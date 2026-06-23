#!/usr/bin/env bash
# =============================================================================
# post-install.sh — Setup système Debian 13 Trixie
# =============================================================================
# Appelé par preseed (late_command, root, chroot via in-target).
# Lancement manuel : sudo bash /opt/debiantrixie/scripts/post-install.sh
#
# Scripts post-reboot (manuels) :
#   bash /opt/debiantrixie/scripts/gnome-anduinos.sh   (GNOME style Win11/AnduinOS)
#   bash /opt/debiantrixie/scripts/niri-setup.sh       (~20 min)
#   bash /opt/debiantrixie/scripts/bash-setup.sh       (ble.sh)
#   sudo bash /opt/debiantrixie/scripts/citrix-setup.sh  (nécessite .deb)
# =============================================================================

# PAS de "set -e" : ce script est best-effort (logue les échecs via log_error
# et continue). Avec set -e, le moindre apt/curl en échec tuerait tout le
# script → exit non-zéro → le preseed late_command marque l'install en échec.
set -uo pipefail

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

# ── WaveTerm (terminal AI-intégré, remplace Ghostty) ─────────────────────────
log_section "WaveTerm"
if ! command -v waveterm &>/dev/null; then
  log_info "Récupération de la dernière version WaveTerm..."
  WAVETERM_VER=$(curl -s https://api.github.com/repos/wavetermdev/waveterm/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" 2>/dev/null \
    || echo "0.14.5")
  WAVETERM_DEB="/tmp/waveterm-${WAVETERM_VER}.deb"
  WAVETERM_URL="https://github.com/wavetermdev/waveterm/releases/download/v${WAVETERM_VER}/waveterm-linux-amd64-${WAVETERM_VER}.deb"
  log_info "Téléchargement WaveTerm v${WAVETERM_VER} (~153 Mo)..."
  if curl -fL --connect-timeout 30 -o "${WAVETERM_DEB}" "${WAVETERM_URL}" 2>>"${LOG_FILE}"; then
    apt install -y "${WAVETERM_DEB}" 2>>"${LOG_FILE}" \
      && log_ok "WaveTerm v${WAVETERM_VER} installé" \
      || log_error "WaveTerm dpkg échoué"
    rm -f "${WAVETERM_DEB}"
  else
    log_error "WaveTerm download échoué — installer depuis https://www.waveterm.dev/download"
  fi
else
  log_ok "WaveTerm déjà présent ($(waveterm --version 2>/dev/null || echo 'version inconnue'))"
fi

# Déployer les configs WaveTerm (Ollama + settings + connexion SSH homelab)
WAVETERM_CONF="${TARGET_HOME}/.config/waveterm"
if [[ -d "${REPO_DIR}/configs/waveterm" ]]; then
  mkdir -p "${WAVETERM_CONF}"
  cp "${REPO_DIR}/configs/waveterm/"*.json "${WAVETERM_CONF}/" 2>/dev/null || true
  chown -R "${TARGET_USER}:${TARGET_USER}" "${WAVETERM_CONF}"
  log_ok "Config WaveTerm déployée (Ollama 10.11.12.122, theme Dracula, SSH homelab)"
fi

# ── Brave Origin (version minimaliste, gratuite sur Linux) ───────────────────
log_section "Brave Origin"
if ! command -v brave-origin &>/dev/null; then
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  curl -fsSLo /etc/apt/sources.list.d/brave-browser.sources \
    https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
  apt update -q
  if apt install -y brave-origin 2>>"${LOG_FILE}"; then
    log_ok "Brave Origin installé (sans Leo/Rewards/VPN/Wallet — gratuit sur Linux)"
  elif apt install -y brave-browser 2>>"${LOG_FILE}"; then
    log_ok "Brave standard installé (brave-origin absent du repo — fallback)"
  else
    log_error "Brave install (origin + fallback) FAILED"
  fi
else
  log_ok "Brave Origin déjà présent"
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

# ── Distrobox + Podman (équivalent Toolbox/Silverblue) ───────────────────────
log_section "Distrobox + Podman"
apt_install podman distrobox uidmap slirp4netns
log_ok "Distrobox prêt — ex: distrobox create --name fedora --image fedora:latest"

# ── VS Code (repo Microsoft officiel) ─────────────────────────────────────────
log_section "VS Code"
if ! command -v code &>/dev/null; then
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list
  apt update -q && apt install -y code \
    && log_ok "VS Code installé" || log_error "VS Code install"
else
  log_ok "VS Code déjà présent"
fi

# ── Zed (script officiel, install user) ───────────────────────────────────────
log_section "Zed"
if [[ ! -x "${TARGET_HOME}/.local/bin/zed" ]] && ! command -v zed &>/dev/null; then
  as_user "curl -fsSL https://zed.dev/install.sh | sh" \
    && log_ok "Zed installé → ~/.local/bin/zed" \
    || log_error "Zed install"
else
  log_ok "Zed déjà présent"
fi

# ── Claude Code CLI (officiel Anthropic) ──────────────────────────────────────
log_section "Claude Code CLI"
if [[ ! -x "${TARGET_HOME}/.local/bin/claude" ]] && ! command -v claude &>/dev/null; then
  as_user "curl -fsSL https://claude.ai/install.sh | bash" \
    && log_ok "Claude Code installé (officiel)" \
    || log_error "Claude Code install"
else
  log_ok "Claude Code déjà présent"
fi

# ── Claude Desktop (build communautaire aaddrick, repo APT signé) ────────────
log_section "Claude Desktop (communautaire)"
if ! is_installed claude-desktop; then
  # Domaine direct : aaddrick.github.io redirige en HTTP (refusé par apt)
  curl -fsSL https://pkg.claude-desktop-debian.dev/KEY.gpg \
    | gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg
  echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] \
https://pkg.claude-desktop-debian.dev stable main" \
    > /etc/apt/sources.list.d/claude-desktop.list
  apt update -q && apt install -y claude-desktop \
    && log_ok "Claude Desktop installé" \
    || log_error "Claude Desktop install"
else
  log_ok "Claude Desktop déjà présent"
fi

# ── Proton Mail Desktop ───────────────────────────────────────────────────────
log_section "Proton Mail"
if ! is_installed proton-mail; then
  PROTON_DEB="/tmp/ProtonMail-desktop.deb"
  if curl -fL --connect-timeout 15 -o "${PROTON_DEB}" \
      "https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb" 2>>"${LOG_FILE}"; then
    apt install -y "${PROTON_DEB}" \
      && log_ok "Proton Mail installé (⚠ premium requis après 14j)" \
      || log_error "Proton Mail dpkg failed"
    rm -f "${PROTON_DEB}"
  else
    log_error "Proton Mail download failed — installer depuis proton.me/mail/download"
  fi
else
  log_ok "Proton Mail déjà présent"
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
echo "║  1. bash /opt/debiantrixie/scripts/gnome-anduinos.sh        ║"
echo "║     (GNOME style Win11 : taskbar, menu démarrer, tiling)    ║"
echo "║  2. bash /opt/debiantrixie/scripts/niri-setup.sh  (~20 min) ║"
echo "║  3. bash /opt/debiantrixie/scripts/bash-setup.sh  (ble.sh)  ║"
echo "║  3. sudo bash /opt/debiantrixie/scripts/citrix-setup.sh     ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ── Sortie : TOUJOURS 0 ───────────────────────────────────────────────────────
# Le late_command du preseed considère tout code != 0 comme un échec d'install.
# Les erreurs réelles sont déjà loguées (ERROR_COUNT) et consultables dans le log.
exit 0
