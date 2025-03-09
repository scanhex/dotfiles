{ pkgs, username, config, ... }:
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware.nix
    ];


  environment.gnome.excludePackages = with pkgs; [ seahorse ];
  services.xserver = {
      enable = true;
      displayManager.gdm.enable = true;
      displayManager.startx.enable = true;
      desktopManager.xfce.enable = true;
      desktopManager.xterm.enable = true;
#      desktopManager.cinnamon.enable = true;
      desktopManager.gnome.enable = true;
  };
  services.displayManager.defaultSession = "hyprland";
#  services.displayManager.sddm = { 
#    enable = true;
#    wayland.enable = true;
#    settings = {
#      General.GreeterEnvironment = "QT_SCREEN_SCALE_FACTORS=2";
#    };
#  };
#  services.desktopManager.plasma6.enable = true;
  my.hyprland.enable = true;

  home-manager.users.${username} = {
    home.packages = with pkgs; [
      nixd
      nix-bash-completions
      micromamba
      clinfo
      bibata-cursors
      osu-lazer-bin
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

  networking.networkmanager = {
      enable = true;
      wifi.powersave = false; # needed on Lina, can maybe disable for laptops
  };

  users.users.${username} = {
	  isNormalUser = true;
	  extraGroups = [ "wheel" "video" "audio" "disk" "networkmanager" "input" ];
	  group = "users";
	  home = "/home/${username}";
	  uid = 1000;
	  shell = pkgs.bash;
	  packages = with pkgs; [
		  google-chrome
		  firefox
          unstable.discord-canary
          telegram-desktop
          zotero
	  ];
  };
  services.udev.extraRules = ''
    KERNEL=="event*", GROUP="input", MODE="0660"
    KERNEL=="js*", GROUP="input", MODE="0660"
  '';

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      AllowUsers = [ username ]; 
      UseDns = true;
      X11Forwarding = true;
      PermitRootLogin = "yes";
    };
  };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  programs.nix-ld  = {
    enable = true;
    package = pkgs.nix-ld-rs;
    libraries = config.hardware.graphics.extraPackages;
  };
  programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      extraCompatPackages = [ pkgs.unstable.proton-ge-bin ];
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
  hm.my.ghostty.enable = true;
  hm.my.zed.enable = true;
  my.lutris.enable = true;

  nix.settings = {
      substituters = [ "https://cache.nixos.org" "https://nix-community.cachix.org" "https://cuda-maintainers.cachix.org" ];
      trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
            ];
  };
  nixpkgs.config.cudaSupport = true;

  environment.systemPackages = with pkgs; [
    binutils
    tree
    file
    curl
    vim
  ];

  system.stateVersion = "25.05";
}
