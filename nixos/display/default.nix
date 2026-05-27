{ lib, config, pkgs, ... }:
with lib;
{
  options.my.display.software-control.enable =
    mkEnableOption "Enable the system-wide PipeWire audio stack";

  config = mkIf config.my.display.software-control.enable {
    hardware.i2c.enable = true; 
    hm = {
      home.packages = [ pkgs.ddcutil ];
      my.hyprland.extraSettings = [
        {
          bind = [
            {
              _args = [
                "XF86MonBrightnessUp"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("ddcutil -d 1 setvcp 10 + 10")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }
            {
              _args = [
                "XF86MonBrightnessDown"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("ddcutil -d 1 setvcp 10 - 10")'')
                {
                  locked = true;
                  repeating = true;
                }
              ];
            }
          ];
        }
      ];
    };
  };
}
