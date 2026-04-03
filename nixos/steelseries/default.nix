{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.my.steelseries;
in
{
  options.my.steelseries = {
    enable = mkEnableOption "SteelSeries device access and tooling";

    aerox5 = {
      brightness = mkOption {
        type = types.ints.between 0 100;
        default = 25;
        description = "Brightness for the wired SteelSeries Aerox 5 LEDs.";
      };

      startupLighting = mkOption {
        type = types.enum [ "off" "reactive" "rainbow" "reactive-rainbow" ];
        default = "rainbow";
        description = "Startup lighting mode for the wired SteelSeries Aerox 5.";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.rivalcfg ];

    services.udev.extraRules = ''
      # Allow users in the input group to manage the SteelSeries Aerox 5 via hidraw.
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1038", ATTRS{idProduct}=="1850", GROUP="input", MODE="0660"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="1038", ATTRS{idProduct}=="1850", GROUP="input", MODE="0660"
    '';

    systemd.services.steelseries-aerox5 = {
      description = "Apply SteelSeries Aerox 5 lighting settings";
      wantedBy = [ "multi-user.target" ];
      wants = [ "systemd-udev-settle.service" ];
      after = [ "systemd-udev-settle.service" ];
      path = [ pkgs.rivalcfg ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        env RIVALCFG_PROFILE=1038:1850 \
          rivalcfg \
          --default-lighting ${escapeShellArg cfg.aerox5.startupLighting} \
          --led-brightness ${toString cfg.aerox5.brightness} \
          || true
      '';
    };
  };
}
