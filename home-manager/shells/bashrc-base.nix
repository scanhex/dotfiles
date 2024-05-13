{
    bashrcBase = '' 
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi
if [ -f ~/.profile ]; then
    . ~/.profile
fi
source ${./git-prompt.sh}
PS1='[\w$(__git_ps1 " (%s)")]\$ '
HISTSIZE=10000000
HISTFILESIZE=10000000
PROMPT_COMMAND='history -a'
export CMAKE_EXPORT_COMPILE_COMMANDS=1
    '';
}
