{lib, pkgs, config, ...}:
let
  inherit (lib) mkOption mkIf types;
in
{
  options.my.steam = {
    enable = mkOption { type = types.bool; default = false; };
  };

  config = mkIf config.my.steam.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      extraCompatPackages = [ pkgs.unstable.proton-ge-bin ];
    };

    home-manager.users.${config.my.user}.home.packages = [
      (pkgs.writeShellScriptBin "dota2" ''
        exec steam steam://rungameid/570
      '')
    ];
  };
}
