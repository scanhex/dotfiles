{
    config,
    lib,
    pkgs,
    ...
}:
{
    options.my.ghostty = {
        enable = lib.mkEnableOption "ghostty";
    };

    config = lib.mkIf config.my.ghostty.enable {
        home.packages = with pkgs; [
            nerd-fonts.iosevka
        ];
        programs.ghostty = {
            enable = true;
            package = pkgs.unstable.ghostty;
        };
    };
}
