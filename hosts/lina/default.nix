{ pkgs, username, config, ... }:
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware.nix
    ];


  home-manager.users.${username} = {
    home.packages = with pkgs; [
      nixd
      nix-bash-completions
      micromamba
      clinfo
      # emacs29-pgtk
    ];
  };

  boot.kernelPackages = pkgs.unstable.linuxPackages_latest;
  hardware.bluetooth = {
      enable = true; 
      powerOnBoot = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 15;
  boot.loader.timeout = 0;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  services.xserver.enable = true;
  services.displayManager.sddm = { 
    enable = true;
    wayland.enable = true;
    settings = {
      General.GreeterEnvironment = "QT_SCREEN_SCALE_FACTORS=2";
    };
  };
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
	  layout = "us";
	  variant = "dvorak";
	  options = "ctrl:nocaps";
  };

  users.users.${username} = {
	  isNormalUser = true;
	  extraGroups = [ "wheel" "video" "audio" "disk" "networkmanager" ];
	  group = "users";
	  home = "/home/alex";
	  uid = 1000;
	  shell = pkgs.bash;
	  packages = with pkgs; [
		  google-chrome
          (lutris.override {
              extraLibraries = pkgs: [
                  pkgs.libadwaita
                  pkgs.gtk4
              ];
          })
          discord
          telegram-desktop
	  ];
  };
  my.mihoyo-telemetry.block = true;

  programs.nix-ld  = {
    enable = true;
    package = pkgs.nix-ld-rs;
    libraries = config.hardware.opengl.extraPackages;
  };
  programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.zsh.enable = true;

  #enable audio 
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
# If you want to use JACK applications, uncomment this
#jack.enable = true;
  };

  time.timeZone = "America/New_York";

  hm.my.wezterm.enable = true;

  environment.systemPackages = with pkgs; [
    binutils
    tree
    file
    curl
    vim
  ];

  system.stateVersion = "25.05";
}
