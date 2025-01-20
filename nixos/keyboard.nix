{config, ...}:
{
  # toggle fn mode for Apple-like keyboards
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=0
    '';
    
  # could try and do it through keyd instead
  services.xserver.xkb = {
	  layout = "us";
	  variant = "dvorak";
  };
  users.users.${config.my.user}.extraGroups = [ "keyd" ];
  # NOTE: can look into kmonad insetad of keyd
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = ["*"];
        settings = {
          main = {
            capslock = "layer(control)";
          };
        };
      };
    };
  };
  # Alternative for capslock remap, couldn't get it to work
  # NOTE: The empty line between blocks is needed!
  #  services.udev.extraHwdb = ''
  #evdev:input:b0003v05AC*
  #  KEYBOARD_KEY_3a=leftctrl
  #    '';
}
