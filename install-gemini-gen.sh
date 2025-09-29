#!/bin/bash

#==============================================================================
# Debian Workstation Setup Script - Hybrid (GNOME/KDE) Version
#
# This script automates the setup of a Debian workstation for
# professional web browsing, light development, and media consumption.
# It automatically detects the desktop environment (GNOME or KDE)
# and adjusts the installation accordingly.
#
# Features:
# - Conditional GNOME package cleanup and extension installation
# - Modern CLI tools (fzf, eza, bat, ripgrep)
# - Complete zsh setup with plugins
# - Flatpak instead of Snap
# - Vivaldi browser + Ghostty terminal
# - Fabric installation via Go with completions
# - Media codecs for video consumption
# - Professional applications (Proton Mail/Pass, Draw.io, Cohesion)
# - Centralized configuration management
#==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
USERNAME=$(logname)
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
WORK_DIR="$USER_HOME/setup_temp"
DE_SESSION="UNKNOWN" # To be detected (GNOME, KDE)

# --- Helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_section() { echo -e "\n${BLUE}### $1 ###${NC}"; }

# Helper function to run commands as the regular user
run_as_user() {
    sudo -u "$USERNAME" env "PATH=$PATH" "GOPATH=$GOPATH" "HOME=$USER_HOME" "$@"
}


#==============================================================================
# FUNCTION DEFINITIONS
#==============================================================================

detect_desktop_environment() {
    print_section "SECTION 1: SYSTEM PREPARATION"
    if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
        DE_SESSION="GNOME"
    elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
        DE_SESSION="KDE"
    fi
    print_status "Detected Desktop Environment: ${YELLOW}$DE_SESSION${NC}"
}

prepare_system() {
    # Ensure the script is run as root
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root. Please use sudo."
        exit 1
    fi

    # Create working directory as the user
    print_status "Creating setup working directory at $WORK_DIR..."
    run_as_user mkdir -p "$WORK_DIR"
    
    # Initial package list update
    print_status "Updating package lists..."
    apt update

    # Conditional GNOME cleanup
    if [ "$DE_SESSION" == "GNOME" ]; then
        print_status "Running GNOME cleanup: Removing unnecessary packages..."
        apt purge -y \
            gnome-2048 gnome-calculator gnome-calendar gnome-characters gnome-clocks \
            gnome-contacts gnome-font-viewer gnome-logs gnome-maps gnome-music \
            gnome-photos gnome-screenshot gnome-system-monitor gnome-weather \
            gnome-games gnome-mahjongg gnome-mines gnome-sudoku gnome-tetravex \
            gnome-klotski gnome-nibbles gnome-robots gnome-taquin aisleriot \
            five-or-more four-in-a-row gnome-chess gnome-tour cheese totem \
            rhythmbox evolution thunderbird libreoffice-common >/dev/null 2>&1 || true
        print_status "GNOME cleanup complete."
    else
        print_status "Skipping GNOME package cleanup for $DE_SESSION environment."
    fi
}

install_core_tools() {
    print_section "SECTION 2: INSTALLING CORE UTILITIES & MODERN CLI TOOLS"
    print_status "Installing essential packages and modern CLI tools..."
    
    # Base packages for both DEs
    local packages=(
        apt-transport-https curl wget git build-essential zsh golang fzf tree
        htop fastfetch bat fd-find ripgrep jq btop yt-dlp glow xclip python3
        python3-pip python3-venv flatpak nodejs npm node-typescript make ffmpeg
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-vaapi
    )

    # Add GNOME-specific packages
    if [ "$DE_SESSION" == "GNOME" ]; then
        print_status "Adding GNOME-specific packages (Tweaks, Extension Manager)..."
        packages+=(gnome-tweaks gnome-software-plugin-flatpak gnome-shell-extension-manager)
    fi

    apt install -y "${packages[@]}"

    # Install eza (modern replacement for ls)
    print_status "Installing eza (modern ls replacement)..."
    wget -qO- https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz | tar xz -C /usr/local/bin eza

    # Configure fastfetch
    print_status "Configuring fastfetch with custom configuration..."
    run_as_user mkdir -p "$USER_HOME/.config/fastfetch"
    run_as_user wget -qO "$USER_HOME/.config/fastfetch/config.jsonc" https://raw.githubusercontent.com/tonybeyond/debiantrixie/main/config.jsonc
}

