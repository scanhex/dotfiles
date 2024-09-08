{pkgs, ...}:
{
  programs.tmux = {
      enable = true;
      sensibleOnTop = true;
      plugins = with pkgs; [
        tmuxPlugins.resurrect
        tmuxPlugins.continuum
      ];
      extraConfig = "
      setw -g alternate-screen on
set -g mouse on
set-window-option -g mode-keys vi
set-option -sg escape-time 10
set-environment -g COLORTERM 'truecolor'
set-option -g default-terminal 'screen-256color'
set -as terminal-features ',xterm-256color:RGB'
# approx. 50MB per pane given that average line is 100 bytes
set-option -g history-limit 500000
bind-key -T copy-mode-vi y send -X copy-pipe 'xclip -in -selection clipboard'
";
  };
}
