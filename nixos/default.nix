{
	flake.nixosModules = {
		default = {
			imports = [ 
				./base.nix
				./nixconfig.nix
			];
		};
	};
}
