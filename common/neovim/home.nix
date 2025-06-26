{ inputs, pkgs, ... }: {
  home.packages = [
   inputs.scanhex-neovim.packages.${pkgs.system}.default
  ];
}
