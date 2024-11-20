#! /bin/bash


kernel=false
docker=false

# Check if --help argument is present
for arg in "$@"; do
    if [ "$arg" == "--help" ]; then
         echo "Usage: script.sh [options]"
        echo
        echo "This script sets up a development environment by installing various packages,"
        echo "configuring shells, and optionally setting up kernel development tools and Docker."
        echo
        echo "Options:"
        echo "  --help       Show this help message and exit"
        echo "  --kernel     Install kernel development tools (g++, gcc, gdb, etc.)"
        echo "  --docker     Install Docker and its dependencies"
        echo "  --all        Install both kernel development tools and Docker"
        exit 0
    fi

    if [ "$arg" == "--kernel" ]; then
      kernel=true
    fi
    if [ "$arg" == "--docker" ]; then
          docker=true
    fi
    if [ "$arg" == "--all" ]; then
            docker=true
            kernel=true
    fi
done

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
sudo apt-get install -y git curl wget
sudo apt-get install -y python-pygments
if [ "$kernel" = true ]; then
  sudo apt-get install -y g++ gcc gdb
  sudo apt-get install -y fakeroot build-essential ncurses-dev xz-utils libssl-dev bc flex libelf-dev bison
fi

if [ "docker" = true ]; then
  # https://docs.docker.com/engine/install/ubuntu/
  sudo apt-get install ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update

   sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


fi
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
