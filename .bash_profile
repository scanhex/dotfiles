export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*
export PGDATA=/usr/local/var/postgres
alias cd="cd -P"
alias sudo="sudo "
alias mvim="/Applications/MacVim.app/Contents/MacOS/Vim -g"
# added by Anaconda3 4.1.1 installer
export PATH="/Users/Alex/anaconda/bin:$PATH"
export WINEPREFIX="/Users/Alex/prefix32"
export PATH="/usr/local/Cellar/openvpn/2.4.6/sbin:$PATH"
export PATH="/Applications/J/bin:$PATH"
# added for IBM Cloud Kubernetes
export KUBECONFIG=/Users/Alex/.bluemix/plugins/container-service/clusters/mycluster/kube-config-mil01-mycluster.yml
export SVN_EDITOR=vim
#export CXXFLAGS="-I /usr/include/c++/4.2.1"
##
# Your previous /Users/Alex/.bash_profile file was backed up as /Users/Alex/.bash_profile.macports-saved_2016-10-13_at_21:21:17
##

# MacPorts Installer addition on 2016-10-13_at_21:21:17: adding an appropriate PATH variable for use with MacPorts.
# export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
# Finished adapting your PATH environment variable for use with MacPorts.


# added by Miniconda3 installer
export PATH="/Users/Alex/miniconda3/bin:$PATH"
export PATH="/usr/local/opt/llvm/bin:$PATH"

# Setting PATH for Python 3.7
# The original version is saved in .bash_profile.pysave
#PATH="/Library/Frameworks/Python.framework/Versions/3.7/bin:${PATH}"
#export PATH

# added by Anaconda3 5.2.0 installer
export PATH="/Users/Alex/anaconda3/bin:$PATH"

export PATH="$HOME/.cargo/bin:$PATH"
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
