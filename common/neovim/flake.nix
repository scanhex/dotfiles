{
  description = "scanhex's portable Neovim + Lazy setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    cp-library = {
      url = "github:scanhex/cp-library";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, nixpkgs-unstable, neovim-nightly-overlay, cp-library, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      perSystem = (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          unstable = import nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };

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
            unstable.vimPlugins.nvim-treesitter.withAllGrammars
            nvim-treesitter-textobjects
            unstable.vimPlugins.nvim-treesitter-context
            plenary-nvim
            telescope-fzf-native-nvim
            telescope-nvim
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
            nvim-dap
          ];

          mkEntry = drv:
            if pkgs.lib.isDerivation drv then {
              name = pkgs.lib.getName drv;
              path = drv;
            } else
              drv;

          lazyPath = pkgs.linkFarm "lazy-plugins" (map mkEntry lazyPlugins);

          extraTools = with pkgs; [
            ripgrep
            clang
            pyright
            lua-language-server
            nil
            curl # neocmakelsp
            rust-analyzer
            lazygit
          ];

          extraEnv = pkgs.buildEnv {
            name = "neovim-extra-tools";
            paths = extraTools;
          };

          tsParsers = (unstable.vimPlugins.nvim-treesitter.withPlugins (p:
            with p; [
              cpp
              cmake
              rust
              lua
              nix
              yaml
              python
              html
              json
              gitignore
              bash
              gitcommit
              git_config
              diff
            ])).dependencies;

          tsBundle = pkgs.symlinkJoin {
            name = "treesitter-parsers";
            paths = tsParsers;
          };

          luaRc = ''
            lazyPath        = "${lazyPath}"
            package.path    = package.path .. ";${./init.lua/lua}/?.lua"

            vim.deprecate   = function() end  -- silence warnings

            clangd_path = "${pkgs.clang-tools_19}/bin/clangd"
            codelldb_path   = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb"
            cp_library_nix  = "${cp-library}"

            require("theprimeagen/set")
            require("theprimeagen/remap")

            require("lazy").setup({
              defaults = { lazy = false },
              dev = {
                path      = lazyPath,
                patterns  = { "." },
                fallback  = true,
              },
              spec = {
                { "nvim-telescope/telescope-fzf-native.nvim", enabled = true },
                -- managed by nix instead of mason:
                { "williamboman/mason.nvim",            enabled = false },
                { "williamboman/mason-lspconfig.nvim",  enabled = false },
                { import = "plugin" },
                { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = {} } },
              },
            })

            vim.cmd.colorscheme("catppuccin")
          '';

          nvimWrapped = pkgs.wrapNeovimUnstable
            pkgs.neovim-unwrapped 
            (pkgs.neovimUtils.makeNeovimConfig {
              wrapRc = true;
              luaRcContent = luaRc;
              plugins = [ pkgs.vimPlugins.lazy-nvim ]; # others handled by Lazy
            });

          appName = "nvim-flake"; # isolated cache: ~/.local/share/nvim-flake/…

          runner = pkgs.writeShellScriptBin "nvim" ''
                      set -euo pipefail
                      unset VIMINIT

                      export PATH=${extraEnv}/bin:$PATH
                      export NVIM_APPNAME=${appName}
                      export NIX_LAZY_DEV_PATH="${lazyPath}"
                      export NVIM_TREESITTER_PARSERS="${tsBundle}"
            #          export XDG_CONFIG_HOME=/dev/null
                      export XDG_CONFIG_DIRS=""
            #          export XDG_DATA_HOME=/dev/null
                      export XDG_DATA_DIRS=""

                      exec ${nvimWrapped}/bin/nvim \
                        --cmd "set rtp^=${./init.lua}" "$@"
          '';

          alexNeovimPackage = pkgs.buildEnv {
            name = "scanhex-neovim";
            meta = {
              description = "scanhex's portable Neovim + Lazy setup";
              maintainers = [ "scanhex" ];
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.all;
            };
            paths = [ runner extraEnv lazyPath tsBundle ];
          } // {
            lua = neovim-nightly-overlay.packages.${system}.default.lua;
          };
        in {
          packages.default = alexNeovimPackage;

          apps.default = {
            type = "app";
            program = "${alexNeovimPackage}/bin/nvim";
          };

          devShells.default =
            pkgs.mkShell { packages = [ alexNeovimPackage ]; };
        });

    in {
      packages = forAllSystems (system: (perSystem system).packages);
      apps = forAllSystems (system: (perSystem system).apps);
      devShells = forAllSystems (system: (perSystem system).devShells);
    };
}
