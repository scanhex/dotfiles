{lib, pkgs, config, ...}:
let
  inherit (lib) mkOption mkIf types;
in
{
    options.my.lutris = {
        enable = mkOption { type = types.bool; default = false; };
        extraLibraries = mkOption {
            type = types.listOf types.package;
            default = [];
        };
    };

    config = mkIf config.my.lutris.enable {
        home-manager.users.${config.my.user}.home.packages =
          [pkgs.wineWowPackages.staging]
          ++ [(pkgs.lutris.override {
              extraLibraries = pkgs: config.my.lutris.extraLibraries;
          })];
        my.aatg = {
          installLibs = true;
          blockMihoyoTelemetry = true;
        };
    };
}
