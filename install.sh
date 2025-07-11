#!/bin/bash

#==============================================================================
# Debian Trixie Workstation Setup Script - Complete Hybrid Version
#
# This script automates the setup of a Debian Trixie workstation for
# professional web browsing, light development, and media consumption.
#
# Features:
# - GNOME package cleanup for lean system
# - Modern CLI tools (fzf, eza, bat, ripgrep)
# - Complete zsh setup with plugins
# - Flatpak instead of Snap
# - Vivaldi browser + Ghostty terminal
# - GNOME extensions (Pop Shell, Blur My Shell, etc.)
# - Fabric installation via Go
# - Media codecs for video consumption
# - Professional applications (Proton Mail/Pass, Draw.io, Cohesion)
#==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
USERNAME=$(logname)
USER_HOME=$(eval echo ~$USERNAME)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

#==============================================================================
# SECTION 1: SYSTEM PREPARATION & GNOME CLEANUP
#==============================================================================
echo "### SECTION 1: SYSTEM PREPARATION & GNOME CLEANUP ###"

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  print_error "This script must be run as root. Please use sudo."
  exit 1
fi

print_status "Removing unnecessary GNOME packages for a lean system..."
apt purge -y \
    gnome-2048 \
    gnome-calculator \
    gnome-calendar \
    gnome-characters \
    gnome-clocks \
    gnome-contacts \
    gnome-documents \
    gnome-font-viewer \
    gnome-logs \
    gnome-maps \
    gnome-music \
    gnome-photos \
    gnome-screenshot \
    gnome-system-monitor \
    gnome-weather \
    gnome-games \
    gnome-mahjongg \
    gnome-mines \
    gnome-sudoku \
    gnome-tetravex \
    gnome-klotski \
    gnome-nibbles \
    gnome-robots \
    gnome-taquin \
    aisleriot \
    five-or-more \
    four-in-a-row \
    gnome-chess \
    gnome-tour \
    cheese \
    totem \
    rhythmbox \
    evolution \
    thunderbird \
    libreoffice-common \
    2>/dev/null || true

print_status "Changing APT sources from Bookworm to Trixie..."
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list

print_status "Updating package lists and upgrading the system..."
apt update && apt upgrade -y

echo "### System updated to Trixie and unnecessary packages removed. ###"
echo

#==============================================================================
# SECTION 2: CORE UTILITIES & MODERN CLI TOOLS
#==============================================================================
echo "### SECTION 2: INSTALLING CORE UTILITIES & MODERN CLI TOOLS ###"

print_status "Installing essential packages and modern CLI tools..."
apt install -y \
    apt-transport-https \
    curl \
    wget \
    git \
    gnome-tweaks \
    build-essential \
    zsh \
    golang \
    fzf \
    tree \
    htop \
    fastfetch \
    bat \
    fd-find \
    ripgrep \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    flatpak \
    gnome-software-plugin-flatpak \
    nodejs \
    npm \
    node-typescript \
    make \
    ffmpeg \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-vaapi \
    eza

echo "### Core utilities and modern CLI tools installed. ###"
echo

#==============================================================================
# SECTION 3: ZSH & OH MY ZSH SETUP WITH PLUGINS
#==============================================================================
echo "### SECTION 3: SETTING UP ZSH & OH MY ZSH WITH PLUGINS ###"

print_status "Setting Zsh as the default shell for $USERNAME..."
chsh -s $(which zsh) $USERNAME

print_status "Installing Oh My Zsh..."
sudo -u $USERNAME sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended"

print_status "Installing zsh plugins..."
# zsh-autosuggestions
sudo -u $USERNAME git clone https://github.com/zsh-users/zsh-autosuggestions ${USER_HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions

# zsh-syntax-highlighting
sudo -u $USERNAME git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${USER_HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# zsh-autocomplete
sudo -u $USERNAME git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git ${USER_HOME}/.oh-my-zsh/custom/plugins/zsh-autocomplete

print_status "Downloading and applying custom .zshrc configuration..."
sudo -u $USERNAME wget -O $USER_HOME/.zshrc https://raw.githubusercontent.com/tonybeyond/ubuntu2404/main/zsh/.zshrc

# Add plugins, Go path, and modern aliases to .zshrc
cat >> $USER_HOME/.zshrc << EOF

# Enhanced plugin configuration
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete)

# Go environment variables
export GOPATH=\$HOME/go
export PATH=\$PATH:\$GOPATH/bin:/usr/local/go/bin

