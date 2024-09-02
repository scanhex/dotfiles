{ pkgs, username, config, ... }:
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware.nix
    ];

  home-manager.users.${username} = {
    home.packages = with pkgs; [
      wezterm
      nixd
      nix-bash-completions
      micromamba
      clinfo
      # emacs29-pgtk
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.luks.devices = {
	  root = {
		  device = "/dev/nvme0n1p2";
		  preLVM = true;
	  };
  };

  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  services.xserver.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
	  layout = "us";
	  variant = "dvorak";
	  options = "caps:escape";
  };

  users.users.${username} = {
	  isNormalUser = true;
	  extraGroups = [ "wheel" "video" "audio" "disk" "networkmanager" ];
	  group = "users";
	  home = "/home/alex";
	  uid = 1000;
	  shell = pkgs.bash;
	  packages = with pkgs; [
		  firefox
			  tree
	  ];
  };

  programs.nix-ld  = {
    enable = true;
    package = pkgs.nix-ld-rs;
    libraries = config.hardware.opengl.extraPackages;
  };
  hardware.opengl.enable = true;
  hardware.opengl.extraPackages = with pkgs; [ intel-ocl opencl-headers ];

  programs.zsh.enable = true;

  my.wezterm.enable = true;

  environment.systemPackages = with pkgs; [
    binutils
    tree
    file
    curl
    vim
  ];


  system.stateVersion = "24.05";
}
