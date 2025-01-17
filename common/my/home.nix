{
  inputs,
  lib,
  ...
}:

let
  inherit (lib) mkOption types;
in
{
  options.my = {
    user = mkOption { type = types.str; };
    name = mkOption { type = types.str; };
    uid = mkOption { type = types.int; };
    keys = mkOption { type = types.listOf types.singleLineStr; };
  };

  config.my = {
      user = "alex";
      name = "Alex Morozov";
      uid = 1000;
      keys = [ 
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOLkF8s/irjRBKOmZ72RvpipuXl5ZYhd86cEWYkL/+GX" # alex_master
      ];
  };
}
