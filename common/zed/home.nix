
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
            # Using custom zed package copied from unstable nixpkgs; can be removed after next unstable update
            package = pkgs.zed-editor;
            userSettings = {
              features = {
                copilot = false;
              };
              telemetry = {
                metrics = false;
              };
              vim_mode = true;
              ui_font_size = 16;
              buffer_font_size = 16;
            };
        };
    };
}
