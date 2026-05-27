{inputs, pkgs, ...}:
{
# TODO: pull this in source, make animations faster
  hm.home.packages = [
    inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
