#!/bin/bash
#==============================================================================
# Debian Trixie / Neptune 9 Workstation Setup Script - Hybrid GNOME/KDE Version
#
# Automates the setup of a workstation optimized for professional web browsing,
# light development, and media consumption for either Debian Trixie (GNOME) or
# Neptune 9 (Debian-based, KDE Plasma Desktop).
#
# Core Features:
# - Desktop-specific package cleanup for GNOME or KDE
# - Modern CLI tools (fzf, eza, bat, ripgrep)
# - Full zsh setup with plugins
# - Flatpak/Flathub applications
# - Vivaldi browser, Ghostty terminal
# - GNOME extensions (if GNOME), KDE optimizations (if KDE)
# - Centralized config management
# - Enhanced error handling, input validation, and safety
#==============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_NAME="Debian Trixie / Neptune 9 Setup"
readonly LOG_FILE="/var/log/debian-neptune-setup.log"

# --- Configuration ---
USERNAME=$(logname)
USER_HOME=$(eval echo ~$USERNAME)
WORK_DIR="$USER_HOME/setup_temp"
DESKTOP_TYPE=""
OS_NAME=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; log INFO "$1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; log WARNING "$1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; log ERROR "$1"; }

cleanup() {
    local exit_code=$?
    print_status "Cleaning up..."
    [[ -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR" 2>/dev/null || true
    apt-get clean 2>/dev/null || true
    exit $exit_code
}

handle_interrupt() { print_warning "Script interrupted by user"; exit 130; }

trap cleanup EXIT
trap handle_interrupt INT TERM

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

validate_inputs() {
    if [[ -z "$USERNAME" || -z "$USER_HOME" ]]; then
        print_error "Failed to determine user information"
        exit 1
    fi
    if [[ ! -d "$USER_HOME" ]]; then
        print_error "User home directory $USER_HOME does not exist"
        exit 1
    fi
}

detect_os() {
    if grep -qi neptune /etc/os-release 2>/dev/null; then
        OS_NAME="Neptune 9"
        DESKTOP_TYPE="kde"
        print_status "Detected Neptune OS 9 (KDE Plasma desktop)"
    elif grep -qi trixie /etc/os-release 2>/dev/null; then
        OS_NAME="Debian Trixie"
        DESKTOP_TYPE="gnome"
        print_status "Detected Debian Trixie (GNOME desktop)"
    else
        print_error "Unsupported OS. Only Debian Trixie and Neptune 9 are supported."
        exit 1
    fi
}

verify_package_installed() {
    local package=$1
    if ! dpkg -l | grep -q "^ii.*$package"; then
        print_error "Package $package failed to install properly"
        return 1
    fi
    print_status "Verified $package is installed"
}

run_as_user() {
    sudo -u "$USERNAME" --set-home --preserve-env=HOME "$@"
}

retry_command() {
    local retries=$1
    local wait_time=$2
    shift 2
    local count=0
    until "$@"; do
        exit_code=$?
        count=$((count + 1))
        if [[ $count -lt $retries ]]; then
            print_warning "Command failed (exit code $exit_code), retrying in ${wait_time}s..."
            sleep "$wait_time"
        else
            print_error "Command failed after $count attempts"
            return $exit_code
        fi
    done
    return 0
}

# Main Script
main() {
    check_root
    validate_inputs
    detect_os

    print_status "Creating temp working directory..."
    run_as_user mkdir -p "$WORK_DIR"

    # --- Desktop Environment Specific Cleanup ---
    if [[ "$DESKTOP_TYPE" == "gnome" ]]; then
        print_status "Cleaning up unnecessary GNOME packages..."
        apt purge -y gnome-2048 gnome-calculator gnome-calendar gnome-characters \
            gnome-clocks gnome-contacts gnome-font-viewer gnome-logs gnome-maps \
            gnome-music gnome-photos gnome-screenshot gnome-system-monitor \
            gnome-weather gnome-games gnome-mahjongg gnome-mines gnome-sudoku \
            gnome-tetravex gnome-klotski gnome-nibbles gnome-robots gnome-taquin \
            aisleriot five-or-more four-in-a-row gnome-chess gnome-tour cheese \
            totem rhythmbox evolution thunderbird libreoffice-common \
            2>/dev/null || true
    elif [[ "$DESKTOP_TYPE" == "kde" ]]; then
        print_status "Cleaning up unnecessary KDE/Neptune packages..."
        apt purge -y kpat kmines ksudoku kmahjongg kmag kmousetool \
            libreoffice-common thunderbird 2>/dev/null || true
    fi

    print_status "Updating package lists & upgrading system..."
    apt update && apt upgrade -y

    # --- Core Utilities & Modern CLI Tools ---
    print_status "Installing essential packages and modern CLI tools..."
    apt install -y apt-transport-https curl wget git build-essential zsh golang \
        fzf tree htop bat fd-find ripgrep jq btop yt-dlp glow xclip python3 \
        python3-pip python3-venv flatpak ffmpeg gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-vaapi \
        nodejs npm node-typescript make eza

    # Setup Fastfetch configuration
    print_status "Configuring fastfetch..."
    run_as_user mkdir -p "$USER_HOME/.config/fastfetch"
    retry_command 3 5 run_as_user wget -O "$USER_HOME/.config/fastfetch/config.jsonc" "https://raw.githubusercontent.com/tonybeyond/debiantrixie/main/config.jsonc"
    chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/fastfetch"

    # --- ZSH & Plugins ---
    print_status "Setting Zsh as the default shell..."
    chsh -s "$(which zsh)" "$USERNAME"

    print_status "Installing Oh My Zsh..."
    retry_command 3 5 run_as_user sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended"

    print_status "Installing zsh plugins..."
    run_as_user git clone https://github.com/zsh-users/zsh-autosuggestions "${USER_HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    run_as_user git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${USER_HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    run_as_user git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git "${USER_HOME}/.oh-my-zsh/custom/plugins/zsh-autocomplete"

    print_status "Downloading and applying custom .zshrc..."
    retry_command 3 5 run_as_user wget -O "$USER_HOME/.zshrc" "https://raw.githubusercontent.com/tonybeyond/debiantrixie/main/.zshrc"
    chown "$USERNAME:$USERNAME" "$USER_HOME/.zshrc"

    # --- Browser & Terminal ---
    print_status "Installing Vivaldi Browser..."
    wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/vivaldi-browser.gpg
    echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg] https://repo.vivaldi.com/archive/deb/ stable main" > /etc/apt/sources.list.d/vivaldi-archive.list
    apt update && apt install -y vivaldi-stable
    verify_package_installed "vivaldi-stable"

    print_status "Installing Ghostty Terminal..."
    ARCH="$(dpkg --print-architecture)"
    cd "$WORK_DIR"
    retry_command 3 5 curl -LO "https://download.opensuse.org/repositories/home:/clayrisser:/sid/Debian_Unstable/${ARCH}/ghostty_1.1.3-2_${ARCH}.deb"
    dpkg -i --force-overwrite ./ghostty_1.1.3-2_${ARCH}.deb || true
    apt-get install -f -y
    verify_package_installed "ghostty"

    run_as_user mkdir -p "$USER_HOME/.config/ghostty"
    retry_command 3 5 run_as_user wget -O "$USER_HOME/.config/ghostty/config" "https://raw.githubusercontent.com/tonybeyond/debiantrixie/main/config"
    chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/ghostty"

    # --- Flatpak & Flathub ---
    print_status "Setting up Flatpak and Flathub Apps..."
    run_as_user flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    run_as_user flatpak install -y flathub com.github.tchx84.Flatseal org.videolan.VLC
    run_as_user flatpak install -y flathub me.proton.Pass me.proton.Mail com.jgraph.drawio.desktop io.github.brunofin.Cohesion

    # --- GNOME/KDE Desktop Extensions & Tweaks ---
    if [[ "$DESKTOP_TYPE" == "gnome" ]]; then
        print_status "Installing GNOME Shell Extensions..."
        apt install -y gnome-shell-extensions gnome-shell-extension-manager gnome-shell-extension-prefs
        run_as_user git clone https://github.com/pop-os/shell.git "$WORK_DIR/pop-shell"
        cd "$WORK_DIR/pop-shell"
        run_as_user make local-install
        apt install -y gnome-shell-extension-workspace-indicator gnome-shell-extension-user-theme
        if apt-cache show gnome-shell-extension-blur-my-shell >/dev/null 2>&1; then
            apt install -y gnome-shell-extension-blur-my-shell
        else
            run_as_user git clone https://github.com/aunetx/blur-my-shell.git "$WORK_DIR/blur-my-shell"
            cd "$WORK_DIR/blur-my-shell"
            run_as_user make install
        fi
        print_warning "Enable your GNOME extensions after reboot via 'Extension Manager'."
    elif [[ "$DESKTOP_TYPE" == "kde" ]]; then
        print_status "Optimizing KDE Plasma Desktop packages..."
        apt install -y kde-config-sddm plasma-discover flatpak-kcm kdeconnect spectacle
        # No custom KDE extensions provided (KDE widgets can be managed via Discover).
        # Remove bloat/add your preferred packages here
    fi

    # --- Fabric CLI Tool Installation ---
    print_status "Installing Fabric CLI with completions..."
    run_as_user bash -c "
        cd ~/setup_temp
        export GOPATH=\$HOME/go
        export PATH=\$PATH:\$GOPATH/bin:/usr/local/go/bin
        go install github.com/danielmiessler/fabric/cmd/fabric@latest
        git clone https://github.com/danielmiessler/fabric.git
        cd fabric
        mkdir -p ~/.zsh/completions
        cp completions/_fabric ~/.zsh/completions/
        mkdir -p ~/.config/fabric
        touch ~/.config/fabric/.env
    "
    if [[ -f "$USER_HOME/go/bin/fabric" ]]; then
        print_status "Fabric installed successfully with zsh completions"
    else
        print_warning "Fabric installation may have failed."
    fi

    # --- Final Optimizations & Cleanup ---
    print_status "Cleaning up APT cache & orphaned packages..."
    apt autoremove -y
    apt autoclean

    print_status "Removing setup working directory..."
    run_as_user rm -rf "$WORK_DIR"

    print_status "Disabling unnecessary services for performance..."
    systemctl disable bluetooth.service 2>/dev/null || true
    systemctl disable cups.service 2>/dev/null || true

    print_status "=========================================="
    print_status "$OS_NAME Workstation Setup Complete!"
    print_status "=========================================="
    echo "✓ Cleaning up unnecessary desktop packages"
    echo "✓ Vivaldi Browser"
    echo "✓ Flatpak and Flathub"
    echo "✓ Oh My Zsh + plugins"
    echo "✓ Modern CLI tools"
    echo "✓ Fastfetch config"
    echo "✓ Ghostty terminal"
    echo "✓ Fabric with zsh completion"
    echo "✓ Media codecs"
    echo "✓ Development tools"
    echo "✓ Performance optimized"
    echo
    echo "IMPORTANT: Reboot required for all changes!"
    echo "After reboot:"
    echo "→ GNOME: Enable extensions via 'Extension Manager'"
    echo "→ KDE: Configure widgets/plugins as desired"
    echo "→ Run 'fabric --setup' and test completions"
    echo "→ Test fastfetch, fzf, eza, bat"
    echo "→ Configure Proton Pass/Mail"
    echo
    read -p "Reboot now? (y/n): " REBOOT_CHOICE
    if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
        print_status "Rebooting..."
        reboot
    else
        print_status "Please reboot your system manually."
    fi
}

main "$@"
