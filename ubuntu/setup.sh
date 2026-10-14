#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "ERROR: command failed at line $LINENO (exit $?)" >&2' ERR


dry_run=false
kernel=false
docker=false
docker_group=false
jdk=false
jdk_version=""      # empty = newest stable (LTS) release available
python=false
python_version=""   # empty = newest stable release available (e.g. 3.12)
# By default, remove vim (disable with --keep-vim)
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

# Non-interactive apt-get. `sudo env` is used because sudo resets the
# environment by default, so a plain `export` would never reach apt.
#   DEBIAN_FRONTEND=noninteractive  -> no debconf dialogs
#   NEEDRESTART_MODE=a              -> needrestart restarts services automatically
apt_get() {
    run sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@"
}


show_help() {
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
    echo "  --jdk[=VERSION]  Install OpenJDK (headless) and set JAVA_HOME in /etc/profile.d/jdk.sh."
    echo "                   Without VERSION, the newest stable (LTS) release available is used."
    echo "                   Example: --jdk=21"
    echo "  --python[=X.Y]   Install Python from the distro's apt repositories (side by side;"
    echo "                   the system python3 is left alone). Without X.Y, the newest"
    echo "                   stable release available is used. Example: --python=3.12"
#    echo "  --keep-vim       Do not remove vim or change the default editor"
    echo "  --dry-run        Print what would be done without changing anything"
}


parse_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help)        show_help; exit 0 ;;
            -k|--kernel)      kernel=true ;;
            -d|--docker)      docker=true ;;
            --docker-group)   docker_group=true ;;
            --all)            kernel=true; docker=true ;;
            --jdk)            jdk=true ;;
            --jdk=*)
                jdk=true
                jdk_version="${arg#--jdk=}"
                [[ "$jdk_version" =~ ^[0-9]+$ ]] \
                    || die "Invalid JDK version '$jdk_version' (expected a whole number such as 17 or 21)."
                ;;
#            --keep-vim)       remove_vim=false ;;
            --python)         python=true ;;
            --python=*)
                python=true
                python_version="${arg#--python=}"
                [[ "$python_version" =~ ^3\.[0-9]+$ ]] \
                    || die "Invalid Python version '$python_version' (expected major.minor, such as 3.12)."
                ;;
            --dry-run)        dry_run=true ;;
            *)                show_help >&2; die "Unknown option: $arg" ;;
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
            apt_get install -y "$pkg" || warn "Failed to install optional package: $pkg"
        else
            warn "Package not available on this release, skipping: $pkg"
        fi
    done
}

# Print the apt candidate version of a package ("(none)" or empty if unavailable).
apt_candidate() {
    apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}' || true
}

