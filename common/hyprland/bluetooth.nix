{pkgs, lib, ...}:
{
    home.packages = [ pkgs.pulseaudio ];
    my.hyprland.extraSettings = [
      {
        bind = [
          {
            _args = [
              (lib.generators.mkLuaInline ''mainMod .. " + SHIFT + B"'')
              (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("pactl set-card-profile $(pactl list cards short | grep -i \"bluez\" | awk '{print $2}') headset-head-unit && sleep 1 && pactl set-card-profile $(pactl list cards short | grep -i \"bluez\" | awk '{print $2}') a2dp-sink-sbc")'')
            ];
          }
        ];
      }
    ];
}
