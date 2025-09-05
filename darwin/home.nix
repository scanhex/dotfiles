{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{

  home.packages = [ pkgs.unstable.raycast ];
  my.ghostty.enable = true;
  my.ghostty.unmanaged = true;

  nix = {
    enable = true;
    settings = {
      trusted-users = [ config.my.user ];
      use-xdg-base-directories = true;
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  imports = lib.my.getHmModules [ ./. ];
}
