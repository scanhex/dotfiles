{ self, inputs, ... }:
{
	flake.nixosConfigurations =
		let
		mkHost =
		{
			hostname,
			username,
			nixpkgs ? inputs.nixpkgs,
			system ? "x86_64-linux",
			defaultModules ? true,
			hmEnable ? true,
			extraModules ? [ ],
		}:
	nixpkgs.lib.nixosSystem {
		inherit system;
		specialArgs = {
			inherit inputs self username;
		};
		modules =
			[
# nixos setup
			{ networking.hostName = "${hostname}"; }
# disko module
#		inputs.disko.nixosModules.disko
			]
			++ nixpkgs.lib.optionals hmEnable [
# home-manager module
			inputs.home-manager.nixosModules.home-manager
			{
				home-manager = {
					useGlobalPkgs = true;
					useUserPackages = true;
					backupFileExtension = "hm_bak~";
					extraSpecialArgs = {
						inherit inputs;
					};
					users.${username} = import ../home-manager/hm-module.nix;
				};
			}
			]
				++ nixpkgs.lib.optionals defaultModules [ self.nixosModules.default ]
				++ extraModules;
	};
	in
	{
# nix build .#nixosConfigurations.wsl.config.system.build.installer
		wsl = mkHost {
			username = "nixos";
			hostname = "nixos";
			defaultModules = false;
			extraModules = [
				./wsl
				inputs.nixos-wsl.nixosModules.wsl
			];
		};
	};
}
