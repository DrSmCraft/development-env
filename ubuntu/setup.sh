#! /bin/bash

echo "Updating package list"
sudo apt-get update

echo "Removing unused packages"
sudo apt-get remove -y vim


echo "Installing packages"
sudo apt-get install -y neovim
sudo apt-get install -y net-tools
sudo apt-get install -y zip unzip
sudo apt-get install -y tree
sudo apt-get install -y zsh
sudo apt-get install git curl wget
sudo apt-get install -y python-pygments
sudo apt-get install -y g++ gcc gdb
sudo apt-get install -y  fakeroot build-essential ncurses-dev xz-utils libssl-dev bc flex libelf-dev bison

echo "Configuring Bash"
rm ~/.bashrc
wget https://raw.githubusercontent.com/DrSmCraft/development-env/main/bash/.bashrc -O ~/.bashrc

echo "Configuring Zsh"
rm ~/.zshrc
wget https://raw.githubusercontent.com/DrSmCraft/development-env/main/zsh/.zshrc -O ~/.zshrc

echo "Setting Zsh as default shell"
sudo usermod --shell /bin/zsh $(whoami)

echo "Configuring NeoVim"
mkdir ~/.config/
mkdir ~/.config/nvim/
wget https://raw.githubusercontent.com/DrSmCraft/development-env/main/nvim/init.vim -O ~/.config/nvim/init.vim
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

echo "Upgrading system"
sudo apt-get -y upgrade

echo "Done"