setup_zsh() {
    print_section "SECTION 3: SETTING UP ZSH & OH MY ZSH"
    print_status "Setting Zsh as the default shell for $USERNAME..."
    chsh -s "$(which zsh)" "$USERNAME"

    print_status "Installing Oh My Zsh..."
    run_as_user sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended"

    print_status "Installing zsh plugins (autosuggestions, syntax-highlighting, autocomplete)..."
    run_as_user git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    run_as_user git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    run_as_user git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git "${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete"

    print_status "Applying custom .zshrc configuration..."
    run_as_user wget -qO "$USER_HOME/.zshrc" https://raw.githubusercontent.com/tonybeyond/debiantrixie/main/.zshrc
}

install_desktop_apps() {
    print_section "SECTION 4: INSTALLING BROWSER & TERMINAL"
    
    # Vivaldi Browser
    print_status "Installing Vivaldi Browser..."
    wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/vivaldi-browser.gpg
    echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg] https://repo.vivaldi.com/archive/deb/ stable main" > /etc/apt/sources.list.d/vivaldi-archive.list
    apt update && apt install -y vivaldi-stable

    # Ghostty Terminal
    print_status "Installing Ghostty Terminal..."
    local arch
    arch="$(dpkg --print-architecture)"
    wget -P "$WORK_DIR" "https://download.opensuse.org/repositories/home:/clayrisser:/sid/Debian_Unstable/$arch/ghostty_1.1.3-2_$arch.deb"
    
    print_status "Installing Ghostty (handling potential terminfo conflicts)..."
    dpkg -i --force-overwrite "$WORK_DIR/ghostty_1.1.3-2_$arch.deb" || true
    apt-get install -f -y # Fix any broken dependencies

    print_status "Setting up Ghostty configuration..."
    run_as_user mkdir -p "$USER_HOME/.config/ghostty"
    run_as_user wget -qO "$USER_HOME/.config/ghostty/config" https://raw.githubusercontent.com/tonybeyond/debiantrixie/main/config
}

setup_flatpak() {
    print_section "SECTION 5: SETTING UP FLATPAK AND FLATHUB"
    print_status "Adding Flathub repository and installing applications..."
    
    # Run flatpak commands as the user in a login shell
    su - "$USERNAME" <<'EOF'
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        
        # Install applications
        flatpak install -y flathub \
            com.github.tchx84.Flatseal \
            org.videolan.VLC \
            me.proton.Pass \
            me.proton.Mail \
            com.jgraph.drawio.desktop \
            io.github.brunofin.Cohesion
EOF
    
    if run_as_user flatpak list | grep -q 'me.proton.Pass'; then
        print_status "Flatpak applications installed successfully."
    else
        print_warning "Some Flatpak installations may have failed. Please check manually."
    fi
}

setup_gnome_specifics() {
    if [ "$DE_SESSION" != "GNOME" ]; then
        print_section "SECTION 6: SKIPPING GNOME-SPECIFIC SETUP"
        print_status "Skipping GNOME Shell extension installation for $DE_SESSION."
        return
    fi
    
    print_section "SECTION 6: INSTALLING GNOME SHELL EXTENSIONS"
    print_status "Installing base packages for GNOME extensions..."
    apt install -y gnome-shell-extensions gnome-shell-extension-prefs gnome-shell-extension-user-theme

    # Pop Shell
    print_status "Installing Pop Shell Tiling Extension..."
    run_as_user bash -c "cd '$WORK_DIR' && git clone https://github.com/pop-os/shell.git && cd shell && git checkout master_noble && make local-install"

    # Blur My Shell
    if apt-cache show gnome-shell-extension-blur-my-shell >/dev/null 2>&1; then
        print_status "Installing Blur My Shell from repository..."
        apt install -y gnome-shell-extension-blur-my-shell
    else
        print_status "Installing Blur My Shell extension manually..."
        run_as_user bash -c "cd '$WORK_DIR' && git clone https://github.com/aunetx/blur-my-shell.git && cd blur-my-shell && make install"
    fi

    print_warning "Please enable your desired extensions using the 'Extension Manager' application after reboot."
}

