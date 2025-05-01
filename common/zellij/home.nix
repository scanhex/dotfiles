{lib, config, ... }:
{
  options = {
    my.zellij.enable = lib.mkEnableOption "zellij";
    my.zellij.ctrl-prefix = lib.mkOption {
      description = "Key that enables tmux mode when pressed with ctrl";
      type = lib.types.str;
      default = "b";
    };
  };

  config.programs.zellij = lib.mkIf config.my.zellij.enable {
    enable = true;
    settings = {
      theme = "dracula";
      keybinds = {
        "normal clear-defaults=true" = {
          "bind \"F12\"".SwitchToMode = "locked";
          "bind \"Ctrl ${config.my.zellij.ctrl-prefix}\"".SwitchToMode = "tmux";
        };
        locked = {
          "bind \"F12\"".SwitchToMode = "Normal";
        };
        scroll = {
          "bind \"Ctrl u\"".HalfPageScrollUp = { _args = [ ]; };
          "bind \"Ctrl d\"".HalfPageScrollDown = { _args = [ ]; };
          "bind \"q\"".SwitchToMode = "Normal";
          "bind \"G\"".ScrollToBottom = { _args = [ ]; };
          "bind \"g\"".ScrollToTop = { _args = [ ]; };
          "bind \"Ctrl ${config.my.zellij.ctrl-prefix}\"".SwitchToMode = "tmux";
        };
        tmux = builtins.foldl' (acc: n:
            acc // {
              "bind \"${toString n}\"" = { GoToTab = n + 1; SwitchToMode = "Normal"; };
            }
          ) { } (lib.range 0 9) // {
            "bind \"e\"".EditScrollback = { _args = []; };
            "bind \"e\"".SwitchToMode = "Normal";
            "bind \"m\"".SwitchToMode = "move";
            "bind \"=\"".SwitchToMode = "resize";
          };
        "shared_except \"locked\"" = {
          "bind \"F12\"".SwitchToMode = "locked";
        };
      };
      default_layout = "compact";
      pane_frames = false;
    };
  };
}

