{ pkgs, username, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      wslu
      wsl-open
      # GUI
      kitty
      goodvibes
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
		vim
    binutils
    tree
    file
    wget
    nix-bash-completions
		python3
  ];

	system.stateVersion = "23.11";
}
