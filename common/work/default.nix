{config, pkgs, lib, ...}:
{
  options.my.work.enable = lib.mkEnableOption "Settings/packages that were introduced for work";

  config = lib.mkIf config.my.work.enable {
#    boot.kernel.sysctl."kernel.yama.ptrace_scope" = 0;
    hm.home.packages = [
      pkgs.google-cloud-sdk
    ];
  };
}
