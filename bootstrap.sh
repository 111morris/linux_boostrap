#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Linux Bootstrap Script
# Supports:
#   - Debian / Ubuntu
#   - Fedora / RHEL
#   - Arch
#   - openSUSE
#   - Alpine
#
# Run:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
# ============================================================

SCRIPT_NAME="$(basename "$0")"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$SCRIPT_NAME]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ------------------------------------------------------------
# Check root/sudo
# ------------------------------------------------------------

if [[ "$EUID" -eq 0 ]]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        error "sudo is not installed."
        error "Please install sudo or run this script as root."
        exit 1
    fi
fi

# ------------------------------------------------------------
# Detect Linux distribution
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    error "Cannot determine Linux distribution."
    exit 1
fi

source /etc/os-release

DISTRO="${ID}"
VERSION="${VERSION_ID:-unknown}"

log "Detected distribution: ${PRETTY_NAME}"

# ------------------------------------------------------------
# Package manager detection
# ------------------------------------------------------------

PACKAGE_MANAGER=""

case "$DISTRO" in
    ubuntu|debian|linuxmint|pop)
        PACKAGE_MANAGER="apt"
        ;;

    fedora|rhel|centos|rocky|almalinux)
        PACKAGE_MANAGER="dnf"
        ;;

    arch|manjaro)
        PACKAGE_MANAGER="pacman"
        ;;

    opensuse*|sles)
        PACKAGE_MANAGER="zypper"
        ;;

    alpine)
        PACKAGE_MANAGER="apk"
        ;;

    *)
        # Fallback based on available commands
        if command -v apt-get >/dev/null 2>&1; then
            PACKAGE_MANAGER="apt"
        elif command -v dnf >/dev/null 2>&1; then
            PACKAGE_MANAGER="dnf"
        elif command -v pacman >/dev/null 2>&1; then
            PACKAGE_MANAGER="pacman"
        elif command -v zypper >/dev/null 2>&1; then
            PACKAGE_MANAGER="zypper"
        elif command -v apk >/dev/null 2>&1; then
            PACKAGE_MANAGER="apk"
        else
            error "Unsupported Linux distribution."
            exit 1
        fi
        ;;
esac

success "Package manager: ${PACKAGE_MANAGER}"

# ------------------------------------------------------------
# Update system
# ------------------------------------------------------------

update_system() {

    log "Updating system..."

    case "$PACKAGE_MANAGER" in

        apt)
            $SUDO apt-get update
            $SUDO apt-get upgrade -y
            ;;

        dnf)
            $SUDO dnf upgrade --refresh -y
            ;;

        pacman)
            $SUDO pacman -Syu --noconfirm
            ;;

        zypper)
            $SUDO zypper refresh
            $SUDO zypper update -y
            ;;

        apk)
            $SUDO apk update
            $SUDO apk upgrade
            ;;

    esac

    success "System updated."
}

# ------------------------------------------------------------
# Install packages
# ------------------------------------------------------------

install_packages() {

    log "Installing common packages..."

    case "$PACKAGE_MANAGER" in

        apt)

            PACKAGES=(
                git
                curl
                wget
                unzip
                zip
                tar
                gzip
                bzip2
                xz-utils

                ca-certificates
                gnupg

                build-essential

                python3
                python3-pip
                python3-venv

                nodejs
                npm

                openssh-client

                tmux
                htop
                tree
                jq
                ripgrep
                fd-find

                vim
            )

            $SUDO apt-get install -y "${PACKAGES[@]}"
            ;;

        dnf)

            PACKAGES=(
                git
                curl
                wget
                unzip
                zip
                tar
                gzip
                bzip2
                xz

                ca-certificates

                gcc
                gcc-c++
                make

                python3
                python3-pip

                nodejs
                npm

                openssh-clients

                tmux
                htop
                tree
                jq
                ripgrep
                fd-find

                vim
            )

            $SUDO dnf install -y "${PACKAGES[@]}"
            ;;

        pacman)

            PACKAGES=(
                git
                curl
                wget
                unzip
                zip
                tar

                base-devel

                python
                python-pip

                nodejs
                npm

                openssh

                tmux
                htop
                tree
                jq
                ripgrep
                fd

                vim
            )

            $SUDO pacman -S --needed --noconfirm "${PACKAGES[@]}"
            ;;

        zypper)

            PACKAGES=(
                git
                curl
                wget
                unzip
                zip
                tar

                gcc
                gcc-c++
                make

                python3
                python3-pip

                nodejs
                npm

                openssh-clients

                tmux
                htop
                tree
                jq
                ripgrep

                vim
            )

            $SUDO zypper install -y "${PACKAGES[@]}"
            ;;

        apk)

            PACKAGES=(
                git
                curl
                wget
                unzip
                zip
                tar

                build-base

                python3
                py3-pip

                nodejs
                npm

                openssh

                tmux
                htop
                tree
                jq
                ripgrep

                vim
            )

            $SUDO apk add "${PACKAGES[@]}"
            ;;

    esac

    success "Common packages installed."
}

