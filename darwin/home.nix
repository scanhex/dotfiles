{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{

  home.packages = [ pkgs.unstable.raycast ];
  my.ghostty.enable = true;
  my.ghostty.unmanaged = true;

  imports = lib.my.getHmModules [ ./. ];
}
