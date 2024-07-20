{inputs, config, pkgs, lib, ...}:
let 
	lazyPlugins = with pkgs.vimPlugins; [
		base46
        cmp-buffer
        cmp-nvim-lsp
        cmp-path
        cmp_luasnip
        comment-nvim
        friendly-snippets
        gitsigns-nvim
        luasnip
		nvim-cmp
		nvim-lspconfig
        nvim-notify
#		nvim-treesitter.withAllGrammars
		nvim-treesitter-textobjects
		nvim-treesitter-context
        plenary-nvim
		telescope-fzf-native-nvim
		telescope-nvim
		#telescope-file-browser-nvim - I'm using my own fork

        bigfile-nvim
		copilot-vim
		catppuccin-nvim
        overseer-nvim
        dressing-nvim
        toggleterm-nvim
        neodev-nvim 
        harpoon
        gitsigns-nvim
        diffview-nvim
        lazygit-nvim
        nvim-surround
        zen-mode-nvim
        rustaceanvim
        refactoring-nvim
        #trouble-nvim -- had some breaking changes post 24.05 release
        #cmake-tools-nvim -- broken in nixpkgs 24.05, super laggy
		];
mkEntryFromDrv = drv:
            if lib.isDerivation drv then
              { name = "${lib.getName drv}"; path = drv; }
            else
              drv;
lazyPath = pkgs.linkFarm "lazy-plugins" (builtins.map mkEntryFromDrv lazyPlugins);
in
{
	programs.neovim = {
		enable = true;
        defaultEditor = true;
        package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
		extraPackages = with pkgs; [
			ripgrep
            clang
            pyright
            lua-language-server
            nil
            neocmakelsp
            pkgs.rust-analyzer
            lazygit
		];
		plugins = with pkgs.vimPlugins; [
			lazy-nvim
		];
		extraLuaConfig =  ''
          nixProfilePath = "${config.home.profileDirectory}";
	      require("theprimeagen/set")
	      require("theprimeagen/remap")
          require("lazy").setup({
            defaults = {
              lazy = false,
            },
            dev = {
              path = "${lazyPath}",
              patterns = { "." },
              fallback = true,
            },
            spec = {
              -- The following configs are needed for fixing lazyvim on nix
              -- force enable telescope-fzf-native.nvim
              { "nvim-telescope/telescope-fzf-native.nvim", enabled = true },
              -- disable mason.nvim, use programs.neovim.extraPackages
              { "williamboman/mason-lspconfig.nvim", enabled = false },
              { "williamboman/mason.nvim", enabled = false },
              -- import/override with your plugins
              { import = "plugins" },
              -- treesitter handled by my.neovim.treesitterParsers, put this line at the end of spec to clear ensure_installed
              { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = {} } },
			  -- $ { cfg.extraSpec }  
			},
          })
		vim.cmd.colorscheme "catppuccin"
        '';
	};
    xdg.configFile."nvim/parser".source =
      let
      treesitterParsers = (pkgs.vimPlugins.nvim-treesitter.withPlugins (plugins: with plugins; [
            cpp
            cmake
            rust
            lua
            nix
            yaml
            python
            html
      ])).dependencies;
      parsers = pkgs.symlinkJoin {
        name = "treesitter-parsers";
        paths = treesitterParsers;
      };
    in
      "${parsers}/parser";
    xdg.configFile."nvim/lua/plugins".source = ./init.lua/after/plugin;
    xdg.configFile."nvim/lua/theprimeagen/set.lua".source = ./init.lua/lua/theprimeagen/set.lua;
    xdg.configFile."nvim/lua/theprimeagen/remap.lua".source = ./init.lua/lua/theprimeagen/remap.lua;
}
