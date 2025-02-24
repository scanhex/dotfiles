{
  inputs,
  username,
  lib,
  ...
}:

{
  imports = [
    (lib.mkAliasOptionModule [ "hm" ] [
      "home-manager"
      "users"
      username
    ])
  ] ++ lib.my.getModules [ ./. ];

  hm.imports = [ ./home.nix ];

  services.earlyoom.enable = true;

  home-manager.extraSpecialArgs = {
    inherit inputs;
  };
  home-manager.useGlobalPkgs = true;
  # do not enable home-manager.useUserPackages, to match standalone home-manager,
  # so home-manager/nixos-rebuild/darwin-rebuild can be used at the same time
  # home-manager.useUserPackages = true;
}
