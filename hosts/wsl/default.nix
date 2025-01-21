{ pkgs, username, config, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      wslu
      wsl-open
      # GUI
      kitty
      goodvibes
      nixd
      nix-bash-completions
      micromamba
      clinfo
      # emacs29-pgtk
    ];
  };

  programs.nix-ld  = {
    enable = true;
    package = pkgs.nix-ld-rs;
    libraries = config.hardware.graphics.extraPackages;
  };
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [ intel-ocl opencl-headers ];

  nix.settings = {
      substituters = [ "https://cache.nixos.org" "https://nix-community.cachix.org" "https://cuda-maintainers.cachix.org" ];
      trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
            ];
  };

  wsl = {
    enable = true;
    defaultUser = "${username}";
    startMenuLaunchers = true;
    nativeSystemd = true;
    interop.includePath = false;
    useWindowsDriver = true;
  };

  services.openssh = { 
      enable = true;
      settings = {
          Port = 2222;
      };
  };

  programs.zsh.enable = true;
  users.users.${username}.shell = pkgs.bash;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    binutils
    tree
    file
    wget
    vim
  ];

	system.stateVersion = "23.11";
}
