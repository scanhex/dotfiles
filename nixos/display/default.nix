{ lib, config, ... }:
with lib;
{
  options.my.display.software-control.enable =
    mkEnableOption "Enable the system-wide PipeWire audio stack";

  config = mkIf config.my.display.software-control.enable {
    hardware.i2c.enable = true; 
    home-manager.users.${config.my.user}.packages = with config.pkgs; [
      ddcutil 
    ];
    my.hyprland.extraConfig = "
      bindel = , XF86MonBrightnessUp,   exec, ddcutil -d 1 setvcp 10 + 10
      bindel = , XF86MonBrightnessDown, exec, ddcutil -d 1 setvcp 10 - 10
      ";
  };
}
