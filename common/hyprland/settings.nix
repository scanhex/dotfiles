{ lib }:
let
  lua = lib.generators.mkLuaInline;
  bind = key: dispatcher: {
    _args = [
      key
      (lua dispatcher)
    ];
  };
  bindWith = key: dispatcher: opts: {
    _args = [
      key
      (lua dispatcher)
      opts
    ];
  };
  monocleToggle = ''
    function()
      local workspace = hl.get_active_workspace()
      if not workspace then
        return
      end

      local nextLayout = "monocle"
      if workspace.tiled_layout == "monocle" then
        nextLayout = "dwindle"
      end

      hl.workspace_rule({ workspace = workspace.name, layout = nextLayout })
    end
  '';
  focusOrCycle = direction: cycle: ''
    function()
      local workspace = hl.get_active_workspace()
      if workspace and workspace.tiled_layout == "monocle" then
        hl.dispatch(hl.dsp.layout("${cycle}"))
        return
      end

      hl.dispatch(hl.dsp.focus({ direction = "${direction}" }))
    end
  '';
  mod = suffix: lua ''mainMod .. " + ${suffix}"'';
in
{
  terminal = { _var = "wezterm"; };
  fileManager = { _var = "thunar"; };
  menu = { _var = "sh -c 'cmd=$(tofi-run) || exit 0; [ -n \"$cmd\" ] && hyprctl dispatch \"hl.dsp.exec_cmd(\\\"$cmd\\\")\"'"; };
  mainMod = { _var = "SUPER"; };

  monitor = [
    {
      output = "DP-4";
      mode = "2560x1440@170";
      position = "auto";
      scale = 1.6;
    }
    {
      output = "DP-1";
      mode = "1920x1080@90";
      position = "auto";
      scale = 1.6;
      mirror = "DP-4";
    }
    {
      output = "HDMI-A-1";
      mode = "3840x2160@240";
      position = "auto";
      scale = 2;
    }
    {
      output = "HDMI-A-2";
      mode = "2560x1440@240";
      position = "auto";
      scale = 1.6;
      mirror = "DP-4";
    }
  ];

  env = [
    { _args = [ "XCURSOR_SIZE" "24" ]; }
    { _args = [ "HYPRCURSOR_SIZE" "24" ]; }
    { _args = [ "XCURSOR_THEME" "Bibata-Modern-Classic" ]; }
    { _args = [ "HYPRCURSOR_THEME" "Bibata-Modern-Classic" ]; }
  ];

  on = {
    _args = [
      "hyprland.start"
      (lua ''
        function()
          hl.exec_cmd("caelestia-shell &")
          hl.exec_cmd("xrdb ~/.Xresources")
        end
      '')
    ];
  };

  config = {
    general = {
      gaps_in = 2;
      gaps_out = 0;
      border_size = 1;
      col = {
        active_border = {
          colors = [
            "rgba(33ccffee)"
            "rgba(00ff99ee)"
          ];
          angle = 45;
        };
        inactive_border = "rgba(595959aa)";
      };
      resize_on_border = true;
      allow_tearing = false;
      layout = "dwindle";
    };

    decoration = {
      rounding = 10;
      active_opacity = 1.0;
      inactive_opacity = 1.0;
      shadow = {
        enabled = true;
        range = 4;
        render_power = 3;
        color = "rgba(1a1a1aee)";
      };
      blur = {
        enabled = true;
        size = 3;
        passes = 1;
        vibrancy = 0.1696;
      };
    };

    animations.enabled = true;

    dwindle.preserve_split = true;

    master.new_status = "master";

    misc = {
      force_default_wallpaper = -1;
      disable_hyprland_logo = false;
      on_focus_under_fullscreen = 1;
      vrr = 0;
    };

    debug.disable_logs = false;

    binds.movefocus_cycles_fullscreen = true;

    cursor.no_hardware_cursors = 1;

    input = {
      kb_layout = "us,ru";
      kb_variant = "dvorak,";
      kb_model = "";
      kb_options = "grp:alt_shift_toggle";
      kb_rules = "";
      follow_mouse = 1;
      float_switch_override_focus = 0;
      sensitivity = 0;
      touchpad.natural_scroll = false;
    };

    xwayland.force_zero_scaling = true;
  };

  curve = [
    {
      _args = [
        "easeOutQuint"
        { type = "bezier"; points = [ [ 0.23 1 ] [ 0.32 1 ] ]; }
      ];
    }
    {
      _args = [
        "easeInOutCubic"
        { type = "bezier"; points = [ [ 0.65 0.05 ] [ 0.36 1 ] ]; }
      ];
    }
    {
      _args = [
        "linear"
        { type = "bezier"; points = [ [ 0 0 ] [ 1 1 ] ]; }
      ];
    }
    {
      _args = [
        "almostLinear"
        { type = "bezier"; points = [ [ 0.5 0.5 ] [ 0.75 1.0 ] ]; }
      ];
    }
    {
      _args = [
        "quick"
        { type = "bezier"; points = [ [ 0.15 0 ] [ 0.1 1 ] ]; }
      ];
    }
  ];

  animation = [
    { leaf = "global"; enabled = true; speed = 10; bezier = "default"; }
    { leaf = "border"; enabled = true; speed = 5.39; bezier = "easeOutQuint"; }
    { leaf = "windows"; enabled = false; speed = 4.79; bezier = "easeOutQuint"; }
    { leaf = "windowsIn"; enabled = false; speed = 0.01; bezier = "quick"; }
    { leaf = "windowsOut"; enabled = false; speed = 0.01; bezier = "quick"; }
    { leaf = "fadeIn"; enabled = true; speed = 1.73; bezier = "almostLinear"; }
    { leaf = "fadeOut"; enabled = true; speed = 1.46; bezier = "almostLinear"; }
    { leaf = "fade"; enabled = false; speed = 3.03; bezier = "quick"; }
    { leaf = "layers"; enabled = true; speed = 3.81; bezier = "easeOutQuint"; }
    { leaf = "layersIn"; enabled = true; speed = 4; bezier = "easeOutQuint"; style = "fade"; }
    { leaf = "layersOut"; enabled = true; speed = 1.5; bezier = "linear"; style = "fade"; }
    { leaf = "fadeLayersIn"; enabled = true; speed = 1.79; bezier = "almostLinear"; }
    { leaf = "fadeLayersOut"; enabled = true; speed = 1.39; bezier = "almostLinear"; }
    { leaf = "workspaces"; enabled = true; speed = 1.94; bezier = "almostLinear"; style = "fade"; }
    { leaf = "workspacesIn"; enabled = true; speed = 1.21; bezier = "almostLinear"; style = "fade"; }
    { leaf = "workspacesOut"; enabled = true; speed = 1.94; bezier = "almostLinear"; style = "fade"; }
  ];

  device = {
    name = "epic-mouse-v1";
    sensitivity = -0.5;
  };

  bind = [
    (bind (mod "Q") "hl.dsp.exec_cmd(terminal)")
    (bind (mod "C") "hl.dsp.window.close()")
    (bind (mod "SHIFT + L") ''hl.dsp.exec_cmd("hyprlock")'')
    (bind (mod "SHIFT + S") ''hl.dsp.exec_cmd("hyprshot -m region -z")'')
    (bind (mod "SHIFT + B") ''hl.dsp.exec_cmd("reconnect-wh1000xm6")'')
    (bind (mod "Print") ''hl.dsp.exec_cmd("hyprshot -m active -m output -z")'')
    (bind (mod "E") "hl.dsp.exec_cmd(fileManager)")
    (bind (mod "V") ''hl.dsp.window.float({ action = "toggle" })'')
    (bind (mod "F") monocleToggle)
    (bind (mod "SHIFT + F") "hl.dsp.window.fullscreen(0)")
    (bind (mod "R") "hl.dsp.exec_cmd(menu)")
    (bind (mod "P") "hl.dsp.window.pseudo()")
    (bind (mod "S") ''hl.dsp.layout("togglesplit")'')

    (bind (mod "left") (focusOrCycle "left" "cycleprev"))
    (bind (mod "right") (focusOrCycle "right" "cyclenext"))
    (bind (mod "up") (focusOrCycle "up" "cycleprev"))
    (bind (mod "down") (focusOrCycle "down" "cyclenext"))
    (bind (mod "h") (focusOrCycle "left" "cycleprev"))
    (bind (mod "l") (focusOrCycle "right" "cyclenext"))
    (bind (mod "k") (focusOrCycle "up" "cycleprev"))
    (bind (mod "j") (focusOrCycle "down" "cyclenext"))

    (bind (mod "1") "hl.dsp.focus({ workspace = 1 })")
    (bind (mod "2") "hl.dsp.focus({ workspace = 2 })")
    (bind (mod "3") "hl.dsp.focus({ workspace = 3 })")
    (bind (mod "4") "hl.dsp.focus({ workspace = 4 })")
    (bind (mod "5") "hl.dsp.focus({ workspace = 5 })")
    (bind (mod "6") "hl.dsp.focus({ workspace = 6 })")
    (bind (mod "7") "hl.dsp.focus({ workspace = 7 })")
    (bind (mod "8") "hl.dsp.focus({ workspace = 8 })")
    (bind (mod "9") "hl.dsp.focus({ workspace = 9 })")
    (bind (mod "0") "hl.dsp.focus({ workspace = 10 })")

    (bind (mod "SHIFT + 1") "hl.dsp.window.move({ workspace = 1 })")
    (bind (mod "SHIFT + 2") "hl.dsp.window.move({ workspace = 2 })")
    (bind (mod "SHIFT + 3") "hl.dsp.window.move({ workspace = 3 })")
    (bind (mod "SHIFT + 4") "hl.dsp.window.move({ workspace = 4 })")
    (bind (mod "SHIFT + 5") "hl.dsp.window.move({ workspace = 5 })")
    (bind (mod "SHIFT + 6") "hl.dsp.window.move({ workspace = 6 })")
    (bind (mod "SHIFT + 7") "hl.dsp.window.move({ workspace = 7 })")
    (bind (mod "SHIFT + 8") "hl.dsp.window.move({ workspace = 8 })")
    (bind (mod "SHIFT + 9") "hl.dsp.window.move({ workspace = 9 })")
    (bind (mod "SHIFT + 0") "hl.dsp.window.move({ workspace = 10 })")

    (bind (mod "T") ''hl.dsp.workspace.toggle_special("magic")'')
    (bind (mod "SHIFT + T") ''hl.dsp.window.move({ workspace = "special:magic" })'')

    (bind (mod "mouse_down") ''hl.dsp.focus({ workspace = "e+1" })'')
    (bind (mod "mouse_up") ''hl.dsp.focus({ workspace = "e-1" })'')

    (bindWith (mod "mouse:272") "hl.dsp.window.drag()" { mouse = true; })
    (bindWith (mod "mouse:273") "hl.dsp.window.resize()" { mouse = true; })

    (bindWith "XF86AudioRaiseVolume" ''hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")'' { locked = true; repeating = true; })
    (bindWith "XF86AudioLowerVolume" ''hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")'' { locked = true; repeating = true; })
    (bindWith "XF86AudioMute" ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")'' { locked = true; repeating = true; })
    (bindWith "XF86AudioMicMute" ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")'' { locked = true; repeating = true; })
    (bindWith "XF86MonBrightnessUp" ''hl.dsp.exec_cmd("brightnessctl s 10%+")'' { locked = true; repeating = true; })
    (bindWith "XF86MonBrightnessDown" ''hl.dsp.exec_cmd("brightnessctl s 10%-")'' { locked = true; repeating = true; })

    (bindWith "XF86AudioNext" ''hl.dsp.exec_cmd("playerctl next")'' { locked = true; })
    (bindWith "XF86AudioPause" ''hl.dsp.exec_cmd("playerctl play-pause")'' { locked = true; })
    (bindWith "XF86AudioPlay" ''hl.dsp.exec_cmd("playerctl play-pause")'' { locked = true; })
    (bindWith "XF86AudioPrev" ''hl.dsp.exec_cmd("playerctl previous")'' { locked = true; })
  ];

  window_rule = [
    {
      match.class = ".*";
      suppress_event = "maximize";
    }
    {
      match = {
        class = "^$";
        title = "^$";
        xwayland = true;
        float = true;
        fullscreen = false;
        pin = false;
      };
      no_focus = true;
    }
    {
      match.class = ".*blueman-manager.*";
      float = true;
      no_anim = true;
      no_focus = true;
      rounding = 0;
      border_size = 0;
    }
    {
      match.class = ".*blueman-manager.*";
      size = "300 400";
    }
    {
      match.class = ".*blueman-manager.*";
      move = "100%-450 100%-450";
    }
    {
      match.class = "com\\.saivert\\.pwvucontrol";
      float = true;
      no_anim = true;
      no_focus = true;
      rounding = 0;
      border_size = 0;
    }
    {
      match.class = ".*com\\.saivert\\.pwvucontrol.*";
      size = "600 400";
    }
    {
      match.class = ".*com\\.saivert\\.pwvucontrol.*";
      move = "100%-750 100%-450";
    }
    {
      match.class = "^.*$";
      focus_on_activate = true;
    }
    {
      match.title = ".*Discord.*";
      workspace = "4";
    }
    {
      match.title = ".*Steam.*";
      workspace = "4";
    }
    {
      match.title = ".*Dota 2.*";
      workspace = "5";
    }
    {
      match.title = ".*Counter-Strike 2.*";
      workspace = "5";
    }
    {
      match.title = ".*(Dead by Daylight|DeadByDaylight).*";
      workspace = "5";
    }
    {
      match.title = ".*Genshin Impact.*";
      workspace = "5";
    }
    {
      match.title = ".*Minecraft.*";
      workspace = "6";
    }
  ];
}
