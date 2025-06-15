{config, pkgs, lib, ...}:
{
  options.my.hyprland.enable = lib.mkEnableOption "hyprland";
  options.my.hyprland.extraConfig = lib.mkOption {
    default = "";
    type = lib.types.lines;
    description = "Extra configuration for hyprland";
  };

  imports = [ ./bluetooth.nix ];

  config = lib.mkIf config.my.hyprland.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig = 
      lib.concatStringsSep "\n" [ (lib.readFile ./hyprland.conf) config.my.hyprland.extraConfig ];
    };
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = true;
          grace = 0;
          hide_cursor = true;
          no_fade_in = false;
        };

        background = [
        {
          path = toString ./outer-wilds.png;
        }
        ];

        input-field = [
        {
          size = "200, 50";
          position = "0, -80";
          monitor = "";
          dots_center = true;
          fade_on_empty = false;
          font_color = "rgb(202, 211, 245)";
          inner_color = "rgb(91, 96, 120)";
          outer_color = "rgb(24, 25, 38)";
          outline_thickness = 5;
          placeholder_text = "<span foreground=\"##cad3f5\">Password...</span>";
          shadow_passes = 2;
        }
        ];
      };
    };
    programs.tofi.enable = true;
    home.packages = [
      pkgs.blueman
      pkgs.xorg.xrdb
      pkgs.hyprshot
      (pkgs.writeShellScriptBin "toggle-pwvu-control" ''
         pat='pwvucontrol'          
         if pgrep -f "$pat" >/dev/null; then
           pkill -f "$pat"          
         else
           pwvucontrol & disown     
         fi
      '')
      (pkgs.writeShellScriptBin "toggle-blueman" ''
        if pgrep -f blueman-manager > /dev/null; then
          pkill -f blueman-manager
        else
          GDK_DPI_SCALE=0.75 blueman-manager & disown
        fi
      '')
    ];
    services.dunst.enable = true;
    xresources.properties = {
      "Xft.dpi" = 155;
      "Xft.autohint" = 0;
      "Xft.lcdfilter" = "lcddefault";
      "Xft.hintstyle" = "hintfull";
      "Xft.hinting" = 1;
      "Xft.antialias" = 1;
      "Xft.rgba" = "rgb";
    };
    home.pointerCursor = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
      size = 24;
      gtk.enable = true;
      x11.enable = true; # Important for X applications
    };
  };
}
