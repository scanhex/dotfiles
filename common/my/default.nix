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

  config = {
    my = {
      user = "alex";
      name = "Alex Morozov";
      uid = 1000;
      keys = [ ];
    };
  };
}
