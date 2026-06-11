#!/usr/bin/env bash
# =============================================================================
# post-install.sh — Setup système Debian 13 Trixie
# =============================================================================
# Appelé par preseed (late_command, root, chroot via in-target).
# Lancement manuel : sudo bash /opt/debiantrixie/scripts/post-install.sh
#
# Scripts post-reboot (manuels) :
#   bash /opt/debiantrixie/scripts/niri-setup.sh       (~20 min)
#   bash /opt/debiantrixie/scripts/bash-setup.sh       (ble.sh)
#   sudo bash /opt/debiantrixie/scripts/citrix-setup.sh  (nécessite .deb)
# =============================================================================

set -euo pipefail

TARGET_USER="${SUDO_USER:-deby}"
TARGET_HOME="/home/${TARGET_USER}"
REPO_DIR="/opt/debiantrixie"
LOG_FILE="/var/log/debiantrixie-setup.log"
ERROR_COUNT=0

log_info()    { echo "[$(date +'%H:%M:%S')] ·     $*" | tee -a "${LOG_FILE}"; }
log_ok()      { echo "[$(date +'%H:%M:%S')] ✓     $*" | tee -a "${LOG_FILE}"; }
log_error()   { echo "[$(date +'%H:%M:%S')] ✗     $*" | tee -a "${LOG_FILE}" >&2; ((ERROR_COUNT++)) || true; }
log_section() { echo "" | tee -a "${LOG_FILE}"; echo "[$(date +'%H:%M:%S')] ════ $* ════" | tee -a "${LOG_FILE}"; }

is_installed() { dpkg -s "$1" &>/dev/null; }
apt_install() {
  for pkg in "$@"; do
    is_installed "$pkg" \
      || apt install -y "$pkg" 2>>"${LOG_FILE}" \
      && log_ok "apt: $pkg" \
      || log_error "apt: $pkg FAILED"
  done
}

# Exécuter en tant que TARGET_USER (robuste en chroot, sans TTY)
as_user() { su -s /bin/bash -c "HOME=${TARGET_HOME} $*" "${TARGET_USER}"; }

[[ $EUID -eq 0 ]] || { echo "Requiert root (sudo)."; exit 1; }
mkdir -p "$(dirname "${LOG_FILE}")" "${TARGET_HOME}"
log_info "=== debiantrixie post-install — $(date) ==="
log_info "Utilisateur cible : ${TARGET_USER} (${TARGET_HOME})"

# ── 1. APT update ─────────────────────────────────────────────────────────────
log_section "Mise à jour système"
apt update -q && apt upgrade -y || log_error "apt update/upgrade"

# ── 2. Paquets principaux ─────────────────────────────────────────────────────
log_section "Paquets principaux"
apt_install \
  curl git wget build-essential unzip gnupg ca-certificates apt-transport-https \
  zsh fzf eza bat btop hyfetch nala vlc xclip flameshot \
  gnome-tweaks gnome-shell-extension-manager \
  gimagereader tesseract-ocr tesseract-ocr-fra tesseract-ocr-eng \
  gawk bash-completion \
  ninja-build cmake gettext \
  flatpak gnome-software-plugin-flatpak

# Flathub (nécessaire pour Ghostty et autres apps)
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
  && log_ok "Flathub ajouté" || true

# ── 3. Locale : en_US interface + fr_CH formats ───────────────────────────────
log_section "Locale"
# Générer les deux locales
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
sed -i 's/# fr_CH.UTF-8/fr_CH.UTF-8/' /etc/locale.gen 2>/dev/null || true
locale-gen en_US.UTF-8 fr_CH.UTF-8 2>/dev/null || locale-gen

cat > /etc/default/locale << 'LOCALE_EOF'
LANG=en_US.UTF-8
LC_TIME=fr_CH.UTF-8
LC_NUMERIC=fr_CH.UTF-8
LC_MONETARY=fr_CH.UTF-8
LC_PAPER=fr_CH.UTF-8
LC_ADDRESS=fr_CH.UTF-8
LC_TELEPHONE=fr_CH.UTF-8
LC_MEASUREMENT=fr_CH.UTF-8
LC_IDENTIFICATION=fr_CH.UTF-8
LOCALE_EOF

update-locale 2>/dev/null || true
log_ok "Locale : en_US.UTF-8 (interface) + fr_CH.UTF-8 (formats)"

# ── 4. Ghostty ────────────────────────────────────────────────────────────────
log_section "Ghostty"
if ! command -v ghostty &>/dev/null; then
  # Essai 1 : paquet Debian natif (Trixie peut avoir ghostty dans ses repos)
  if apt install -y ghostty 2>/dev/null; then
    log_ok "Ghostty installé depuis apt"
  # Essai 2 : script mkasberg (compatible Debian-based)
  elif /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)" 2>/dev/null; then
    log_ok "Ghostty installé via mkasberg"
  # Fallback : Flatpak (nécessite reboot avant utilisation)
  else
    log_info "Ghostty : tentative via Flatpak..."
    flatpak install -y --noninteractive flathub com.mitchellh.ghostty 2>/dev/null \
      && log_ok "Ghostty installé via Flatpak (reboot requis)" \
      || log_error "Ghostty indisponible — installer manuellement post-reboot"
  fi
