{ lib, nixosConfig, ... }:
{
  imports =
    [
      ./git.nix
			./alias.nix
    ]
    ++ lib.optionals nixosConfig.services.xserver.enable [
    ];

  home.stateVersion = nixosConfig.system.stateVersion;
  home.enableNixpkgsReleaseCheck = false;
}
