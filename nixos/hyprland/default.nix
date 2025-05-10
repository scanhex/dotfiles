{lib, pkgs, config, ...}:
{
  options.my.hyprland.enable = lib.mkEnableOption "hyprland";
  imports = [ ./waybar.nix ];
  config = lib.mkIf config.my.hyprland.enable {
    my.waybar.enable = true;
    #my.stylix.enable = true;
    hm.my.hyprland.enable = true;
    programs = lib.optionalAttrs config.my.hyprland.enable {
      hyprland.enable = true; # needed?
      hyprlock.enable = true;
    };
    services = lib.optionalAttrs config.my.hyprland.enable {
      playerctld.enable = true;
    };
  };
}