else
  log_ok "Ghostty déjà présent"
fi

mkdir -p "${TARGET_HOME}/.config/ghostty"
if [[ -f "${REPO_DIR}/configs/ghostty/config" ]]; then
  cp "${REPO_DIR}/configs/ghostty/config" "${TARGET_HOME}/.config/ghostty/config"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config/ghostty"
  log_ok "Config Ghostty déployée"
fi

# ── 5. Brave browser ──────────────────────────────────────────────────────────
log_section "Brave Browser"
if ! command -v brave-browser &>/dev/null; then
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
  apt update -q && apt install -y brave-browser \
    && log_ok "Brave installé" || log_error "Brave install"
else
  log_ok "Brave déjà présent"
fi

# ── 6. Neovim (depuis source) ─────────────────────────────────────────────────
log_section "Neovim"
if ! command -v nvim &>/dev/null; then
  BUILD_DIR="/tmp/neovim-build"
  [[ -d "${BUILD_DIR}" ]] || \
    git clone https://github.com/neovim/neovim.git --branch=stable --depth=1 "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  make CMAKE_BUILD_TYPE=RelWithDebInfo 2>>"${LOG_FILE}"
  cd build && cpack -G DEB
  DEB=$(find . -name 'nvim-linux*.deb' | head -n1)
  [[ -n "${DEB}" ]] && dpkg -i "${DEB}" && log_ok "Neovim installé" || log_error "Neovim build"
  cd /tmp
else
  log_ok "Neovim déjà présent"
fi
NVIM_CONF="${TARGET_HOME}/.config/nvim"
if [[ ! -d "${NVIM_CONF}" ]]; then
  as_user "git clone https://github.com/nvim-lua/kickstart.nvim.git ${NVIM_CONF}" \
    && log_ok "kickstart.nvim déployé" || log_error "kickstart.nvim clone"
fi

# ── 7. Oh My Zsh + plugins ────────────────────────────────────────────────────
log_section "Oh My Zsh"
if [[ ! -d "${TARGET_HOME}/.oh-my-zsh" ]]; then
  as_user "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended" \
    && log_ok "Oh My Zsh installé" || log_error "Oh My Zsh install"
fi

ZSH_PLUGINS="${TARGET_HOME}/.oh-my-zsh/custom/plugins"
mkdir -p "${ZSH_PLUGINS}"
declare -A OMZ_PLUGINS=(
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
  ["zsh-autocomplete"]="https://github.com/marlonrichert/zsh-autocomplete.git"
)
for name in "${!OMZ_PLUGINS[@]}"; do
  [[ -d "${ZSH_PLUGINS}/${name}" ]] || \
    as_user "git clone ${OMZ_PLUGINS[$name]} ${ZSH_PLUGINS}/${name}" \
    && log_ok "Plugin zsh: ${name}" || log_error "Plugin zsh: ${name}"
done

if [[ -f "${REPO_DIR}/configs/zshrc" ]]; then
  sed 's/exa /eza /g; s/exa -/eza -/g' "${REPO_DIR}/configs/zshrc" > "${TARGET_HOME}/.zshrc"
  chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.zshrc"
  log_ok ".zshrc déployé"
fi
chsh -s "$(which zsh)" "${TARGET_USER}" && log_ok "zsh shell par défaut"

# ── 8. Bash tweaks (Starship + Hack Nerd Font + .bashrc) ─────────────────────
log_section "Bash tweaks"

if ! command -v starship &>/dev/null; then
  curl -sS https://starship.rs/install.sh | sh -s -- --yes \
    && log_ok "Starship → /usr/local/bin" || log_error "Starship install"
fi

mkdir -p "${TARGET_HOME}/.config"
if [[ ! -f "${TARGET_HOME}/.config/starship.toml" ]]; then
  cat > "${TARGET_HOME}/.config/starship.toml" << 'TOML'
