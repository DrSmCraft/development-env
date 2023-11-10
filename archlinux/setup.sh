#! /bin/bash

echo "Updating package list"
pacman -Sy

echo "Removing unused packages"
pacman -R --noconfirm vim


echo "Installing packages"
pacman -S --noconfirm neovim
pacman -S --noconfirm net-tools
pacman -S --noconfirm zip unzip
pacman -S --noconfirm tree
pacman -S --noconfirm zsh
pacman -S --noconfirm python-pygments
pacman -S --noconfirm g++ gcc gdb

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
pacman -Syu --noconfirm 

echo "Done"
