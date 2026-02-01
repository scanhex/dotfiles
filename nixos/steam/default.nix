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
      # HoYoPlay/Genshin: install by adding the launcher to Steam once so compatdata exists.
      # If this differs on another PC, only adjust the args below (compat id, exe path, steam root).
      # To find compat id can try this rg --files -g 'GenshinImpact.exe' ~/.local/share/Steam/steamapps/compatdata | sed -E 's|.*/compatdata/([0-9]+)/.*|\\1|' | sort -u
      (pkgs.writeShellScriptBin "hoyoplay" ''
        exec ${./launch-hoyogame.sh} \
          --steam-root "$HOME/.local/share/Steam" \
          --compat-id 2649200909 \
          --exe "Program Files/HoYoPlay/launcher.exe" \
          --steam-app-id 2649200909 \
          -- "$@"
      '')
      (pkgs.writeShellScriptBin "genshinimpact" ''
        exec ${./launch-hoyogame.sh} \
          --steam-root "$HOME/.local/share/Steam" \
          --compat-id 2649200909 \
          --exe "Program Files/HoYoPlay/games/Genshin Impact game/GenshinImpact.exe" \
          --steam-app-id 2649200909 \
          -- "$@"
      '')
      (pkgs.writeShellScriptBin "dota2" ''
        exec steam steam://rungameid/570
      '')
    ];
  };
}
