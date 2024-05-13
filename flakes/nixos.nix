{ self, withSystem, ... }:

let
  mkNixos =
    { 
			hostname,
			username,
			system ? "x86_64-linux",
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
        inherit lib username;
        inputs = self.inputs;
        pkgs = if (nixpkgs != self.inputs.nixpkgs || config != { } || overlays != [ ]) then customPkgs else pkgs;
      };
      modules = [
				self.inputs.home-manager.nixosModules.home-manager
				{
					home-manager = {
						useGlobalPkgs = true;
						useUserPackages = true;
						backupFileExtension = "hm_bak~";
						extraSpecialArgs = {
							inputs = self.inputs;
						};
						users.${username} = import ../home-manager/home.nix;
					};
				}
      ../nixos
			] 
            ++ modules;
    });
in
{
  flake.nixosConfigurations = {
    wsl = mkNixos {
			username = "nixos";
			hostname = "nixos";
      modules = [ ../hosts/wsl
								self.inputs.nixos-wsl.nixosModules.wsl
			];
    };
  };
}
