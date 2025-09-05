{
    config,
    lib,
    pkgs,
    ...
}:
{
    options.my.ghostty = {
        enable = lib.mkEnableOption "ghostty";
        unmanaged = lib.mkEnableOption "ghostty not managed by nix";
    };

    config = lib.mkIf config.my.ghostty.enable {
        home.packages = with pkgs; [
            nerd-fonts.iosevka
        ];
        programs.ghostty = lib.mkIf (!config.my.ghostty.unmanaged) {
            enable = true;
            package = pkgs.unstable.ghostty;
        };
        home.file.".config/ghostty/config".text = builtins.readFile ./config + "\n" + "command = ${pkgs.bashInteractive}/bin/bash -l\n";
    };
}
