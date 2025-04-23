{
  self,
  inputs,
  withSystem,
  ...
}:
let mkDarwin = {
  username,
  system ? "aarch64-darwin",
  nixpkgs ? self.inputs.nixpkgs,
  config ? { },
  overlays ? [ ],
  modules ? [ ]
}:
withSystem system ({ lib, pkgs, system, ... }:
  let
  customPkgs = import nixpkgs (lib.recursiveUpdate
    {
      inherit system;
      overlays = (import ../overlays {inherit inputs system; }) ++ overlays;
      config = {
        allowUnfree = true;
      };
    } { inherit config; }
  );
  in
  inputs.darwin.lib.darwinSystem {
    inherit system;
    specialArgs = {
      inherit lib username;
      inputs = self.inputs;
      pkgs = customPkgs;
    };
    modules = [
      ../darwin
  				{
   					home-manager = {
    						useGlobalPkgs = true;
    						useUserPackages = true;
    						backupFileExtension = "hm_bak~";
    						extraSpecialArgs = {
     							inputs = self.inputs;
    						};
   					};
  				}
 			]
    ++ modules;
  });
in
{
  flake.darwinConfigurations = {
    mbp = mkDarwin {
      username = "alex";
      modules = [ ../hosts/mbp.nix ];
    };
  };
}
