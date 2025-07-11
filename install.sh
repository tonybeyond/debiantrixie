#!/bin/bash

# Debian Trixie Workstation Setup Script - Enhanced Version
# Optimized for professional web browsing, light development, and media consumption

set -e

echo "=========================================="
echo "Debian Trixie Workstation Setup - Enhanced"
echo "=========================================="

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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Update apt sources to Trixie
print_status "Updating apt sources to Debian Trixie..."
sudo tee /etc/apt/sources.list.d/debian.sources > /dev/null << EOF
Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: trixie
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://security.debian.org/debian-security/
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

# Remove old sources.list if it exists
if [ -f /etc/apt/sources.list ]; then
    sudo mv /etc/apt/sources.list /etc/apt/sources.list.backup
fi

# Update package database
print_status "Updating package database..."
sudo apt update

# Remove unnecessary GNOME packages for a lean system
print_status "Removing unnecessary GNOME packages..."
sudo apt purge -y \
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

# Install essential packages including fzf
print_status "Installing essential packages..."
sudo apt install -y \
    curl \
    wget \
    git \
    vim \
    zsh \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    flatpak \
    gnome-software-plugin-flatpak \
    golang-go \
    nodejs \
    npm \
    typescript \
    make \
    gnome-shell-extensions \
    gnome-shell-extension-prefs \
    firefox-esr \
    fzf \
    tree \
    htop \
    neofetch \
    bat \
    fd-find \
    ripgrep \
    jq \
    python3 \
    python3-pip \
    python3-venv

# Install eza (modern replacement for ls)
print_status "Installing eza..."
cd /tmp
wget -c https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz -O - | tar xz
sudo chmod +x eza
sudo chown root:root eza
sudo mv eza /usr/local/bin/eza
cd ~

# Install Flatpak and Flathub
print_status "Setting up Flatpak and Flathub..."
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install Vivaldi Browser
print_status "Installing Vivaldi Browser..."
wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | sudo apt-key add -
echo "deb https://repo.vivaldi.com/archive/deb/ stable main" | sudo tee /etc/apt/sources.list.d/vivaldi.list
sudo apt update
sudo apt install -y vivaldi-stable

# Install Ghostty (Debian approach)
print_status "Installing Ghostty terminal..."
if ! command -v ghostty &> /dev/null; then
    cd /tmp
    git clone https://github.com/clayrisser/debian-ghostty.git
    cd debian-ghostty
    sudo ./install.sh
    cd ~
fi

# Install Oh My Zsh
print_status "Installing Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install zsh plugins
print_status "Installing zsh plugins..."
# zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# zsh-autocomplete
git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete

# Download and setup .zshrc
print_status "Setting up .zshrc configuration..."
curl -fsSL https://raw.githubusercontent.com/tonybeyond/ubuntu2404/main/zsh/.zshrc -o ~/.zshrc

# Ensure plugins are enabled in .zshrc
print_status "Configuring zsh plugins..."
# Check if plugins line exists and update it
if grep -q "plugins=(" ~/.zshrc; then
    sed -i 's/plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete)/' ~/.zshrc
else
    echo "plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete)" >> ~/.zshrc
fi

# Add fzf configuration to .zshrc
print_status "Configuring fzf..."
cat >> ~/.zshrc << 'EOF'

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
EOF

# Change default shell to zsh
print_status "Changing default shell to zsh..."
chsh -s $(which zsh)

# Install Pop Shell
print_status "Installing Pop Shell GNOME extension..."
cd /tmp
git clone https://github.com/pop-os/shell.git
cd shell
# Use the appropriate branch for current GNOME version
git checkout master_noble
make local-install
cd ~

# Install additional GNOME extensions via package manager where available
print_status "Installing additional GNOME extensions..."
sudo apt install -y \
    gnome-shell-extension-workspace-indicator \
    gnome-shell-extension-user-theme

# Install Blur My Shell extension manually
print_status "Installing Blur My Shell extension..."
cd /tmp
git clone https://github.com/aunetx/blur-my-shell.git
cd blur-my-shell
make install
cd ~

# Install Fabric by Daniel Miessler
print_status "Installing Fabric..."
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
go install github.com/danielmiessler/fabric@latest

# Add Go paths to .zshrc if not already present
if ! grep -q "export GOPATH" ~/.zshrc; then
    echo "" >> ~/.zshrc
    echo "# Go environment variables" >> ~/.zshrc
    echo "export GOPATH=\$HOME/go" >> ~/.zshrc
    echo "export PATH=\$PATH:\$GOPATH/bin:/usr/local/go/bin" >> ~/.zshrc
fi

# Install media codecs for YouTube and video playback
print_status "Installing media codecs..."
sudo apt install -y \
    ffmpeg \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-vaapi

# Clean up
print_status "Cleaning up..."
sudo apt autoremove -y
sudo apt autoclean

# Install some useful Flatpak applications
print_status "Installing useful Flatpak applications..."
flatpak install -y flathub \
    org.mozilla.firefox \
    com.github.tchx84.Flatseal \
    org.videolan.VLC

print_status "=========================================="
print_status "Enhanced setup completed successfully!"
print_status "=========================================="
print_warning "Please reboot your system to ensure all changes take effect."
print_warning "After reboot, you may need to:"
print_warning "1. Enable GNOME extensions via Extensions app"
print_warning "2. Run 'fabric --setup' to configure Fabric"
print_warning "3. Test fzf with Ctrl+R for command history search"

echo ""
echo "Installed and configured:"
echo "✓ Removed unnecessary GNOME packages (clocks, music, maps, etc.)"
echo "✓ Debian Trixie repositories"
echo "✓ Vivaldi Browser"
echo "✓ Flatpak with Flathub support"
echo "✓ Pop Shell GNOME extension"
echo "✓ Workspace Indicator extension"
echo "✓ Blur My Shell extension"
echo "✓ Oh My Zsh with plugins: autosuggestions, syntax-highlighting, autocomplete"
echo "✓ fzf (fuzzy finder) with key bindings"
echo "✓ eza (modern ls replacement)"
echo "✓ Ghostty terminal"
echo "✓ Fabric by Daniel Miessler"
echo "✓ Development tools and modern CLI utilities"
echo "✓ Media codecs"
