{ self, lib, withSystem, ... }:

let
  mkHome =
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
    self.inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = if (nixpkgs != self.inputs.nixpkgs || config != { } || overlays != [ ]) then customPkgs else pkgs;
      extraSpecialArgs = {
        lib = import (self.inputs.home-manager + "/modules/lib/stdlib-extended.nix") lib;
        inputs = self.inputs;
      };
      modules = [
        {
          news.display = "silent";
          news.json = lib.mkForce { };
          news.entries = lib.mkForce [ ];
          # set the same option as home-manager in nixos/nix-darwin, to generate the same derivation
          nix.package = pkgs.nix;
        }
        ../common/home.nix
      ] ++ modules;
    });
in
{
  flake.homeConfigurations = {
    amorozov = mkHome { 
      modules = [
      {
        home.username = "amorozov";
        home.homeDirectory = "/home/amorozov";
      }
      ./home-manager-work.nix
      ];
    };
    alex = mkHome { 
	    modules = [
	    {
		    home.username = "alex";
		    home.homeDirectory = "/home/alex";
	    }
      ./home-manager-work.nix
      ];
    };
  };

  perSystem = { self', inputs', pkgs, ... }: {
    packages.home-manager = inputs'.home-manager.packages.default;
    apps.init-home.program = pkgs.writeShellScriptBin "init-home" ''
      ${self'.packages.home-manager}/bin/home-manager --extra-experimental-features "nix-command flakes" switch --flake "${self}" "$@"
    '';
  };
}
