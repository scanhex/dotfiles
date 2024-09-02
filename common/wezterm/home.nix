{
    config,
    lib,
    pkgs,
    ...
}:
{
    options.my.wezterm = {
        enable = lib.mkEnableOption "wezterm";
    };

    config = lib.mkIf config.my.wezterm.enable {
        home.packages = with pkgs; [
            (nerdfonts.override { fonts = [ "Iosevka" ]; })
        ];
        programs.wezterm = {
            enable = true;
            package = pkgs.wezterm;
            extraConfig = ''
return {
  font = wezterm.font("Iosevka Nerd Font Mono"),
  font_size = 14.0,
  keys = {
    {key="n", mods="SHIFT|CTRL", action="ToggleFullScreen"},
  }
}
'';
        };
    };
}
