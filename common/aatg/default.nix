{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
cfg = config.my.aatg;
in {
  # Genshin Impact Launcher
  options.my.aatg = {
    installLibs = mkOption { type = types.bool; default = false; };
    blockMihoyoTelemetry = mkOption { type = types.bool; default = false; };
  };

  config.my.lutris.extraLibraries = mkIf cfg.installLibs [ pkgs.libadwaita pkgs.gtk4 ];

  config.networking = optionalAttrs cfg.blockMihoyoTelemetry {
    hosts = {
      "0.0.0.0" = [
        "overseauspider.yuanshen.com"
        "log-upload-os.hoyoverse.com"
        "log-upload-os.mihoyo.com"
        "dump.gamesafe.qq.com"

        "log-upload.mihoyo.com"
        "devlog-upload.mihoyo.com"
        "uspider.yuanshen.com"
        "sg-public-data-api.hoyoverse.com"
        "public-data-api.mihoyo.com"

        "prd-lender.cdp.internal.unity3d.com"
        "thind-prd-knob.data.ie.unity3d.com"
        "thind-gke-usc.prd.data.corp.unity3d.com"
        "cdp.cloud.unity3d.com"
        "remote-config-proxy-prd.uca.cloud.unity3d.com"
      ];
    };
  };
}
