sudo apt install git vim-gtk3
if ! [ -f ~/.vimrc ]; then
  curl https://raw.githubusercontent.com/scanhex/dotfiles/master/.vimrc -o ~/.vimrc
else
  echo "~/.vimrc exists, left unchanged."
fi
mkdir -p ~/.vim/autoload ~/.vim/bundle && curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
git clone https://github.com/scanhex/nova.vim ~/.vim/bundle/nova.vim
mkdir -p ~/Code
curl https://raw.githubusercontent.com/scanhex/dotfiles/master/JetBrainsMono-Regular.ttf /usr/local/share/fonts/
