{
	description = "My master nix flake";

	inputs = {
		nixpkgs = {
			url = "github:NixOS/nixpkgs/nixos-23.11";
		};
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
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
