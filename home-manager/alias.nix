{ lib, pkgs, ... }:
{
	programs.bash.enable = true; # otherwise shellAliases wouldn't work? 
	programs.zsh.enable = true;
	programs.zsh.shellAliases.g = "git";
  home.shellAliases = {
		g = "git";
	};
}