apt_installable() {
    local cand
    cand=$(apt_candidate "$1")
    [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

# True for early-access / alpha / beta / release-candidate package versions,
# e.g. OpenJDK 26~13ea-1 or Python 3.14.0~rc2-1, ~b1, ~a3.
is_prerelease_version() {
    local re='~([0-9.]*(ea|alpha|beta)|(a|b|rc)[0-9]+)'
    [[ "$1" =~ $re ]]
}


update_system() {
    log "Updating package lists and upgrading system"
    apt_get update
    # --force-confold keeps existing config files instead of prompting.
    apt_get upgrade -y -o Dpkg::Options::=--force-confold
}

install_base() {
    log "Installing base packages"
    apt_get install -y \
        neovim net-tools zip unzip tree zsh git curl wget ca-certificates \
        cloc ncdu ranger lsof

    # Not present on all releases (e.g. duf needs Ubuntu 22.04+ / Debian 12+).
    install_optional duf glances magic-wormhole python3-pygments

    if [ "$remove_vim" = true ]; then
        log "Removing vim and setting Neovim as the default editor"
        apt_get remove -y vim vim-tiny vim-common || warn "Could not remove vim packages"
        if command -v nvim >/dev/null 2>&1; then
            run sudo update-alternatives --set editor "$(command -v nvim)" \
                || warn "Could not set nvim as the default editor"
        fi
    fi
}

install_kernel_tools() {
    log "Installing kernel development tools"
    apt_get install -y \
        build-essential gdb fakeroot libncurses-dev xz-utils libssl-dev \
        bc flex bison libelf-dev dwarves rsync cpio
}


# ---------------------------------------------------------------------------
# Java (OpenJDK)
# ---------------------------------------------------------------------------
# "Latest stable" means the newest LTS release. Non-LTS releases are short-lived
# and early-access (alpha/beta) builds are never picked automatically.
JDK_LTS_VERSIONS="8 11 17 21 25 29"   # ascending

jdk_pkg_name() { printf 'openjdk-%s-jdk-headless' "$1"; }

jdk_candidate()       { apt_candidate "$(jdk_pkg_name "$1")"; }
jdk_is_installable() { apt_installable "$(jdk_pkg_name "$1")"; }

# Major versions of OpenJDK installable on this release, ascending.
available_jdk_versions() {
    local v
    apt-cache pkgnames openjdk- 2>/dev/null \
        | sed -nE 's/^openjdk-([0-9]+)-jdk-headless$/\1/p' \
        | sort -un \
        | while read -r v; do
            if jdk_is_installable "$v"; then printf '%s\n' "$v"; fi
        done
}

# Sets JDK_RESOLVED to the major version to install, or dies.
# Note: with --dry-run the package lists are not refreshed, so this uses
# whatever apt already knows about.
resolve_jdk_version() {
    local v cand best=""

    if [ -n "$jdk_version" ]; then
        if ! jdk_is_installable "$jdk_version"; then
            die "OpenJDK $jdk_version is not available on this release. Available: $(available_jdk_versions | tr '\n' ' ')"
        fi
        cand=$(jdk_candidate "$jdk_version")
        if is_prerelease_version "$cand"; then
            warn "OpenJDK $jdk_version is a pre-release (early-access) build here: $cand"
        fi
        JDK_RESOLVED=$jdk_version
        return 0
    fi

    for v in $JDK_LTS_VERSIONS; do
        jdk_is_installable "$v" || continue
        cand=$(jdk_candidate "$v")
        if is_prerelease_version "$cand"; then
            warn "Skipping OpenJDK $v: pre-release build ($cand)"
            continue
        fi
        best=$v    # list is ascending, so the last match is the newest
    done

    [ -n "$best" ] \
        || die "No stable (LTS) OpenJDK found in the apt repositories. Available: $(available_jdk_versions | tr '\n' ' ')"
    JDK_RESOLVED=$best
}

write_jdk_profile() {  # usage: write_jdk_profile <java_home>
    local java_home=$1 dest=/etc/profile.d/jdk.sh content
    content=$(printf '# Managed by setup.sh\nexport JAVA_HOME=%s\n' "$java_home")

    if [ "$dry_run" = true ]; then
        printf '[dry-run] write %s:\n%s\n' "$dest" "$content"
        return 0
    fi
    printf '%s\n' "$content" | sudo tee "$dest" >/dev/null
    sudo chmod 644 "$dest"
    log "Wrote $dest"
}

install_jdk() {
    log "Installing OpenJDK"
    resolve_jdk_version

    local pkg java_home
    pkg=$(jdk_pkg_name "$JDK_RESOLVED")
    java_home="/usr/lib/jvm/java-${JDK_RESOLVED}-openjdk-$(dpkg --print-architecture)"
    log "Selected OpenJDK $JDK_RESOLVED ($pkg)"

    apt_get install -y "$pkg"

    if [ "$dry_run" != true ] && [ ! -d "$java_home" ]; then
        warn "Expected JAVA_HOME directory not found: $java_home; skipping JAVA_HOME setup."
        return 0
    fi

    # Make this version the system default even if another JDK is installed.
    run sudo update-alternatives --set java  "$java_home/bin/java" \
        || warn "Could not set default java alternative"
    run sudo update-alternatives --set javac "$java_home/bin/javac" \
        || warn "Could not set default javac alternative"

    write_jdk_profile "$java_home"

    if [ "$dry_run" != true ]; then
        "$java_home/bin/java" -version
        "$java_home/bin/javac" -version
    fi
}


# ---------------------------------------------------------------------------
# Python (distro packages)
# ---------------------------------------------------------------------------
# Only versions packaged by the distro are available (no PPAs). "Latest stable"
# is the highest pythonX.Y with an apt candidate that is not a pre-release.
# The interpreter is installed side by side as pythonX.Y; /usr/bin/python3 is
# deliberately left untouched because system tools depend on it.
python_pkg_name() { printf 'python%s' "$1"; }

python_candidate()       { apt_candidate "$(python_pkg_name "$1")"; }
python_is_installable() { apt_installable "$(python_pkg_name "$1")"; }

# Installable Python versions (X.Y) on this release, ascending.
available_python_versions() {
    local v
    apt-cache pkgnames python3. 2>/dev/null \
        | sed -nE 's/^python(3\.[0-9]+)$/\1/p' \
        | sort -t. -k2,2n -u \
        | while read -r v; do
            if python_is_installable "$v"; then printf '%s\n' "$v"; fi
        done
}

# Sets PYTHON_RESOLVED to the X.Y version to install, or dies.
# Note: with --dry-run the package lists are not refreshed, so this uses
# whatever apt already knows about.
resolve_python_version() {
    local v cand best=""

    if [ -n "$python_version" ]; then
        if ! python_is_installable "$python_version"; then
            die "Python $python_version is not available from the apt repositories on this release. Available: $(available_python_versions | tr '\n' ' ')"
        fi
        cand=$(python_candidate "$python_version")
        if is_prerelease_version "$cand"; then
            warn "Python $python_version is a pre-release build here: $cand"
        fi
        PYTHON_RESOLVED=$python_version
        return 0
    fi

    for v in $(available_python_versions); do
        cand=$(python_candidate "$v")
        if is_prerelease_version "$cand"; then
            warn "Skipping Python $v: pre-release build ($cand)"
            continue
        fi
        best=$v    # list is ascending, so the last match is the newest
    done

    [ -n "$best" ] \
        || die "No stable Python found in the apt repositories. Available: $(available_python_versions | tr '\n' ' ')"
    PYTHON_RESOLVED=$best
}

install_python() {
    log "Installing Python"
    resolve_python_version

    local py="python${PYTHON_RESOLVED}"
    log "Selected Python $PYTHON_RESOLVED ($py)"

    apt_get install -y "$py" python3-pip
    # venv (needed for virtual environments on Debian/Ubuntu) and headers for
    # building C extensions; skip politely if a release does not package them.
    install_optional "${py}-venv" "${py}-dev"

    if [ "$dry_run" != true ]; then
        "$py" --version
        # Prove venv + ensurepip really work, not just that the package exists.
        local tmp
        tmp=$(mktemp -d)
        if "$py" -m venv "$tmp/venv"; then
            log "$py can create virtual environments"
        else
            warn "$py could not create a virtual environment; is ${py}-venv installed?"
        fi
        rm -rf "$tmp"
    fi
}


# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------
remove_conflicting_docker_pkgs() {
    local pkg
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 \
               podman-docker containerd runc; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            warn "Removing conflicting package: $pkg"
            apt_get remove -y "$pkg"
        fi
    done
}

install_docker() {
    log "Installing Docker Engine"
    # https://docs.docker.com/engine/install/ubuntu/ (and /debian/)
    remove_conflicting_docker_pkgs

    apt_get install -y ca-certificates curl
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

    apt_get update
    apt_get install -y docker-ce docker-ce-cli containerd.io \
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

    # mktemp creates files as 0600; dotfiles should be normal 0644.
    chmod 644 "$tmp"

    run mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ]; then
        run cp -a "$dest" "${dest}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    run mv "$tmp" "$dest"
    log "Installed $dest"
}

# /etc/profile.d is only read by login shells, and the dotfiles fetched above
# replace ~/.bashrc and ~/.zshrc on every run. So after fetching, make sure both
# rc files source jdk.sh (idempotent: skipped if the line is already there).
ensure_jdk_in_rc() {  # usage: ensure_jdk_in_rc <rc-file>
    local rc=$1
    if [ "$dry_run" = true ]; then
        printf '[dry-run] ensure %s sources /etc/profile.d/jdk.sh\n' "$rc"
        return 0
    fi
    if [ ! -f "$rc" ]; then
        warn "$rc not found; JAVA_HOME will not be set for that shell."
        return 0
    fi
    if grep -qF '/etc/profile.d/jdk.sh' "$rc"; then
        return 0
    fi
    cat >> "$rc" <<'EOF'

# JAVA_HOME (added by setup.sh)
if [ -r /etc/profile.d/jdk.sh ]; then . /etc/profile.d/jdk.sh; fi
EOF
    log "Added JAVA_HOME source line to $rc"
}

configure_shells() {
    log "Configuring Bash and Zsh"
    fetch_config bash/.bashrc "$HOME/.bashrc" || true
    fetch_config zsh/.zshrc   "$HOME/.zshrc"  || true

    if [ "$jdk" = true ]; then
        ensure_jdk_in_rc "$HOME/.bashrc"
        ensure_jdk_in_rc "$HOME/.zshrc"
    fi

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
    # Log everything (including argument errors) to the console and a file.
    exec > >(tee -a "$LOG_FILE") 2>&1

    log "Starting setup script at $(date)"
    log "Logging to $LOG_FILE"

    parse_args "$@"

    preflight
    update_system
    install_base
    if [ "$jdk" = true ]; then install_jdk; fi
    if [ "$python" = true ]; then install_python; fi
    if [ "$kernel" = true ]; then install_kernel_tools; fi
    if [ "$docker" = true ]; then install_docker; fi
    configure_shells
    configure_neovim

    if [ "$jdk" = true ]; then
        warn "JAVA_HOME is defined in /etc/profile.d/jdk.sh and sourced from ~/.bashrc and ~/.zshrc. Open a new shell to pick it up."
    fi

    if [ "$python" = true ]; then
        echo "Python ${PYTHON_RESOLVED:-} is installed as python${PYTHON_RESOLVED:-X.Y}; the system python3 was not changed. Use: python${PYTHON_RESOLVED:-X.Y} -m venv .venv"
    fi

    if [ "$docker_group" = true ]; then
        warn "Log out and back in for shell and docker group changes to take effect."
    else
        warn "Log out and back in for the shell change to take effect."
    fi

    log "Finished setup script at $(date)"
    exit 0
}

main "$@"