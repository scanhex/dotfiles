{
	flake.nixosModules = {
		default = {
			imports = [ ./base.nix ];
		};
	};
}
