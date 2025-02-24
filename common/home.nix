# inspired by https://github.com/zendo/nsworld/blob/main/home-manager/hm-standalone.nix
{ pkgs, lib, config, ... }:
let nix-user-chroot-patch = pkgs.callPackage ../nix-user-chroot-patch {};
pythonEnv = pkgs.python312.withPackages (ps: [ ps.numpy ps.pandas ps.matplotlib ps.requests ps.pip ]);
in 
{
  imports = lib.my.getHmModules [ ./. ];

  home.packages = [
    pkgs.bash
      pkgs.tmux 
      pkgs.clang
      pkgs.rustc
      pkgs.nix
      pkgs.cargo
      pkgs.glibc
      pkgs.gnumake
      pkgs.cmake
      pkgs.ninja
      pkgs.clang-tools_17
      pkgs.gdb
      pkgs.valgrind
      pkgs.nushell
      pkgs.bat
      pkgs.stgit
      pkgs.tig
      pkgs.virtualenv
      pkgs.pixi
      pkgs.unstable.ast-grep
      pkgs.difftastic
      pkgs.ripgrep
      pkgs.unstable.jujutsu
      pkgs.unstable.ruff
      pkgs.unstable.uv
      pkgs.pciutils
      pkgs.nodePackages.nodejs
      pkgs.yazi
      pythonEnv
      nix-user-chroot-patch
  ];

  programs.fzf.enable = true;
  programs.lazygit = {
      enable = true;
      settings = {
          gui = {
              scrollHeight = 10;
          };
      };
  };
  programs.jujutsu = {
      enable = true;
      package = pkgs.unstable.jujutsu;
      settings = {
          user.name = config.my.name;
          user.email = config.my.email;
          merge-tools.difft.diff-args = ["--color=always" "$left" "$right" ];
          ui.diff.tool = "difft";
          ui.default-command = ["log" "-r" "present(@) | ancestors(immutable_heads().., 2) | present(trunk())"];
          revsets.log = "ancestors(@)";
          snapshot.auto-track = "~(root:\"personal/\" | root:\"Session.vim\" | root:\".clangd\" | root:\"compile_commands.json\" | root:\"CMakePresets.json\")";
          fix.tools.clang_format = {
              command = ["clang-format" "--assume-filename=$path"];
              patterns = ["glob:'**/*.cpp'" "glob:'**/*.h'"];
          };
      };
  };
  programs.bash.shellAliases = {
      jjp = "jj fix && jj git push";
      jjf = "jj git fetch";
  };
  xdg.enable = true;
  nix = { 
    enable = true;
    settings = {
      trusted-users = [ config.my.user ];
      use-xdg-base-directories = true;
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
  programs.bash.sessionVariables = {
    NIXPKGS_ALLOW_UNFREE = "1";
  };

  home.shellAliases = {
    python3 = "LD_PRELOAD=${nix-user-chroot-patch}/lib/nix-user-chroot-patch.so python3";
    g = "LD_PRELOAD=${nix-user-chroot-patch}/lib/nix-user-chroot-patch.so git";
  };

  home.stateVersion = "23.11"; # Shouldn't need to change this most of the time
}
