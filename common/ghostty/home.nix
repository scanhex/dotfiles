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
              macos-option-as-alt = true;
              font-family = "Iosevka Nerd Font Mono";
              adjust-cell-width = "-5%";
              copy-on-select = "clipboard";
              shell-integration = "bash";
              maximize = true;
              scrollback-limit = 64000000;
              app-notifications = "no-clipboard-copy";
              command = "${pkgs.bashInteractive}/bin/bash -l";
            };
        };
    };
}
