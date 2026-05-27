{config, pkgs, lib, ...}:
let
  settings = import ./settings.nix { inherit lib; };
in
{
  options.my.hyprland.enable = lib.mkEnableOption "hyprland";
  options.my.hyprland.extraSettings = lib.mkOption {
    default = [ ];
    type = lib.types.listOf lib.types.attrs;
    description = "Extra Hyprland Lua settings fragments.";
  };

  imports = [ ./bluetooth.nix ];

  config = lib.mkIf config.my.hyprland.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      configType = "lua";
      settings = lib.mkMerge ([ settings ] ++ config.my.hyprland.extraSettings);
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
    services.hyprsunset = {
      enable = true;
      settings = {
        profile = [
          {
            time = "06:00";
            temperature = 6500;
            gamma = 100;
          }
          {
            time = "19:00";
            temperature = 3500;
          }
        ];
      };
    };
    programs.tofi.enable = true;
    home.packages = [
      pkgs.blueman
      pkgs.xrdb
      pkgs.hyprshot
      pkgs.xdg-desktop-portal-gtk
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
      (pkgs.writeShellScriptBin "reconnect-wh1000xm6" ''
        d=80:99:E7:D4:1C:BC
        u=''${d//:/_}
        bluetoothctl disconnect "$d"
        sleep 0.1
        bluetoothctl --timeout 10 connect "$d" || {
          bluetoothctl power off
          sleep 0.1
          bluetoothctl power on
          sleep 0.1
          bluetoothctl --timeout 12 connect "$d"
        }
        CARD="bluez_card.$u"
        pactl set-card-profile "$CARD" a2dp-sink || true
        s=$(pactl list short sinks | awk -v id="$u" '$2 ~ ("bluez_output." id){print $2}' | head -n1)
        [ -n "$s" ] && pactl set-default-sink "$s" && pactl list short sink-inputs | awk '{print $1}' | xargs -r -I{} pactl move-sink-input {} "$s"
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
