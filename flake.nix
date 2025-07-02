{
	description = "My master nix flake";

    inputs = {
        nixpkgs = {
            url = "github:NixOS/nixpkgs/nixos-25.05";
        };
        nixpkgs-unstable = {
            url = "github:NixOS/nixpkgs/nixos-unstable";
        };
        determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
        scanhex-neovim = {
            url = "path:./common/neovim";
            inputs.nixpkgs.follows = "nixpkgs";
            inputs.nixpkgs-unstable.follows = "nixpkgs-unstable";
        };
        flake-parts = {
            url = "github:hercules-ci/flake-parts";
            inputs.nixpkgs-lib.follows = "nixpkgs";
        };
        nixos-wsl = {
            url = "github:nix-community/NixOS-WSL";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        darwin = {
          url = "github:lnl7/nix-darwin/nix-darwin-25.05";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        home-manager = {
            url = "github:nix-community/home-manager/release-25.05";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        stylix.url = "github:danth/stylix/release-25.05";
    };

	outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
		flake-parts.lib.mkFlake { inherit inputs; } {
			systems = [
				"x86_64-linux"
				"aarch64-darwin"
			];

			imports = [
				./flakes
			];
		};
}
