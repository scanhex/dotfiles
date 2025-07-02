{ lib, config, ... }:
with lib;
{
  options.my.pipewire.enable =
    mkEnableOption "Enable the system-wide PipeWire audio stack";

  config = mkIf config.my.pipewire.enable {
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;

      wireplumber.extraConfig."51-force-a2dp" = {
        "bluetooth_policy".policy."media-role.use-headset-profile" = false;
        "monitor.bluez.properties" = {
          # Keep only the high-quality A2DP roles
          "bluez5.roles"       = [ "a2dp_sink" "a2dp_source" ];
          # Optional quality / convenience tweaks
          "bluez5.auto-connect" = [ "a2dp_sink" ];   # switch to A2DP on connect
          "bluez5.enable-sbc-xq" = true;             # better SBC quality
          "bluez5.enable-msbc"  = false;             # no HFP/HSP fallback
        };
      };
    };
  };
}