format = """
$os$username$hostname$directory$git_branch$git_status$python$nodejs$rust$golang$docker_context
$character"""
[os]
disabled = false
[os.symbols]
Debian = " "
[username]
style_user  = "bold green"
style_root  = "bold red"
show_always = true
format      = "[$user]($style)@"
[hostname]
ssh_only = false
format   = "[$hostname](bold blue) "
[directory]
truncation_length = 3
style             = "bold cyan"
[git_branch]
format = "[$symbol$branch]($style) "
style  = "bold yellow"
[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"
TOML
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config"
  log_ok "Config Starship créée (icône Debian)"
fi

FONT_DIR="${TARGET_HOME}/.local/share/fonts/HackNerdFont"
if [[ ! -d "${FONT_DIR}" ]]; then
  mkdir -p "${FONT_DIR}"
  curl -fLo /tmp/Hack.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip \
    && unzip -o /tmp/Hack.zip -d "${FONT_DIR}" \
    && rm /tmp/Hack.zip \
    && fc-cache -fv >/dev/null \
    && chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local" \
    && log_ok "Hack Nerd Font installée" \
    || log_error "Hack Nerd Font"
fi

BASHRC="${TARGET_HOME}/.bashrc"
if ! grep -q "debiantrixie bash tweaks" "${BASHRC}" 2>/dev/null; then
  [[ -f "${BASHRC}" ]] && cp "${BASHRC}" "${BASHRC}.bak-pre-preseed"
  cat >> "${BASHRC}" << 'BASHRC_BLOCK'

# ── debiantrixie bash tweaks ──────────────────────────────────────────────────

# ble.sh — installe via : bash /opt/debiantrixie/scripts/bash-setup.sh
[[ $- == *i* ]] && [[ -f ~/.local/share/blesh/ble.sh ]] \
  && source ~/.local/share/blesh/ble.sh --noattach

eval "$(starship init bash)"
eval "$(fzf --bash)"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

HISTSIZE=10000; HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

[[ -f /usr/share/bash-completion/bash_completion ]] \
  && source /usr/share/bash-completion/bash_completion

alias ls='eza -al --color=always --group-directories-first --icons'
alias la='eza -a  --color=always --group-directories-first --icons'
alias ll='eza -l  --color=always --group-directories-first --icons'
alias lt='eza -aT --color=always --group-directories-first --icons'
alias l.='eza -a | grep -E "^\."'
alias upall='sudo apt upgrade -y'
alias upcheck='sudo apt update'
alias cleanup='sudo apt autoremove --purge'
alias grep='grep --color=auto'
alias ip='ip --color=auto'
alias diff='diff --color=auto'
alias df='df -h'; alias du='du -h'; alias free='free -h'
alias mkdir='mkdir -pv'; alias cp='cp -iv'; alias mv='mv -iv'; alias rm='rm -iv'
alias ..='cd ..'; alias ...='cd ../..'; alias ....='cd ../../..'
alias g='git'; alias gs='git status'; alias ga='git add'
alias gc='git commit'; alias gp='git push'
alias gl='git log --oneline --graph --decorate'

[[ ${BLE_VERSION-} ]] && ble-attach
# ── fin debiantrixie bash tweaks ──────────────────────────────────────────────
BASHRC_BLOCK
  chown "${TARGET_USER}:${TARGET_USER}" "${BASHRC}"
  log_ok ".bashrc patché"
fi

# ── Shadow PC (cloud gaming/workstation) ─────────────────────────────────────
log_section "Shadow PC"
if ! is_installed shadow-prod && ! command -v shadow-prod &>/dev/null; then
  # Dépendances vidéo (VA-API/VDPAU) requises par le client
  apt_install libva-glx2 libvdpau1 libva-drm2 libcurl4 libva-wayland2

  SHADOW_DEB="/tmp/shadow-amd64.deb"
  if curl -fL --connect-timeout 15 -o "${SHADOW_DEB}" \
      "https://update.shadow.tech/launcher/prod/linux/x86_64/shadow-amd64.deb" 2>>"${LOG_FILE}"; then
    apt install -y "${SHADOW_DEB}" 2>>"${LOG_FILE}" \
      && log_ok "Shadow PC installé" \
      || log_error "Shadow PC dpkg failed"
    rm -f "${SHADOW_DEB}"

    # Groupe input requis pour la capture clavier/souris
    usermod -a -G input "${TARGET_USER}" \
      && log_ok "User ${TARGET_USER} ajouté au groupe input"

    # Support Wayland : module uinput + règle udev + groupe shadow-input
    echo "uinput" > /etc/modules-load.d/uinput.conf
    groupadd -f shadow-input
    cat > /etc/udev/rules.d/65-shadow-client.rules << 'UDEV'
KERNEL=="uinput", MODE="0660", GROUP="shadow-input"
UDEV
    usermod -a -G shadow-input "${TARGET_USER}"
    log_ok "Config Wayland (uinput + udev) appliquée — effective après reboot"
  else
    log_error "Shadow PC download failed — installer manuellement depuis shadow.tech/download"
  fi
else
  log_ok "Shadow PC déjà présent"
fi

# ── 9. Citrix Workspace ───────────────────────────────────────────────────────
log_section "Citrix Workspace"
if [[ -x "${REPO_DIR}/scripts/citrix-setup.sh" ]]; then
  bash "${REPO_DIR}/scripts/citrix-setup.sh" && log_ok "Citrix installé" \
    || log_error "Citrix SKIPPED — lancer après reboot : sudo bash /opt/debiantrixie/scripts/citrix-setup.sh"
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  debiantrixie post-install — TERMINÉ                        ║"
printf "║  Erreurs : %-3d                                               ║\n" "${ERROR_COUNT}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Scripts post-reboot :                                      ║"
echo "║  1. bash /opt/debiantrixie/scripts/niri-setup.sh  (~20 min) ║"
echo "║  2. bash /opt/debiantrixie/scripts/bash-setup.sh  (ble.sh)  ║"
echo "║  3. sudo bash /opt/debiantrixie/scripts/citrix-setup.sh     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
