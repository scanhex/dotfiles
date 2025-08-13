{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{

  home.packages = [ pkgs.unstable.raycast ];

  imports = lib.my.getHmModules [ ./. ];
}
