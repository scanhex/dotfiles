{
  config,
  lib,
  pkgs,
  ...
}:

{
  networking.hostName = "mbp";

  hm.my.wezterm.enable = true;
  hm.my.zed.enable = true;
  hm.home.packages = [ pkgs.slack ];

  # For `flakes/darwin-vm.nix`
  # nix.linux-builder.enable = true;
  # Workaround `sandbox-exec: pattern serialization length <number> exceeds maximum (65535)`
  # nix.settings.extra-sandbox-paths = [ "/nix/store" ];
}
