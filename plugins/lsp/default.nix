{
  lib,
  helpers,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.plugins.lsp;
in
{
  imports = [ ./language-servers ];

  options = {
    plugins.lsp = {
      enable = mkEnableOption "neovim's built-in LSP";

      package = lib.mkPackageOption pkgs [
        "vimPlugins"
        "nvim-lspconfig"
      ] { };

      keymaps = {
        silent = mkOption {
          type = types.bool;
          description = "Whether nvim-lsp keymaps should be silent";
          default = false;
        };

        diagnostic = mkOption {
          type = with types; attrsOf (either str attrs);
          description = "Mappings for `vim.diagnostic.<action>` functions to be added when an LSP is attached.";
          example = {
            "<leader>k" = "goto_prev";
            "<leader>j" = "goto_next";
          };
          default = { };
        };

        lspBuf = mkOption {
          type = with types; attrsOf (either str attrs);
          description = "Mappings for `vim.lsp.buf.<action>` functions to be added when an LSP it attached.";
          example = {
            "gd" = "definition";
            "gD" = "references";
            "gt" = "type_definition";
            "gi" = "implementation";
            "K" = "hover";
          };
          default = { };
        };

        extra = mkOption {
          type = with types; listOf helpers.keymaps.deprecatedMapOptionSubmodule;
          apply = map helpers.keymaps.removeDeprecatedMapAttrs;
          description = ''
            Extra keymaps to register when an LSP is attached.
            This can be used to customise LSP behaviour, for example with "telescope" or the "Lspsaga" plugin, as seen in the examples.
          '';
          example = [
            {
              key = "<leader>lx";
              action = "<CMD>LspStop<Enter>";
            }
            {
              key = "<leader>ls";
              action = "<CMD>LspStart<Enter>";
            }
            {
              key = "<leader>lr";
              action = "<CMD>LspRestart<Enter>";
            }
            {
              key = "gd";
              action.__raw = "require('telescope.builtin').lsp_definitions()";
            }
            {
              key = "K";
              action = "<CMD>Lspsaga hover_doc<Enter>";
            }
          ];
          default = [ ];
        };
      };

      enabledServers = mkOption {
        type =
          with types;
          listOf (oneOf [
            str
            (submodule {
              options = {
                name = mkOption {
                  type = str;
                  description = "The server's name";
                };

                capabilities = mkOption {
                  type = types.nullOr (types.attrsOf types.bool);
                  description = "Control resolved capabilities for the language server.";
                  default = null;
                  example = {
                    documentFormattingProvider = false;
                  };
                };

                extraOptions = mkOption {
                  type = attrs;
                  description = "Extra options for the server";
                };
              };
            })
          ]);
        description = "A list of enabled LSP servers. Don't use this directly.";
        default = [ ];
        internal = true;
        visible = false;
      };

      inlayHints = mkOption {
        description = ''
          Whether to enable LSP inlay-hints.
          Only affects language servers with inlay-hints support.

          See [`:h lsp-inlay_hint`](https://neovim.io/doc/user/lsp.html#lsp-inlay_hint).
        '';
        type = types.bool;
        default = false;
        example = true;
      };

      onAttach = mkOption {
        type = types.lines;
        description = "A lua function to be run when a new LSP buffer is attached. The argument `client` and `bufnr` is provided.";
        default = "";
      };

      capabilities = mkOption {
        type = types.lines;
        description = "Lua code that modifies inplace the `capabilities` table.";
        default = "";
      };

      setupWrappers = mkOption {
        type = with types; listOf (functionTo str);
        description = "Code to be run to wrap the setup args. Takes in an argument containing the previous results, and returns a new string of code.";
        default = [ ];
      };

      preConfig = mkOption {
        type = types.lines;
        description = "Code to be run before loading the LSP. Useful for requiring plugins";
        default = "";
      };

      postConfig = mkOption {
        type = types.lines;
        description = "Code to be run after loading the LSP. This is an internal option";
        default = "";
      };
    };
  };

  config =
    let
      runWrappers =
        wrappers: s: if wrappers == [ ] then s else (head wrappers) (runWrappers (tail wrappers) s);
      updateCapabilities =
        let
          servers = builtins.filter (
            server: server.capabilities != null && server.capabilities != { }
          ) cfg.enabledServers;
        in
        lib.concatMapStringsSep "\n" (
          server:
          let
            updates = lib.concatMapStringsSep "\n" (name: ''
              client.server_capabilities.${name} = ${helpers.toLuaObject server.capabilities.${name}}
            '') (builtins.attrNames server.capabilities);
          in
          ''
            if client.name == "${server.name}" then
              ${updates}
            end
          ''
        ) servers;
    in
    mkIf cfg.enable {
      extraPlugins = [ cfg.package ];

      keymapsOnEvents.LspAttach =
        let
          mkMaps =
            prefix:
            mapAttrsToList (
              key: action:
              let
                actionStr = if isString action then action else action.action;
                actionProps = if isString action then { } else filterAttrs (n: v: n != "action") action;
              in
              {
                mode = "n";
                inherit key;
                action = helpers.mkRaw (prefix + actionStr);

                options = {
                  inherit (cfg.keymaps) silent;
                } // actionProps;
              }
            );
        in
        (mkMaps "vim.diagnostic." cfg.keymaps.diagnostic)
        ++ (mkMaps "vim.lsp.buf." cfg.keymaps.lspBuf)
        ++ cfg.keymaps.extra;

      # Enable inlay-hints
      plugins.lsp.onAttach = mkIf cfg.inlayHints ''
        -- LSP Inlay Hints {{{
        if client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
        -- }}}
      '';

      # Enable all LSP servers
      extraConfigLua = ''
        -- LSP {{{
        do
          ${cfg.preConfig}

          local __lspServers = ${helpers.toLuaObject cfg.enabledServers}
          -- Adding lspOnAttach function to nixvim module lua table so other plugins can hook into it.
          _M.lspOnAttach = function(client, bufnr)
            ${updateCapabilities}

            ${cfg.onAttach}
          end
          local __lspCapabilities = function()
            capabilities = vim.lsp.protocol.make_client_capabilities()

            ${cfg.capabilities}

            return capabilities
          end

          local __setup = ${runWrappers cfg.setupWrappers "{
            on_attach = _M.lspOnAttach,
            capabilities = __lspCapabilities()
          }"}

          for i,server in ipairs(__lspServers) do
            if type(server) == "string" then
              require('lspconfig')[server].setup(__setup)
            else
              local options = ${runWrappers cfg.setupWrappers "server.extraOptions"}

              if options == nil then
                options = __setup
              else
                options = vim.tbl_extend("keep", options, __setup)
              end

              require('lspconfig')[server.name].setup(options)
            end
          end

          ${cfg.postConfig}
        end
        -- }}}
      '';
    };
}
