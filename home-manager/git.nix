{ config, ... }:
{
  programs.git = {
		enable = true;
		userName = "Alex Morozov";
		userEmail = "scanhex@gmail.com";
        extraConfig.push.autoSetupRemote = true;
		aliases = {
			st = "status -sb";
			ci = "commit";
			co = "checkout";
		};
	};

	programs.git.delta.enable = true;
}