# FZF configuration
if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
fi
if [ -f /usr/share/doc/fzf/examples/completion.zsh ]; then
    source /usr/share/doc/fzf/examples/completion.zsh
fi

# FZF options for better experience
export FZF_DEFAULT_OPTS='--layout=reverse --height=80% --preview "cat {} || tree -C {} | head -100"'

# Modern command aliases
alias ls='eza --icons'
alias ll='eza -l --icons'
alias la='eza -la --icons'
alias tree='eza --tree --icons'
alias cat='batcat'
alias find='fd'
alias neofetch='fastfetch' 
alias grep='rg'
EOF

# Fix ownership of the .zshrc file
chown $USERNAME:$USERNAME $USER_HOME/.zshrc

echo "### Zsh & Oh My Zsh with plugins configured. ###"
echo

#==============================================================================
# SECTION 4: BROWSER & TERMINAL INSTALLATION
#==============================================================================
echo "### SECTION 4: INSTALLING VIVALDI BROWSER & GHOSTTY TERMINAL ###"

# --- Vivaldi Browser Installation ---
print_status "Installing Vivaldi Browser..."
wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/vivaldi-browser.gpg
echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg] https://repo.vivaldi.com/archive/deb/ stable main" > /etc/apt/sources.list.d/vivaldi-archive.list
apt update && apt install -y vivaldi-stable

# --- Ghostty Terminal Installation ---
print_status "Installing Ghostty Terminal..."
cd /tmp
ARCH="$(dpkg --print-architecture)"
curl -LO https://download.opensuse.org/repositories/home:/clayrisser:/sid/Debian_Unstable/$ARCH/ghostty_1.1.3-2_$ARCH.deb
apt install -y ./ghostty_1.1.3-2_$ARCH.deb

# Create Ghostty config directory and copy configuration
print_status "Setting up Ghostty configuration..."
sudo -u $USERNAME mkdir -p $USER_HOME/.config/ghostty
sudo -u $USERNAME wget -O $USER_HOME/.config/ghostty/config https://raw.githubusercontent.com/tonybeyond/ubuntu2404/refs/heads/main/ghostty/.config/ghostty/config

# Fix ownership of config file
chown -R $USERNAME:$USERNAME $USER_HOME/.config/ghostty

cd ~

echo "### Vivaldi and Ghostty installed with custom configuration. ###"
echo


#==============================================================================
# SECTION 5: FLATPAK & FLATHUB SETUP
#==============================================================================
echo "### SECTION 5: SETTING UP FLATPAK AND FLATHUB ###"

print_status "Switching to user context for Flatpak installations..."
su - $USERNAME << 'EOF'
    # Add Flathub repository
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    # Install basic Flatpak applications
    flatpak install -y flathub org.mozilla.firefox com.github.tchx84.Flatseal org.videolan.VLC
    
    # Install additional professional applications
    flatpak install -y flathub me.proton.Pass me.proton.Mail com.jgraph.drawio.desktop io.github.brunofin.Cohesion
EOF

# Verify installations completed successfully
if su - $USERNAME -c "flatpak list | grep -q 'me.proton.Pass'"; then
    print_status "Flatpak applications installed successfully"
else
    print_warning "Some Flatpak installations may have failed. Check manually."
fi

echo "### Flatpak setup complete with all applications installed. ###"
echo

#==============================================================================
# SECTION 8: FABRIC (BY DANIEL MIESSLER) INSTALLATION
#==============================================================================
echo "### SECTION 8: INSTALLING FABRIC ###"

print_status "Installing Fabric via the Go method..."

# Ensure we're in the user's home directory and set proper environment
cd $USER_HOME

# Install Fabric with proper user context and environment
sudo -u $USERNAME bash -c "
    cd $USER_HOME
    export GOPATH=$USER_HOME/go
    export PATH=\$PATH:\$GOPATH/bin:/usr/local/go/bin
    export HOME=$USER_HOME
    go install github.com/danielmiessler/fabric/cmd/fabric@latest
"

# Verify installation
if [ -f "$USER_HOME/go/bin/fabric" ]; then
    print_status "Fabric installed successfully at $USER_HOME/go/bin/fabric"
else
    print_warning "Fabric installation may have failed. Please check manually."
fi

echo "### Fabric has been installed. ###"
echo


