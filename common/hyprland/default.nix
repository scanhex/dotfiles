{lib, pkgs, config, ...}:
{
  options.my.hyprland.enable = lib.mkEnableOption "hyprland";
  imports = [ ./waybar.nix ./stylix.nix ];
  config = lib.mkIf config.my.hyprland.enable {
    programs.hyprland.enable = true;
    hm.programs.tofi.enable = true;
    hm.home.packages = [ pkgs.blueman ];
    my.waybar.enable = true;
    my.stylix.enable = true;
  };
}
