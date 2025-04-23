# based on: https://gitlab.com/Zaney/zaneyos/-/blob/main/modules/home/waybar.nix?ref_type=heads
{
  pkgs,
  lib,
  host,
  config,
  ...
}: let
  betterTransition = "all 0.3s cubic-bezier(.55,-0.68,.48,1.682)";
in {
  options.my.waybar.enable = lib.mkEnableOption "waybar";
  config = lib.mkIf config.my.waybar.enable {
    hm.home.packages = [ pkgs.pwvucontrol ];
    hm.programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = [
      {
        layer = "bottom";
        position = "bottom";
        mod = "dock";
        exclusive = true;
        "gtk-layer-shell" = true;
        "margin-bottom" = -1;
        passthrough = false;
        height = 41;
        "modules-left" = [
          "custom/os_button"
            "hyprland/workspaces"
            "wlr/taskbar"
        ];
        "modules-center" = [ ];
        "modules-right" = [
            "tray"
            "bluetooth"
            "pulseaudio"
            "network"
            "battery"
            "hyprland/language"
            "clock"
        ];

        "hyprland/language" = {
          format = "{}";
          "format-en" = "ENG";
          "format-ru" = "РУС";
        };

        "hyprland/workspaces" = {
          "icon-size" = 32;
          spacing = 16;
          "on-scroll-up" = "hyprctl dispatch workspace r+1";
          "on-scroll-down" = "hyprctl dispatch workspace r-1";
        };

        "custom/os_button" = {
          format = "";
          "on-click" = "wofi --show drun";
          tooltip = false;
        };

        cpu = {
          interval = 5;
          format = "  {usage}%";
          "max-length" = 10;
        };

        temperature = {
          "hwmon-path-abs" = "/sys/devices/platform/coretemp.0/hwmon";
          "input-filename" = "temp2_input";
          "critical-threshold" = 75;
          tooltip = false;
          "format-critical" = "({temperatureC}°C)";
          format = "({temperatureC}°C)";
        };

        disk = {
          interval = 30;
          format = "󰋊 {percentage_used}%";
          path = "/";
          tooltip = true;
          unit = "GB";
          "tooltip-format" = "Available {free} of {total}";
        };

        memory = {
          interval = 10;
          format = "  {percentage}%";
          "max-length" = 10;
          tooltip = true;
          "tooltip-format" = "RAM - {used:0.1f}GiB used";
        };

        "wlr/taskbar" = {
          format = "{icon}";
          "icon-size" = 28;
          spacing = 3;
          "on-click-middle" = "close";
          "tooltip-format" = "{title}";
          "ignore-list" = [ ];
          "on-click" = "activate";
        };

        tray = {
          "icon-size" = 18;
          spacing = 3;
        };

        clock = {
          format = "      {:%R\n %d.%m.%Y}";
          "tooltip-format" = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "year";
            "mode-mon-col" = 3;
            "weeks-pos" = "right";
            "on-scroll" = 1;
            "on-click-right" = "mode";
            format = {
              months = "<span color='#ffead3'><b>{}</b></span>";
              days = "<span color='#ecc6d9'><b>{}</b></span>";
              weeks = "<span color='#99ffdd'><b>W{}</b></span>";
              weekdays = "<span color='#ffcc66'><b>{}</b></span>";
              today = "<span color='#ff6699'><b><u>{}</u></b></span>";
            };
          };
          actions = {
            "on-click-right" = "mode";
            "on-click-forward" = "tz_up";
            "on-click-backward" = "tz_down";
            "on-scroll-up" = "shift_up";
            "on-scroll-down" = "shift_down";
          };
        };

        network = {
          "format-wifi" = " {icon}";
          "format-ethernet" = "  ";
          "format-disconnected" = "󰌙";
          "format-icons" = [
            "󰤯 "
              "󰤟 "
              "󰤢 "
              "󰤢 "
              "󰤨 "
          ];
        };

        battery = {
          states = {
            good = 95;
            warning = 30;
            critical = 20;
          };
          format = "{icon} {capacity}%";
          "format-charging" = " {capacity}%";
          "format-plugged" = " {capacity}%";
          "format-alt" = "{time} {icon}";
          "format-icons" = [
            "󰂎"
              "󰁺"
              "󰁻"
              "󰁼"
              "󰁽"
              "󰁾"
              "󰁿"
              "󰂀"
              "󰂁"
              "󰂂"
              "󰁹"
          ];
        };

        pulseaudio = {
          "max-volume" = 150;
          "scroll-step" = 10;
          format = "{icon}";
          "tooltip-format" = "{volume}%";
          "format-muted" = " ";
          "format-icons" = {
            default = [
              " "
                " "
                " "
            ];
          };
          "on-click" = "pwvucontrol";
        };
        bluetooth= {
          format = " {status}";
          "format-disabled" = "";
          "format-connected" = " {num_connections} con.";
          "tooltip-format" = "{controller_alias}\t{controller_address}";
          "tooltip-format-connected" = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          "tooltip-format-enumerate-connected" = "{device_alias}\t{device_address}";
          "on-click" = "GDK_DPI_SCALE=0.75 blueman-manager";
        };
      }
      ];
      style = lib.concatStrings [
        ''

          /*base background color*/
          @define-color bg_main rgba(25, 25, 25, 0.65);
      @define-color bg_main_tooltip rgba(0, 0, 0, 0.7);


      /*base background color of selections */
      @define-color bg_hover rgba(200, 200, 200, 0.3);
      /*base background color of active elements */
      @define-color bg_active rgba(100, 100, 100, 0.5);

      /*base border color*/
      @define-color border_main rgba(255, 255, 255, 0.2);

      /*text color for entries, views and content in general */
      @define-color content_main white;
      /*text color for entries that are unselected */
      @define-color content_inactive rgba(255, 255, 255, 0.25);

      * {
        text-shadow: none;
        box-shadow: none;
border: none;
        border-radius: 0;
        font-family: "Segoe UI", "Ubuntu";
        font-weight: 600;
        font-size: 12.7px;


      }

      window#waybar {
background:  @bg_main;
             border-top: 1px solid @border_main;
color: @content_main;
      }

      tooltip {
background: @bg_main_tooltip;
            border-radius: 5px;
            border-width: 1px;
            border-style: solid;
            border-color: @border_main;
      }
      tooltip label{
color: @content_main;
      }

#custom-os_button {
  font-family: "JetBrainsMono Nerd Font";
  font-size: 24px;
  padding-left: 12px;
  padding-right: 20px;
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}
#custom-os_button:hover {
background:  @bg_hover;
color: @content_main;
}

