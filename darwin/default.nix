{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ../common
  ] ++ lib.my.getModules [ ./. ];

  hm.imports = [ ./home.nix ];
  services.tailscale.enable = true;

  security.sudo.extraConfig = ''
     ${config.my.user} ALL=(ALL) NOPASSWD: ALL
   '';

  environment.systemPackages = [];
}
