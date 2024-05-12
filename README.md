# dotfiles
## Installation option 1
1. Install nix and nix-instantiate automatically via `bash <(curl -L https://nixos.org/nix/install) --no-daemon`
2. Run `nix build .#init-home`
3. Run `nix-env --uninstall nix` (because it would conflict with this flake's nix)
4. Run `./result/activate`
## Installation option 2
1. Download statically built nix binary, 
2. Via nix, make commands like nix-instantiate available
3. Add them both to path
4. Run `nix run .#init-home`, you don't need the above in path anymore
