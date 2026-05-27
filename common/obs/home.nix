{pkgs, lib, config, ...}:
{
  options.my.obs.enable = lib.mkEnableOption "obs";
  config = lib.mkIf config.my.obs.enable {
    home.packages = [(pkgs.wrapOBS {
        plugins = with pkgs.obs-studio-plugins; [
        obs-websocket
        ];
        })
    ] ++ lib.optionals config.my.hyprland.enable [
      pkgs.obs-cmd
    ];

    my.hyprland.extraSettings = [
      {
        bind = [
          {
            _args = [
              "CTRL + SHIFT + F12"
              (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("obs-cmd recording toggle")'')
            ];
          }
        ];
      }
    ];
  };
}
