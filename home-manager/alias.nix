{ lib, pkgs, ... }:
{
	programs.bash.enable = true; # otherwise the shell Aliases won't work
	programs.zsh.enable = true; 
  home.shellAliases = {
		g = "git";
	};
}
