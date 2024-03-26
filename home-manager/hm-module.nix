{ lib, nixosConfig, ... }:
{
  imports =
    [
      ./git.nix
			./alias.nix
    ];

  home.stateVersion = nixosConfig.system.stateVersion;
  home.enableNixpkgsReleaseCheck = false;
}
