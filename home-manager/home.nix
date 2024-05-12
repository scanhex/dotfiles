# inspired by https://github.com/zendo/nsworld/blob/main/home-manager/hm-standalone.nix
{ pkgs, ... }:
let nix-user-chroot-patch = pkgs.callPackage ../nix-user-chroot-patch {};
in 
{
	imports = [
		./git.nix
		./neovim
        ./shells
	];

	home.packages = [
      pkgs.bash
  	  pkgs.tmux 
	  pkgs.rustc
	  pkgs.nix
	  pkgs.cargo
	  pkgs.glibc
      pkgs.clang-tools_17
      pkgs.gdb
      pkgs.valgrind
      pkgs.nushell
      pkgs.bat
      pkgs.parquet-tools
	  nix-user-chroot-patch
	];

    programs.fzf.enable = true;

	home.shellAliases = {
		python3 = "LD_PRELOAD=${nix-user-chroot-patch}/lib/nix-user-chroot-patch.so python3";
		g = "LD_PRELOAD=${nix-user-chroot-patch}/lib/nix-user-chroot-patch.so git";
	};

    home.stateVersion = "23.11";
}
