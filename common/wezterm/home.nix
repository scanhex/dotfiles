{
    config,
    lib,
    pkgs,
    ...
}:
{
    options.my.wezterm = {
        enable = lib.mkEnableOption "wezterm";
        tmux-binds = lib.mkOption {
          description = "Enable tmux bindings for wezterm";
          type = lib.types.bool;
          default = true;
        };
    };

    config = lib.mkIf config.my.wezterm.enable {
        home.packages = with pkgs; [
            nerd-fonts.iosevka
        ];
        programs.wezterm = {
            enable = true;
            package = pkgs.wezterm;
            extraConfig = ''
wezterm.on('gui-attached', function(domain)
  -- maximize all displayed windows on startup
  local workspace = wezterm.mux.get_active_workspace()
  for _, window in ipairs(wezterm.mux.all_windows()) do
    if window:get_workspace() == workspace then
      window:gui_window():maximize()
    end
  end
end)
return {
  font = wezterm.font("Iosevka Nerd Font Mono"),
  font_size = 14.0,
  ${if config.my.wezterm.tmux-binds then "leader = { key=\"b\", mods=\"CTRL\" }," else ""}
  hide_tab_bar_if_only_one_tab = true,
  -- window_decorations = "NONE",
  default_prog = { "${pkgs.bashInteractive}/bin/bash" },
  keys = {
    {key="n", mods="SHIFT|CTRL", action="ToggleFullScreen"},
    ${if config.my.wezterm.tmux-binds then ''
    { key = "b", mods = "LEADER|CTRL",       action=wezterm.action.SendKey { key = 'b', mods = 'CTRL' }},
    { key = "p", mods = "LEADER",       action=wezterm.action.ActivateTabRelative(-1)},
    { key = "n", mods = "LEADER",       action=wezterm.action.ActivateTabRelative(1)},
    { key = "1", mods = "LEADER",       action=wezterm.action{ActivateTab=0}},
    { key = "2", mods = "LEADER",       action=wezterm.action{ActivateTab=1}},
    { key = "3", mods = "LEADER",       action=wezterm.action{ActivateTab=2}},
    { key = "4", mods = "LEADER",       action=wezterm.action{ActivateTab=3}},
    { key = "5", mods = "LEADER",       action=wezterm.action{ActivateTab=4}},
    { key = "6", mods = "LEADER",       action=wezterm.action{ActivateTab=5}},
    { key = "7", mods = "LEADER",       action=wezterm.action{ActivateTab=6}},
    { key = "8", mods = "LEADER",       action=wezterm.action{ActivateTab=7}},
    { key = "9", mods = "LEADER",       action=wezterm.action{ActivateTab=8}},
    { key = "[", mods = "LEADER",       action="ActivateCopyMode"},
    { key = "|", mods = "LEADER|SHIFT",       action=wezterm.action{SplitHorizontal={domain="CurrentPaneDomain"}}},
    { key = "c", mods = "LEADER",       action=wezterm.action{SpawnTab="CurrentPaneDomain"}},
    { key = "h", mods = "LEADER",       action=wezterm.action{ActivatePaneDirection="Left"}},
    { key = "j", mods = "LEADER",       action=wezterm.action{ActivatePaneDirection="Down"}},
    { key = "k", mods = "LEADER",       action=wezterm.action{ActivatePaneDirection="Up"}},
    { key = "l", mods = "LEADER",       action=wezterm.action{ActivatePaneDirection="Right"}},
    '' else ""}
  }
}
'';
        };
    };
}
