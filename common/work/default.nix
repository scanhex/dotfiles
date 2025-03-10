{config, lib, ...}:
{
  options.my.work.enable = lib.mkEnableOption "Settings/packages that are mostly needed for work";

  config = lib.mkIf config.my.work.enable {
    boot.kernel.sysctl."kernel.yama.ptrace_scope" = 0;
  };
}
