{ inputs, pkgs, lib, config, ... }: {
  options.my.neovim = {
    enable = lib.mkEnableOption "scanhex neovim configuration";
  };
  config.home = lib.mkIf config.my.neovim.enable {
    packages = [
      inputs.scanhex-neovim.packages.${pkgs.system}.default
    ];
    sessionVariables.EDITOR = "nvim";
  };
}
