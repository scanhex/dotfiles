{pkgs}:
{
    home.packages = [ pkgs.pulseaudio ];
    my.hyprland.extraConfig = "
bind = $mainMod SHIFT, B, exec, pactl set-card-profile $(pactl list cards short | grep -i \"bluez\" | awk '{print $2}') headset-head-unit && sleep 1 && pactl set-card-profile $(pactl list cards short | grep -i \"bluez\" | awk '{print $2}') a2dp-sink-sbc
";
}
