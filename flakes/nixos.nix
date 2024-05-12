{ self, withSystem, ... }:

let
  mkNixos =
    { system ? "x86_64-linux"
    , nixpkgs ? self.inputs.nixpkgs
    , config ? { }
    , overlays ? [ ]
    , modules ? [ ]
    }:
    withSystem system ({ lib, pkgs, system, ... }:
    let
      customPkgs = import nixpkgs (lib.recursiveUpdate
        {
          inherit system;
          overlays = [ self.overlays.default ] ++ overlays;
          config.allowUnfree = true;
        }
        {
          inherit config;
        }
      );
    in
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit lib;
        inputs = self.inputs;
        pkgs = if (nixpkgs != self.inputs.nixpkgs || config != { } || overlays != [ ]) then customPkgs else pkgs;
      };
      modules = [
        ../nixos
      ] ++ modules;
    });
in
{
  flake.nixosConfigurations = {
    wsl = mkNixos {
      modules = [ ../hosts/wsl.nix ];
    };
  };
}
