{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      neovim
      lua-language-server
      nixd
      nixfmt
      stylua
    ];

    environment.variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  dotnix.modules.home =
    { pkgs, lib, ... }:
    let
      treesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (
        g: with g; [
          bash
          json
          lua
          luadoc
          markdown
          markdown_inline
          nix
          query
          regex
          toml
          vim
          vimdoc
          yaml
        ]
      );
      # LazyVim discovers installed parsers through install_dir, not runtimepath.
      parserBundle = pkgs.symlinkJoin {
        name = "lazyvim-treesitter-parsers";
        paths = [ treesitter ] ++ treesitter.dependencies;
      };
      plugins = with pkgs.vimPlugins; {
        inherit LazyVim;
        "grug-far.nvim" = grug-far-nvim;
        "nui.nvim" = nui-nvim;
        "bufferline.nvim" = bufferline-nvim;
        catppuccin = catppuccin-nvim;
        "flash.nvim" = flash-nvim;
        "lazy.nvim" = lazy-nvim;
        "lazydev.nvim" = lazydev-nvim;
        "noice.nvim" = noice-nvim;
        "persistence.nvim" = persistence-nvim;
        "snacks.nvim" = snacks-nvim;
        "todo-comments.nvim" = todo-comments-nvim;
        "tokyonight.nvim" = tokyonight-nvim;
        "trouble.nvim" = trouble-nvim;
        "ts-comments.nvim" = ts-comments-nvim;
        "which-key.nvim" = which-key-nvim;
        "gitsigns.nvim" = gitsigns-nvim;
        "nvim-lint" = nvim-lint;
        "nvim-lspconfig" = nvim-lspconfig;
        "plenary.nvim" = plenary-nvim;
        "lualine.nvim" = lualine-nvim;
        "mini.ai" = mini-ai;
        "mini.icons" = mini-icons;
        "mini.pairs" = mini-pairs;
        "nvim-treesitter" = parserBundle;
        "nvim-treesitter-textobjects" = nvim-treesitter-textobjects;
        "friendly-snippets" = friendly-snippets;
        "blink.cmp" = blink-cmp;
        "conform.nvim" = conform-nvim;
        "nvim-ts-autotag" = nvim-ts-autotag;
      };
      # lazy.nvim resolves require() back to plugins by directory basename.
      pluginDirectory = pkgs.linkFarm "lazyvim-plugins" (
        lib.mapAttrsToList (name: path: { inherit name path; }) plugins
      );
      registryLua = pkgs.writeText "lazyvim-registry.lua" ''
        return {
          nixpkgs = "${pkgs.path}",
          install_dir = "${pluginDirectory}/nvim-treesitter",
          plugins = ${
            lib.generators.toLua { } (lib.mapAttrs (name: _: "${pluginDirectory}/${name}") plugins)
          },
        }
      '';
      nvimConfig = pkgs.runCommand "lazyvim-config" { } ''
        mkdir -p $out
        cp ${./neovim/init.lua} $out/init.lua
        cp -r ${./neovim/lua} $out/lua
        chmod -R u+w $out
        cp ${registryLua} $out/lua/config/registry.lua
      '';
    in
    {
      xdg.configFile.nvim.source = nvimConfig;
    };
}