#workspaces {
color: transparent;
       margin-right: 1.5px;
       margin-left: 1.5px;
}
#workspaces button {
padding: 3px;
color: @content_inactive;
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}
#workspaces button.active {
color: @content_main;
       border-bottom: 3px solid white;
}
#workspaces button.focused {
color: @bg_active;
}
#workspaces button.urgent {
background:  rgba(255, 200, 0, 0.35);
             border-bottom: 3px dashed @warning_color;
color: @warning_color;
}
#workspaces button:hover {
background: @bg_hover;
color: @content_main;
}

#taskbar {
}

#taskbar button {
  /* min-width: 130px; */
  border-bottom: 3px solid rgba(255, 255, 255, 0.3);
  margin-left: 2px;
  margin-right: 2px;
  padding-left: 8px;
  padding-right: 8px;
color: white;
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}

#taskbar button.active {
  border-bottom: 3px solid white;
background: @bg_active;
}

#taskbar button:hover {
  border-bottom: 3px solid white;
background: @bg_hover;
color: @content_main;
}

#cpu, #disk, #memory {
padding:3px;
}

#temperature {
color: transparent;
       font-size: 0px;
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}
#temperature.critical {
  padding-right: 3px;
color: @warning_color;
       font-size: initial;
       border-bottom: 3px dashed @warning_color;
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}

#window {
  border-radius: 10px;
  margin-left: 20px;
  margin-right: 20px;
}

#tray{
  margin-left: 5px;
  margin-right: 5px;
}
#tray > .passive {
  border-bottom: none;
}
#tray > .active {
  border-bottom: 3px solid white;
}
#tray > .needs-attention {
  border-bottom: 3px solid @warning_color;
}
#tray > widget {
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}
#tray > widget:hover {
background: @bg_hover;
}

#pulseaudio {
  font-family: "JetBrainsMono Nerd Font";
  padding-left: 5px;
  padding-right: 3px;
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}
#pulseaudio:hover {
background: @bg_hover;
}

#bluetooth {
  font-family: "JetBrainsMono Nerd Font";
  padding-left: 3px;
  padding-right: 3px;
  border-left: 1px solid rgba(255, 255, 255, 0.1);
  border-right: 1px solid rgba(255, 255, 255, 0.1);
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}
#bluetooth:hover {
background: @bg_hover;
}

#network {
  padding-left: 3px;
  padding-right: 3px;
}

#language {
  padding-left: 5px;
  padding-right: 5px;
}

#clock {
  padding-right: 5px;
  padding-left: 5px;
transition: all 0.25s cubic-bezier(0.165, 0.84, 0.44, 1);
}
#clock:hover {
background: @bg_hover;
}
''
      ];
    };
  };
}
