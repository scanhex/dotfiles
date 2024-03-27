
{ config, ... }:
{
  programs.neovim = { 
        enable = true;
        withPython3 = true;
        plugins = with pkgs.vimPlugins; [
                nvchad
        ];
  };
}


