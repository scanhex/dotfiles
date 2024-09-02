{config, ...}:
{
  imports = [ ./apple-disable-fn.nix ];

  users.users.${config.my.user} = {
      isNormalUser = true;
      uid = config.my.uid;
      openssh.authorizedKeys.keys = config.my.keys;
  };
}
