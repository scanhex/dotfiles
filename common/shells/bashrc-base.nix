{config, ...}:
{
    bashrcBase = '' 
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi
if [ -f ~/.profile ]; then
    . ~/.profile
fi
. ${config.home.profileDirectory}/etc/profile.d/nix.sh
source ${./git-prompt.sh}
PS1='[\w$(__git_ps1 " (%s)")]\$ '
HISTSIZE=10000000
HISTFILESIZE=10000000
PROMPT_COMMAND='history -a'
export CMAKE_EXPORT_COMPILE_COMMANDS=1

if [ -f ~/.bashrc-secrets ]; then
    . ~/.bashrc-secrets
fi

zellij_tab_name_update() {
    if [[ -n $ZELLIJ ]]; then
        local current_dir=$PWD
        if [[ $current_dir == $HOME ]]; then
            current_dir="~"
        else
            current_dir=''\${current_dir##*/}
        fi
        command nohup zellij action rename-tab $current_dir >/dev/null 2>&1
    fi
}

for completion_script in ${config.home.profileDirectory}/share/bash-completion/completions/*
do
  source "$completion_script"
done
    '';
}
