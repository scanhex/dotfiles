{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{

  home.packages = [ pkgs.raycast ];

  imports = lib.my.getHmModules [ ./. ];
}
