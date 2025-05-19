{
  config,
  lib,
  pkgs,
  ...
}:

{
  networking.hostName = "mbp";

  hm.my.bash.bashrcSuffix = "
    export PATH=\"$HOME/.bun/bin:$HOME/.cache/.bun/bin:$PATH\"
    ";


  hm.my.wezterm.enable = true;
  hm.my.wezterm.tmux-binds = false;
  #hm.my.zed.enable = true; zed has issues with immutability. also want the latest version.
  hm.home.packages = [ pkgs.slack pkgs.tailscale ];

  # For `flakes/darwin-vm.nix`
  # nix.linux-builder.enable = true;
  # Workaround `sandbox-exec: pattern serialization length <number> exceeds maximum (65535)`
  # nix.settings.extra-sandbox-paths = [ "/nix/store" ];
}
