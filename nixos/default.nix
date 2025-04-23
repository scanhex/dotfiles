{inputs, lib, config, username, ...}:
{
  imports = [
    ./keyboard.nix
    inputs.home-manager.nixosModules.home-manager
    ../common ]
  ++ lib.my.getModules [ ./. ];

  hm.imports = lib.my.getHmModules [ ./. ];

  services.earlyoom.enable = true;

  security.sudo.wheelNeedsPassword = false;

  users.users.${username} = {
      isNormalUser = true;
      uid = config.my.uid;
      openssh.authorizedKeys.keys = config.my.keys;
  };
}
