{lib, pkgs, config, ...}:
{
  options.my.hyprland.enable = lib.mkEnableOption "hyprland";
  imports = [ ./waybar.nix ./stylix.nix ];
  config = lib.mkIf config.my.hyprland.enable {
    programs.hyprland.enable = true;
    services.playerctld.enable = true;
    hm.programs.tofi.enable = true;
    hm.home.packages = [ pkgs.blueman pkgs.xorg.xrdb ];
    my.waybar.enable = true;
    my.stylix.enable = true;
    hm.xresources.properties = {
      "Xft.dpi" = 155;
      "Xft.autohint" = 0;
      "Xft.lcdfilter" = "lcddefault";
      "Xft.hintstyle" = "hintfull";
      "Xft.hinting" = 1;
      "Xft.antialias" = 1;
      "Xft.rgba" = "rgb";
    };
    hm.home.pointerCursor = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
      size = 24;
      gtk.enable = true;
      x11.enable = true; # Important for X applications
    };
  };
}
