{
	description = "My master nix flake";

    inputs = {
        nixpkgs = {
            url = "github:NixOS/nixpkgs/nixos-24.11";
        };
        nixpkgs-unstable = {
            url = "github:NixOS/nixpkgs/e5b167bc7b3749c1a2eba831e7048e37738b4b1c";
        };
        neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay/31a7206bdf9e0c01db2165e20a6082690c60b9c9";
        flake-parts = {
            url = "github:hercules-ci/flake-parts";
            inputs.nixpkgs-lib.follows = "nixpkgs";
        };
        nixos-wsl = {
            url = "github:nix-community/NixOS-WSL";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        darwin = {
          url = "github:lnl7/nix-darwin/nix-darwin-24.11";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        home-manager = {
            url = "github:nix-community/home-manager/release-24.11";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        stylix.url = "github:danth/stylix/release-24.11";
        cp-library = {
            url = "github:scanhex/cp-library";
            flake = false;
        };
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
