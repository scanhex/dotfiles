
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.my.zed;
in
{
    options.my.zed = { 
        enable = mkOption { type = types.bool; default = false; };
    };

    config = mkIf cfg.enable { 
        programs.zed-editor = { 
            enable = true;
            package = pkgs.unstable.zed-editor;
        };
    };
}
