
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
            package = pkgs.unstable.zed-editor;
            enable = true;
            userSettings = {
              features = {
                edit_prediction_provider = "copilot";
              };
              show_edit_predictions = true;
              edit_predictions.mode = "eager_preview";
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
