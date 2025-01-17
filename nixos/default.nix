{inputs, config, username, ...}:
{
  imports = [ ./apple-disable-fn.nix inputs.home-manager.nixosModules.home-manager ../common ];

  security.sudo.wheelNeedsPassword = false;

  users.users.${username} = {
      isNormalUser = true;
      uid = config.my.uid;
      openssh.authorizedKeys.keys = config.my.keys;
  };
}
