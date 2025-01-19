{inputs, lib, config, username, ...}:
{
  imports = [ 
  ./apple-disable-fn.nix 
  inputs.home-manager.nixosModules.home-manager 
  ../common ]
  ++ lib.my.getModules [ ./. ];

  hm.imports = lib.my.getHmModules [ ./. ];


  security.sudo.wheelNeedsPassword = false;

  users.users.${username} = {
      isNormalUser = true;
      uid = config.my.uid;
      openssh.authorizedKeys.keys = config.my.keys;
  };
}
