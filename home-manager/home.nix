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

  nixpkgs.overlays = [ (final: prev: 
      { 
      bash-completion = prev.bash-completion.overrideAttrs (old:  
          {
            src = builtins.fetchurl {
              url = "https://github.com/scop/bash-completion/releases/download/2.11/bash-completion-2.11.tar.xz";
              sha256 = "1b0iz7da1sgifx1a5wdyx1kxbzys53v0kyk8nhxfipllmm5qka3k";
            };
          });
      delta = prev.delta.overrideAttrs (old: 
        {
          postInstall = "";
        });
      })];


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
      pkgs.stgit
      pkgs.tig
      nix-user-chroot-patch
  ];

  programs.fzf.enable = true;
  xdg.enable = true;
  nix = { 
    enable = true;
    settings = {
      use-xdg-base-directories = true;
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  home.shellAliases = {
    python3 = "LD_PRELOAD=${nix-user-chroot-patch}/lib/nix-user-chroot-patch.so python3";
    g = "LD_PRELOAD=${nix-user-chroot-patch}/lib/nix-user-chroot-patch.so git";
  };

  home.stateVersion = "23.11"; # Shouldn't need to change this most of the time
}
