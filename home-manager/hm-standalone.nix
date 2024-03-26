# inspired by https://github.com/zendo/nsworld/blob/main/home-manager/hm-standalone.nix
{ inputs, ... }:
{
	flake.homeConfigurations = 
		let 
			mkHome = 
				{
					username,
					nixpkgs ? inputs.nixpkgs,
					system ? "x86_64-linux",
					extraModules ? [ ],
				}:
				inputs.home-manager.lib.homeManagerConfiguration {
					pkgs = import nixpkgs {
            inherit system;
            overlays = builtins.attrValues inputs.self.overlays;
            config.allowUnfree = true;
          };
				
					extraSpecialArgs = {
						inherit inputs; 
					};

					modules = [ 
						./alias.nix
						./git.nix
					] ++ extraModules;
				};
	in 
	{
		alex = mkHome {
			username = "alex";
		};
	};
}
