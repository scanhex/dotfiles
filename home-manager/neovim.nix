{ pkgs, ... }:
let 
	lazyPlugins = with pkgs.vimPlugins; [
		base46
			cmp-buffer
			cmp-nvim-lsp
			cmp-nvim-lua
			cmp-path
			cmp_luasnip
			comment-nvim
			friendly-snippets
			gitsigns-nvim
			(indent-blankline-nvim.overrideAttrs (old: {
																						src = old.src.override {
																						rev = "9637670896b68805430e2f72cf5d16be5b97a22a";
																						sha256 = "01h49q9j3hh5mi3hxsaipfsc03ypgg14r79fbm6sy63rh8a66jnl";
																						};
																						}))
	luasnip
		nvchad-ui
		nvim-autopairs
		nvim-cmp
		nvim-colorizer-lua
		nvim-lspconfig
		nvim-tree-lua
		(nvim-treesitter.withPlugins (p: [p.cpp p.lua p.python p.nix]))
		nvim-web-devicons
		nvterm
		telescope-fzf-native-nvim
		telescope-nvim
		which-key-nvim
		];
in
{

    xdg.configFile."nvim/lazyPlugins".source = pkgs.vimUtils.packDir {
      lazyPlugins = {
        start = lazyPlugins;
      };
    };

		programs.neovim =
		let
        nvchad = pkgs.vimPlugins.nvchad.overrideAttrs (old: {
          patches = [
            ./nvchad.patch
          ];
          postPatch = ''
            substituteInPlace lua/plugins/init.lua \
            --replace '"NvChad/ui"' '"NvChad/nvchad-ui"' \
            --replace '"L3MON4D3/LuaSnip"' '"L3MON4D3/luasnip"' \
            --replace '"numToStr/Comment.nvim"' '"numToStr/comment.nvim"'
          '';
        });
		in
		{
			enable = true;
			extraPackages = with pkgs; [
				ripgrep
			];
			plugins = with pkgs.vimPlugins; [
				base46
					lazy-nvim
					nvchad
			];
			extraLuaConfig = ''
				dofile("${nvchad}/init.lua")
				'';
		};
    xdg.configFile."nvim/parser".source =
      let
      treesitterParsers = (pkgs.vimPlugins.nvim-treesitter.withPlugins (plugins: with plugins; [
            cpp
            lua
            nix
            yaml
      ])).dependencies;
      parsers = pkgs.symlinkJoin {
        name = "treesitter-parsers";
        paths = treesitterParsers;
      };
    in
      "${parsers}/parser";
}