# ------------------------------------------------------------
# Git configuration
# ------------------------------------------------------------

configure_git() {

    log "Configuring Git..."

    # Change these values to your own.
    GIT_NAME="${GIT_NAME:-Your Name}"
    GIT_EMAIL="${GIT_EMAIL:-you@example.com}"

    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"

    git config --global init.defaultBranch main

    git config --global pull.rebase false

    git config --global core.editor vim

    git config --global color.ui auto

    success "Git configured."
}

# ------------------------------------------------------------
# Python configuration
# ------------------------------------------------------------

configure_python() {

    log "Checking Python..."

    if command -v python3 >/dev/null 2>&1; then

        PYTHON_VERSION=$(python3 --version)

        success "Python found: $PYTHON_VERSION"

    else

        warn "Python 3 was not found."
    fi
}

# ------------------------------------------------------------
# Node configuration
# ------------------------------------------------------------

configure_node() {

    log "Checking Node.js..."

    if command -v node >/dev/null 2>&1; then

        NODE_VERSION=$(node --version)

        success "Node.js found: $NODE_VERSION"

    else

        warn "Node.js was not found."
    fi

    if command -v npm >/dev/null 2>&1; then

        NPM_VERSION=$(npm --version)

        success "npm found: $NPM_VERSION"

    else

        warn "npm was not found."
    fi
}

# ------------------------------------------------------------
# Optional applications
# ------------------------------------------------------------

install_optional_software() {

    log "Installing optional software..."

    # --------------------------------------------------------
    # Add your software here.
    #
    # IMPORTANT:
    # Keep packages that exist in your distro repositories here.
    #
    # Examples:
    #
    # Docker
    # PostgreSQL
    # Redis
    # Neovim
    # Python tools
    # etc.
    # --------------------------------------------------------

    OPTIONAL_PACKAGES=(
        # neovim
        # docker
        # docker-compose
        # postgresql
        # redis
    )

    if [[ ${#OPTIONAL_PACKAGES[@]} -eq 0 ]]; then
        warn "No optional packages configured."
        return
    fi

    case "$PACKAGE_MANAGER" in

        apt)
            $SUDO apt-get install -y "${OPTIONAL_PACKAGES[@]}"
            ;;

        dnf)
            $SUDO dnf install -y "${OPTIONAL_PACKAGES[@]}"
            ;;

        pacman)
            $SUDO pacman -S --needed --noconfirm "${OPTIONAL_PACKAGES[@]}"
            ;;

        zypper)
            $SUDO zypper install -y "${OPTIONAL_PACKAGES[@]}"
            ;;

        apk)
            $SUDO apk add "${OPTIONAL_PACKAGES[@]}"
            ;;

    esac

    success "Optional software installed."
}

# ------------------------------------------------------------
# Shell configuration
# ------------------------------------------------------------

configure_shell() {

    log "Configuring shell..."

    SHELL_NAME="$(basename "${SHELL:-bash}")"

    log "Current shell: $SHELL_NAME"

    # Put aliases/environment configuration here later.

    success "Shell configuration complete."
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

print_summary() {

    echo
    echo "============================================================"
    echo " Linux Bootstrap Complete"
    echo "============================================================"
    echo
    echo "Distribution : $PRETTY_NAME"
    echo "Package mgr  : $PACKAGE_MANAGER"
    echo
    echo "Installed / checked:"
    echo "  Git"
    echo "  Python 3"
    echo "  Node.js"
    echo "  npm"
    echo "  Build tools"
    echo "  SSH"
    echo "  curl / wget"
    echo "  tmux"
    echo "  vim"
    echo "  jq"
    echo "  ripgrep"
    echo "  tree"
    echo
    echo "============================================================"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main() {

    update_system

    install_packages

    configure_git

    configure_python

    configure_node

    install_optional_software

    configure_shell

    print_summary
}

main "$@"

