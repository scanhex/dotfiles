{lib, config, ...}:
{
  options.my.pipewire = {
    enable = lib.mkEnableOption "PipeWire audio service";
  };
  config.services.pipewire = lib.mkIf config.my.pipewire.enable {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.extraConfig."51-force-a2dp.lua" = ''
      bluetooth_policy.policy["media-role.use-headset-profile"] = false
      monitor.bluez.properties = {
        bluez5.roles = [ "a2dp_sink" "a2dp_source" ]  -- Disable low-quality hands-free profiles for Bluetooth headphones
      }
    '';
  };
}