#==============================================================================
# SECTION 9: FINAL OPTIMIZATIONS & CLEANUP
#==============================================================================
echo "### SECTION 9: FINAL OPTIMIZATIONS & CLEANUP ###"

print_status "Cleaning up APT cache and removing orphaned packages..."
apt autoremove -y
apt autoclean

print_status "Setting up system optimizations..."
# Disable unnecessary services for better performance
systemctl disable cups.service 2>/dev/null || true

echo "### System optimizations completed. ###"
echo

#==============================================================================
# SECTION 10: GNOME SHELL EXTENSIONS
#==============================================================================
echo "### SECTION 10: INSTALLING GNOME SHELL EXTENSIONS ###"

print_status "Installing base packages for GNOME extensions..."
apt install -y gnome-shell-extensions gnome-shell-extension-manager gnome-shell-extension-prefs

# --- Additional Extensions from APT where available ---
print_status "Installing additional GNOME extensions from repositories..."
apt install -y \
    gnome-shell-extension-workspace-indicator \
    gnome-shell-extension-user-theme \
    2>/dev/null || true

# --- Blur My Shell Extension ---
if apt-cache show gnome-shell-extension-blur-my-shell >/dev/null 2>&1; then
    print_status "Installing Blur My Shell from repository..."
    apt install -y gnome-shell-extension-blur-my-shell
else
    print_status "Installing Blur My Shell extension manually in user context..."
    su - $USERNAME << 'EOF'
        cd /tmp
        git clone https://github.com/aunetx/blur-my-shell.git
        cd blur-my-shell
        make install
        cd ~
        rm -rf /tmp/blur-my-shell
EOF
fi

# --- Pop Shell ---
print_status "Installing Pop Shell Tiling Extension in user context..."
su - $USERNAME << 'EOF'
    cd /tmp
    git clone https://github.com/pop-os/shell.git
    cd shell
    git checkout master_noble
    make local-install
    cd ~
    rm -rf /tmp/shell
EOF

print_warning "Please enable your desired extensions using the 'Extension Manager' application after reboot."

echo "### GNOME Shell extensions installed. ###"
echo

#==============================================================================
# FINALIZATION
#==============================================================================
echo "### SETUP COMPLETE! ###"
echo
print_status "=========================================="
print_status "Debian Trixie Workstation Setup Complete!"
print_status "=========================================="
echo
echo "Installed and configured:"
echo "✓ Removed unnecessary GNOME packages (clocks, music, maps, games, etc.)"
echo "✓ Debian Trixie repositories"
echo "✓ Vivaldi Browser (instead of Brave)"
echo "✓ Flatpak with Flathub support (instead of Snap)"
echo "✓ Pop Shell GNOME extension"
echo "✓ Workspace Indicator extension"
echo "✓ Blur My Shell extension"
echo "✓ User Theme extension"
echo "✓ Oh My Zsh with plugins: autosuggestions, syntax-highlighting, autocomplete"
echo "✓ Modern CLI tools: fzf, eza, bat, ripgrep, fd-find"
echo "✓ Ghostty terminal"
echo "✓ Fabric by Daniel Miessler"
echo "✓ Media codecs for YouTube and video consumption"
echo "✓ Development tools (Node.js, Python, Go)"
echo "✓ Professional applications:"
echo "  • Proton Pass (password manager)"
echo "  • Proton Mail (secure email client)"
echo "  • Draw.io Desktop (diagram creation)"
echo "  • Cohesion (Git client)"
echo "✓ System optimizations for performance"
echo
echo "-----------------------------------------------------------------"
echo "IMPORTANT: A reboot is required for all changes to take full effect."
echo "After rebooting, please do the following:"
echo "1. Open the 'Extension Manager' app to enable and configure extensions"
echo "2. Log into Zsh (should be default) - plugins will be automatically loaded"
echo "3. Test fzf with Ctrl+R for fuzzy command history search"
echo "4. Run 'fabric --setup' to configure Fabric"
echo "5. Try modern aliases: 'ls' (eza), 'll' (eza -l), 'cat' (bat)"
echo "6. Configure Proton Pass and Proton Mail with your credentials"
echo "-----------------------------------------------------------------"
echo
read -p "Reboot now? (y/n): " REBOOT_CHOICE
if [[ "$REBOOT_CHOICE" == "y" || "$REBOOT_CHOICE" == "Y" ]]; then
    echo "Rebooting..."
    reboot
else
    echo "Please reboot your system manually to apply all changes."
fi

exit 0