install_fabric() {
    print_section "SECTION 7: INSTALLING FABRIC (BY DANIEL MIESSLER)"
    print_status "Installing Fabric via Go with Zsh completions..."

    # Run installation and setup in a user login shell
    su - "$USERNAME" <<'EOF'
        # Set Go environment variables for this session
        export GOPATH="$HOME/go"
        export PATH="$PATH:$GOPATH/bin:/usr/local/go/bin"
        
        # Install Fabric
        go install github.com/danielmiessler/fabric/cmd/fabric@latest
        
        # Clone repo for completions
        cd "$HOME/setup_temp"
        git clone https://github.com/danielmiessler/fabric.git
        
        # Setup zsh completions
        mkdir -p "$HOME/.zsh/completions"
        cp fabric/completions/_fabric "$HOME/.zsh/completions/"
        
        # Create empty .env file
        mkdir -p "$HOME/.config/fabric"
        touch "$HOME/.config/fabric/.env"
EOF

    if [ -f "$USER_HOME/go/bin/fabric" ]; then
        print_status "Fabric installed successfully."
    else
        print_warning "Fabric installation may have failed. Please check manually."
    fi
}

final_cleanup() {
    print_section "SECTION 8: FINAL OPTIMIZATIONS & CLEANUP"
    print_status "Cleaning up APT cache and removing orphaned packages..."
    apt autoremove -y >/dev/null 2>&1
    apt autoclean >/dev/null 2>&1

    print_status "Cleaning up temporary setup directory..."
    run_as_user rm -rf "$WORK_DIR"

    print_status "Disabling unnecessary services..."
    systemctl disable bluetooth.service >/dev/null 2>&1 || true
    systemctl disable cups.service >/dev/null 2>&1 || true

    print_status "System optimizations completed."
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================
main() {
    detect_desktop_environment
    prepare_system
    install_core_tools
    setup_zsh
    install_desktop_apps
    setup_flatpak
    setup_gnome_specifics # This function is conditional internally
    install_fabric
    final_cleanup

    # --- Finalization ---
    echo
    print_status "=========================================="
    print_status "Debian Workstation Setup Complete!"
    print_status "=========================================="
    echo "✓ System configured for ${YELLOW}$DE_SESSION${NC}."
    echo "✓ Core utilities and modern CLI tools installed."
    echo "✓ Zsh, Oh My Zsh, and plugins are configured."
    echo "✓ Vivaldi Browser and Ghostty Terminal installed."
    echo "✓ Flatpak with professional applications is ready."
    if [ "$DE_SESSION" == "GNOME" ]; then
        echo "✓ GNOME cleaned up and extensions (Pop Shell, etc.) installed."
    fi
    echo "✓ Fabric by Daniel Miessler is installed."
    echo
    echo "-----------------------------------------------------------------"
    echo "IMPORTANT: A reboot is required for all changes to take full effect."
    echo "After rebooting, please do the following:"
    if [ "$DE_SESSION" == "GNOME" ]; then
        echo "1. Open 'Extension Manager' to enable and configure extensions."
    fi
    echo "2. Run 'fabric --setup' to configure Fabric."
    echo "3. Test commands like 'fastfetch', 'ls' (eza), and 'cat' (bat)."
    echo "4. Enjoy your new setup! ✨"
    echo "-----------------------------------------------------------------"
    echo
    
    read -p "Reboot now? (y/n): " REBOOT_CHOICE
    if [[ "$REBOOT_CHOICE" == "y" || "$REBOOT_CHOICE" == "Y" ]]; then
        echo "Rebooting..."
        reboot
    else
        echo "Please reboot your system manually to apply all changes."
    fi
}

main "$@"

exit 0
