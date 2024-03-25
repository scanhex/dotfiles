{
	description = "My master nix flake";

	inputs = {
		nixpkgs = {
			url = "github:NixOS/nixpkgs/nixos-23.11";
		};
	};

	outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
		flake-parts.lib.mkFlake { inherit inputs; } {
			systems = [
				"x86_64-linux"
				"aarch64-linux"
			];

			imports = [
				./nixos
				./home-manager/hm-standalone.nix
				./hosts
			];
		};
}
