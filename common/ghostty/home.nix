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
            settings = {
              copy-on-select = "clipboard";
              scrollback-limit = 64000000;
              app-notifications = "no-clipboard-copy";
            };
        };
        home.file.".config/ghostty/config".text = builtins.readFile ./config + "\n" + "command = ${pkgs.bashInteractive}/bin/bash -l\n";
    };
}
