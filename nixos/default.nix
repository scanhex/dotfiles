{config, username, ...}:
{
  imports = [ ./apple-disable-fn.nix ];

  security.sudo.wheelNeedsPassword = false;

  users.users.${username} = {
      isNormalUser = true;
      uid = config.my.uid;
      openssh.authorizedKeys.keys = config.my.keys;
  };
}
