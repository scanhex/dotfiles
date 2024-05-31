{config, lib, ...}:
{
    options = {
        my.bash.bashrcPrefix = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Prefix for the bashrc file";
        };
        my.bash.bashrcSuffix = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Suffix for the bashrc file";
        };
    };
    config = {
        programs.bash.bashrcExtra = config.my.bash.bashrcPrefix + (import ./bashrc-base.nix {config = config;}).bashrcBase + config.my.bash.bashrcSuffix;
        programs.bash.enable = true; # otherwise bashrcExtra/shellAliases wouldn't work 
        #programs.zsh.enable = true;
        home.shellAliases = {
            mm = "micromamba";
            cp="cp -i";
            mv="mv -i";
        };
    };
}
