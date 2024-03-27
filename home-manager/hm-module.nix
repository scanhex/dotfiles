{ lib, nixosConfig, ... }:
{
  imports =
    [
      ./git.nix
      ./neovim/neovim.nix
			./alias.nix
    ];

  home.stateVersion = nixosConfig.system.stateVersion;
  home.enableNixpkgsReleaseCheck = false;
}
