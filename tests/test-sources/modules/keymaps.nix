{helpers, ...}: {
  legacy = {
    maps.normal."," = "<cmd>echo \"test\"<cr>";
  };

  legacy-mkMaps = {
    maps = helpers.keymaps.mkMaps {silent = true;} {
      normal."," = "<cmd>echo \"test\"<cr>";
      visual = {
        "<C-a>" = {
          action = "function() print('toto') end";
          lua = true;
          silent = false;
        };
        "<C-z>" = {
          action = "bar";
        };
      };
    };
  };

  legacy-mkModeMaps = {
    maps.normal = helpers.keymaps.mkModeMaps {silent = true;} {
      "," = "<cmd>echo \"test\"<cr>";
      "<C-a>" = {
        action = "function() print('toto') end";
        lua = true;
        silent = false;
      };
      "<leader>b" = {
        action = "bar";
      };
    };
  };

  example = {
    keymaps = [
      {
        key = ",";
        action = "<cmd>echo \"test\"<cr>";
      }
      {
        mode = ["n" "s"];
        key = "<C-p>";
        action = "<cmd>echo \"test\"<cr>";
      }
    ];
  };

  mkMaps = {
    keymaps =
      helpers.keymaps.mkKeymaps
      {
        mode = "x";
        options.silent = true;
      }
      [
        {
          mode = "n";
          key = ",";
          action = "<cmd>echo \"test\"<cr>";
        }
        {
          key = "<C-a>";
          action = "function() print('toto') end";
          lua = true;
          options.silent = false;
        }
        {
          mode = ["n" "v"];
          key = "<C-z>";
          action = "bar";
        }
      ];
  };
}
