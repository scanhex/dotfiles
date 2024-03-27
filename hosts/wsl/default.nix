{ pkgs, username, ... }:
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
			python311
			python311Packages.requests
      # emacs29-pgtk
    ];
  };

  wsl = {
    enable = true;
    defaultUser = "${username}";
    startMenuLaunchers = true;
    nativeSystemd = true;

    # Enable native Docker support
    # docker-native.enable = true;

    # Enable integration with Docker Desktop (needs to be installed)
    # docker-desktop.enable = true;
  };

	programs.zsh.enable = true;
	users.users.${username}.shell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    binutils
    tree
    file
    wget
    vim
  ];

	system.stateVersion = "23.11";
}
