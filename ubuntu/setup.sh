#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "ERROR: command failed at line $LINENO (exit $?)" >&2' ERR


dry_run=false
kernel=false
docker=false
docker_group=false
# By default, remove vim
remove_vim=true

LOG_FILE="${LOG_FILE:-$HOME/setup.log}"
REPO_URL="https://raw.githubusercontent.com/DrSmCraft/development-env/main"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Run a command, or just print it in --dry-run mode.
run() {
    if [ "$dry_run" = true ]; then
        printf '[dry-run] %s\n' "$*"
    else
        "$@"
    fi
}


function show_help {
    echo "Usage: setup.sh [options]"
    echo
    echo "This script sets up a development environment by installing various packages,"
    echo "configuring shells, and optionally setting up kernel development tools and Docker."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -k, --kernel     Install kernel development tools (g++, gcc, gdb, etc.)"
    echo "  -d, --docker     Install Docker and its dependencies"
    echo "  --docker-group   Add the current user to the 'docker' group (root-equivalent!)"
    echo "  --all            Install both kernel development tools and Docker"
    echo "  --dry-run        Print what would be done without changing anything"
    exit 0
}


parse_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help)      show_help; exit 0 ;;
            -k|--kernel)       kernel=true ;;
            -d|--docker)       docker=true ;;
            --docker-group)       docker_group=true ;;
            --all)          kernel=true; docker=true ;;
            --dry-run)      dry_run=true ;;
            *)              show_help >&2; die "Unknown option: $arg" ;;
        esac
    done
}



# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight() {
    command -v sudo >/dev/null 2>&1 \
        || die "sudo is not installed. As root, run: apt-get install sudo && usermod -aG sudo $USER"

    [ -r /etc/os-release ] || die "Cannot detect OS: /etc/os-release is missing."
    # shellcheck disable=SC1091
    . /etc/os-release

    # Work out which Docker repo to use (ubuntu or debian), including derivatives.
    case "${ID:-}" in
        ubuntu|debian) DOCKER_REPO_ID="$ID" ;;
        *)
            case " ${ID_LIKE:-} " in
                *" ubuntu "*) DOCKER_REPO_ID=ubuntu ;;
                *" debian "*) DOCKER_REPO_ID=debian ;;
                *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu/Debian only." ;;
            esac
            ;;
    esac

    if [ "$DOCKER_REPO_ID" = ubuntu ]; then
        DOCKER_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    else
        DOCKER_CODENAME="${VERSION_CODENAME:-}"
    fi

    if [ "$docker" = true ] && [ -z "$DOCKER_CODENAME" ]; then
        die "Could not determine the release codename for the Docker repository."
    fi

    log "Detected: ${PRETTY_NAME:-$ID} (Docker repo: $DOCKER_REPO_ID/$DOCKER_CODENAME)"
}



# ---------------------------------------------------------------------------
# Package installation
# ---------------------------------------------------------------------------
# Install packages that may not exist on every release; skip missing ones.
install_optional() {
    local pkg
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            apt install -y "$pkg" || warn "Failed to install optional package: $pkg"
        else
            warn "Package not available on this release, skipping: $pkg"
        fi
    done
}


update_system() {
    log "Updating package lists and upgrading system"
    run sudo apt update
    run sudo apt upgrade -y
}

install_base() {
    log "Installing base packages"
    run sudo apt install -y \
        neovim net-tools zip unzip tree zsh git curl wget ca-certificates \
        cloc ncdu ranger lsof

    # Not present on all releases (e.g. duf needs Ubuntu 22.04+ / Debian 12+).
    install_optional duf glances magic-wormhole python3-pygments

    if [ "$remove_vim" = true ]; then
        log "Removing vim and setting Neovim as the default editor"
        run sudo apt remove -y vim vim-tiny vim-common || warn "Could not remove vim packages"
        if command -v nvim >/dev/null 2>&1; then
            run sudo update-alternatives --set editor "$(command -v nvim)" \
                || warn "Could not set nvim as the default editor"
        fi
    fi
}

install_kernel_tools() {
    log "Installing kernel development tools"
    run sudo apt install -y \
        build-essential gdb fakeroot libncurses-dev xz-utils libssl-dev \
        bc flex bison libelf-dev dwarves rsync cpio
}


# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------
remove_conflicting_docker_pkgs() {
    local pkg
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            warn "Removing conflicting package: $pkg"
            run sudo apt remove -y "$pkg"
        fi
    done
}

install_docker() {
    log "Installing Docker Engine"
    # https://docs.docker.com/engine/install/ubuntu/ (and /debian/)
    remove_conflicting_docker_pkgs

    run sudo apt install -y ca-certificates curl
    run sudo install -m 0755 -d /etc/apt/keyrings
    run sudo curl -fsSL "https://download.docker.com/linux/${DOCKER_REPO_ID}/gpg" \
        -o /etc/apt/keyrings/docker.asc
    run sudo chmod a+r /etc/apt/keyrings/docker.asc

    local repo_line
    repo_line="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_REPO_ID} ${DOCKER_CODENAME} stable"
    if [ "$dry_run" = true ]; then
        printf '[dry-run] write to /etc/apt/sources.list.d/docker.list: %s\n' "$repo_line"
    else
        printf '%s\n' "$repo_line" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi

    run sudo apt update
    run sudo apt install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    if [ "$docker_group" = true ]; then
        log "Adding $USER to the docker group (log out/in to take effect)"
        run sudo usermod -aG docker "$USER"
    fi
}


# ---------------------------------------------------------------------------
# Dotfiles and shell configuration
# ---------------------------------------------------------------------------
# Download to a temp file first so a failed download never clobbers the
# existing config; back up whatever was there before.
fetch_config() {  # usage: fetch_config <path-in-repo> <destination>
    local path=$1 dest=$2 url tmp
    url="${REPO_URL}/${path}"

    log "Fetching from $url"

    if [ "$dry_run" = true ]; then
        printf '[dry-run] fetch %s -> %s\n' "$url" "$dest"
        return 0
    fi

    tmp=$(mktemp)
    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        warn "Failed to download $url; leaving $dest untouched."
        return 1
    fi

    run mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ]; then
        run cp -a "$dest" "${dest}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    run mv "$tmp" "$dest"
    log "Installed $dest"
}

configure_shells() {
    log "Configuring Bash and Zsh"
    fetch_config bash/.bashrc "$HOME/.bashrc" || true
    fetch_config zsh/.zshrc   "$HOME/.zshrc"  || true

    log "Setting Zsh as the default shell"
    local zsh_path
    zsh_path=$(command -v zsh) || { warn "zsh not found; skipping shell change"; return 0; }
    if ! grep -qx "$zsh_path" /etc/shells; then
        if [ "$dry_run" = true ]; then
            printf '[dry-run] add %s to /etc/shells\n' "$zsh_path"
        else
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        fi
    fi
    # Using sudo avoids the password prompt chsh gives when run directly.
    run sudo chsh -s "$zsh_path" "$USER"
}

configure_neovim() {
    log "Configuring Neovim"
    fetch_config nvim/init.vim "$HOME/.config/nvim/init.vim" || true

    local plug="$HOME/.local/share/nvim/site/autoload/plug.vim"
    if [ "$dry_run" = true ]; then
        printf '[dry-run] fetch vim-plug -> %s and run :PlugInstall\n' "$plug"
        return 0
    fi

    run mkdir -p "$(dirname "$plug")"
    run curl -fsSL https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim \
        -o "$plug" || { warn "Failed to download vim-plug"; return 0; }

    if [ -f "$HOME/.config/nvim/init.vim" ]; then
        run nvim --headless +PlugInstall +qall \
            || warn "PlugInstall failed; run :PlugInstall manually inside nvim"
    fi
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log "Starting setup script at $(date)"
    parse_args "$@"

    # Log everything to the console and a file.
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Logging to $LOG_FILE"

    preflight
    update_system
    install_base
    if [ "$kernel" = true ]; then install_kernel_tools; fi
    if [ "$docker" = true ]; then install_docker; fi
    configure_shells
    configure_neovim

    if [ "$docker_group" = true ]; then
        echo "Log out and back in for shell and docker group changes to take effect."
    else
        echo "Log out and back in for the shell change to take effect."
    fi

    log "Done"
    exit 0;
}

main "$@"