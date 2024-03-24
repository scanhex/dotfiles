{
	description = "My master nix flake";

	inputs = {
		nixpkgs = {
			url = "github:NixOS/nixpkgs/nixos-23.11";
		};
	};

	outputs = { self, nixpkgs, ... }:
		let 
			lib = nixpkgs.lib;
		in {
			nixosConfigurations = {
				nixos = lib.nixosSystem {
					system = "x86_64-linux";
					modules = [ 
						./configuration.nix
						./home-manager/hm-standalone.nix
					];
				};
			};

		};
}
