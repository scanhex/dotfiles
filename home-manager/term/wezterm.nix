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
            config = {
                font = {
                    bold = "Iosevka";
                    italic = "Iosevka";
                    normal = "Iosevka";
                };
            };
        };
    };
}
