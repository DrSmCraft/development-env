#! /bin/bash

echo "Updating package list"
apt-get update

echo "Removing unused packages"
apt-get remove -y vim


echo "Installing packages"
apt-get install -y neovim
apt-get install -y net-tools
apt-get install -y zip unzip
apt-get install -y tree
apt-get install -y zsh
apt-get install -y python-pygments
apt-get install -y g++ gcc gdb


echo "Configuring Bash"
rm ~/.bashrc
wget https://raw.githubusercontent.com/DrSmCraft/development-env/main/bash/.bashrc -O ~/.bashrc

echo "Configuring Zsh"
rm ~/.zshrc
wget https://raw.githubusercontent.com/DrSmCraft/development-env/main/zsh/.zshrc -O ~/.zshrc

echo "Setting Zsh as default shell"
usermod --shell /bin/zsh $(whoami)

echo "Configuring NeoVim"
mkdir ~/.config/
mkdir ~/.config/nvim/
wget https://raw.githubusercontent.com/DrSmCraft/development-env/main/nvim/init.vim -O ~/.config/nvim/init.vim
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

echo "Upgrading system"
apt-get -y upgrade

echo "Done"
