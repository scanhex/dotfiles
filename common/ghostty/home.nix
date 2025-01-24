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
            (nerdfonts.override { fonts = [ "Iosevka" ]; })
        ];
        programs.ghostty = {
            enable = true;
            package = pkgs.unstable.ghostty;
        };
    };
}
