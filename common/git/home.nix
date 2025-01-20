{ config, ... }:
{
  programs.git = {
    enable = true;
    userName = config.my.name;
    userEmail = config.my.email;
    ignores = [ "/personal/" ];
    extraConfig.push.autoSetupRemote = true;
    aliases = {
      br = "branch";
      ci = "commit";
      co = "checkout";
      st = "status -sb";
      ame = "commit -a --amend --no-edit";
    };
  };
  home.shellAliases = {
    gco = "git branch | grep -v \"^\*\" | fzf --height=20% --reverse --info=inline | xargs git checkout";
  };

  programs.git.delta.enable = true;
}


