{
  lib,
  inputs,
  pkgs,
  ...
}:
{
	nix.settings.experimental-features = [ nix-command flakes ];
}
