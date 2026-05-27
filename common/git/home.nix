{ config, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;
    ignores = [ "/personal/" ];
    settings = {
      user = {
        name = config.my.name;
        email = config.my.email;
      };
      push.autoSetupRemote = true;
      alias = {
        br = "branch";
        ci = "commit";
        co = "checkout";
        st = "status -sb";
        ame = "commit -a --amend --no-edit";
      };
    };
  };
  home.shellAliases = {
    gco = "git branch | grep -v \"^\*\" | fzf --height=20% --reverse --info=inline | xargs git checkout";
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };
}

