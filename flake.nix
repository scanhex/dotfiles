{
	description = "My master nix flake";

    inputs = {
        nixpkgs = {
            url = "github:NixOS/nixpkgs/nixos-24.11";
        };
        nixpkgs-unstable = {
            url = "github:NixOS/nixpkgs/nixos-unstable";
        };
        neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
        flake-parts = {
            url = "github:hercules-ci/flake-parts";
            inputs.nixpkgs-lib.follows = "nixpkgs";
        };
        nixos-wsl = {
            url = "github:nix-community/NixOS-WSL";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        home-manager = {
            url = "github:nix-community/home-manager/release-24.11";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        cp-library = {
            url = "github:scanhex/cp-library";
            flake = false;
        };
    };

	outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
		flake-parts.lib.mkFlake { inherit inputs; } {
			systems = [
				"x86_64-linux"
				"aarch64-linux"
			];

			imports = [
				./flakes
			];
		};
}
