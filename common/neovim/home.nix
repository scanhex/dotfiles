{ inputs, pkgs, ... }: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    package = inputs.scanhex-neovim.packages.${pkgs.system}.default;
  };
}
