{pkgs, ...}:
{
    home.shellAliases = {
    };
    home.packages = [ pkgs.micromamba ];
    my.bash.bashrcPrefix = ''
'';
    my.bash.bashrcSuffix = ''
'';
}
