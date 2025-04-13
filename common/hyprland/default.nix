{lib, pkgs, config, ...}:
{
  options.my.hyprland.enable = lib.mkEnableOption "hyprland";
  imports = [ ./waybar.nix ./stylix.nix ./bluetooth.nix ];
  config = lib.mkIf config.my.hyprland.enable {
    programs.hyprland.enable = true; # needed?
    programs.hyprlock.enable = true;
    services.playerctld.enable = true;
    my.waybar.enable = true;
    my.stylix.enable = true;
    hm.my.hyprland.enable = true;
  };
}
