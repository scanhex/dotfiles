{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.my.mihoyo-telemetry;
in {
  options.my.mihoyo-telemetry = {
    block = mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to block miHoYo telemetry servers.
      '';
    };
  };

  config = mkIf cfg.block {
    networking.hosts = {
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
