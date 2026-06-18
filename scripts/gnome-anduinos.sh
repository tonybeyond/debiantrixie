#!/usr/bin/env bash
# =============================================================================
# gnome-anduinos.sh — GNOME façon AnduinOS / Windows 11 sur Debian 13 Trixie
# =============================================================================
# Reproduit l'expérience desktop d'AnduinOS (anduinos.com) sur GNOME 48 :
#   • Dash to Panel  → taskbar en bas, icônes centrées
#   • Arc Menu       → menu démarrer style Windows 11 (layout "Eleven")
#   • Tiling Shell   → gestion de fenêtres type FancyZones
#   • Blur My Shell  → transparence/flou
#   • Just Perfection → ajustements fins du shell
#   • Emoji Copy     → panneau emoji
#
# À lancer EN UTILISATEUR (pas sudo) depuis une session GNOME.
#   bash /opt/debiantrixie/scripts/gnome-anduinos.sh
#
# Cible : GNOME Shell 48 (Debian Trixie). Les extensions sont téléchargées
# depuis extensions.gnome.org en ciblant la version shell détectée.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}  ⚠${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*"; }

[[ $EUID -ne 0 ]] || { echo "Lancer SANS sudo (en utilisateur, dans une session GNOME)."; exit 1; }

# ── Vérifier qu'on est bien sous GNOME ────────────────────────────────────────
if ! command -v gnome-shell &>/dev/null; then
  log_error "gnome-shell introuvable. Ce script cible GNOME (Debian GNOME / RefreshOS-like)."
  exit 1
fi

SHELL_VERSION=$(gnome-shell --version | grep -oE '[0-9]+' | head -n1)
log_info "GNOME Shell détecté : version ${SHELL_VERSION}"

# ── 1. Dépendances ────────────────────────────────────────────────────────────
log_section "Dépendances"
sudo apt update
# gnome-shell-extensions : extensions officielles + outils
# gir1.2-gmenu-3.0 : dépendance Arc Menu (sinon le menu n'apparaît pas)
# gnome-menus : idem
# pipx : pour gnome-extensions-cli (installe les extensions tierces proprement)
for pkg in gnome-shell-extensions gnome-shell-extension-manager \
           gir1.2-gmenu-3.0 gnome-menus gnome-tweaks \
           dconf-cli pipx jq curl wget; do
  if dpkg -s "$pkg" &>/dev/null; then
    log_ok "présent : $pkg"
  elif sudo apt install -y "$pkg" &>/dev/null; then
    log_ok "installé : $pkg"
  else
    log_warn "indisponible : $pkg"
  fi
done

# ── 2. gnome-extensions-cli (gext) via pipx ──────────────────────────────────
log_section "gnome-extensions-cli"
export PATH="${HOME}/.local/bin:${PATH}"
if ! command -v gext &>/dev/null; then
  pipx install gnome-extensions-cli --system-site-packages 2>/dev/null \
    && log_ok "gext installé" \
    || log_warn "gext install échoué — fallback sur installation manuelle"
  pipx ensurepath 2>/dev/null || true
else
  log_ok "gext déjà présent"
fi

# ── 3. Installation des extensions ────────────────────────────────────────────
log_section "Extensions GNOME (style AnduinOS)"

# UUIDs des extensions (extensions.gnome.org)
declare -A EXTENSIONS=(
  ["dash-to-panel@jderose9.github.com"]="Dash to Panel (taskbar)"
  ["arcmenu@arcmenu.com"]="Arc Menu (menu démarrer)"
  ["tilingshell@ferrarodomenico.com"]="Tiling Shell (FancyZones)"
  ["blur-my-shell@aunetx"]="Blur My Shell"
  ["just-perfection-desktop@just-perfection"]="Just Perfection"
  ["emoji-copy@felipeftn"]="Emoji Copy"
)

install_extension() {
  local uuid="$1" name="$2"

  # Déjà installée ?
  if gnome-extensions list 2>/dev/null | grep -q "^${uuid}$"; then
    log_ok "déjà installée : ${name}"
    return 0
  fi

  # Méthode 1 : gext (gnome-extensions-cli) — gère la version shell auto
  if command -v gext &>/dev/null; then
    if gext install "${uuid}" 2>/dev/null; then
      log_ok "installée (gext) : ${name}"
      return 0
    fi
  fi

  # Méthode 2 : téléchargement direct depuis extensions.gnome.org
  local info_url="https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${SHELL_VERSION}"
  local dl_path
  dl_path=$(curl -s "${info_url}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('download_url',''))" 2>/dev/null || echo "")

  if [[ -n "${dl_path}" ]]; then
    local tmp_zip="/tmp/${uuid}.zip"
    if curl -sL "https://extensions.gnome.org${dl_path}" -o "${tmp_zip}"; then
      gnome-extensions install --force "${tmp_zip}" 2>/dev/null \
        && log_ok "installée (manuel) : ${name}" \
        || log_warn "échec install : ${name}"
      rm -f "${tmp_zip}"
      return 0
    fi
  fi

  log_warn "indisponible pour GNOME ${SHELL_VERSION} : ${name}"
  return 1
}

for uuid in "${!EXTENSIONS[@]}"; do
  install_extension "${uuid}" "${EXTENSIONS[$uuid]}"
done

# ── 4. Activer les extensions ─────────────────────────────────────────────────
log_section "Activation"
# Note : nécessite parfois un relogin pour que gnome-shell les charge.
for uuid in "${!EXTENSIONS[@]}"; do
  gnome-extensions enable "${uuid}" 2>/dev/null \
    && log_ok "activée : ${uuid}" \
    || log_warn "activation différée (relogin requis) : ${uuid}"
done

# ── 5. Configuration Dash to Panel (taskbar bas, style Win11) ────────────────
log_section "Configuration Dash to Panel"
D2P="/org/gnome/shell/extensions/dash-to-panel"

# Position en bas sur l'écran principal
dconf write ${D2P}/panel-positions '"{\"0\":\"BOTTOM\"}"' 2>/dev/null || true
dconf write ${D2P}/panel-sizes '"{\"0\":48}"' 2>/dev/null || true
# Icônes applications centrées (style Win11)
dconf write ${D2P}/panel-element-positions \
  '"{\"0\":[{\"element\":\"showAppsButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"activitiesButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"leftBox\",\"visible\":true,\"position\":\"stackedTL\"},{\"element\":\"taskbar\",\"visible\":true,\"position\":\"centerMonitor\"},{\"element\":\"centerBox\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"rightBox\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"dateMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"systemMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"desktopButton\",\"visible\":true,\"position\":\"stackedBR\"}]}"' 2>/dev/null || true
# Comportement clic : cycle entre les fenêtres
dconf write ${D2P}/click-action "'CYCLE'" 2>/dev/null || true
dconf write ${D2P}/show-window-previews true 2>/dev/null || true
dconf write ${D2P}/group-apps true 2>/dev/null || true
dconf write ${D2P}/isolate-workspaces false 2>/dev/null || true
log_ok "Dash to Panel : barre en bas, hauteur 48px, apps centrées"

# ── 6. Configuration Arc Menu (layout Windows 11 "Eleven") ───────────────────
log_section "Configuration Arc Menu"
ARC="/org/gnome/shell/extensions/arcmenu"
dconf write ${ARC}/menu-layout "'Eleven'" 2>/dev/null || true
dconf write ${ARC}/position-in-panel "'Left'" 2>/dev/null || true
dconf write ${ARC}/menu-button-icon "'Distro_Icon'" 2>/dev/null || true
dconf write ${ARC}/distro-icon 21 2>/dev/null || true   # icône Debian si dispo
dconf write ${ARC}/multi-monitor false 2>/dev/null || true
log_ok "Arc Menu : layout 'Eleven' (Windows 11), aligné à gauche"

# ── 7. Just Perfection (ajustements façon Win11) ─────────────────────────────
log_section "Just Perfection"
JP="/org/gnome/shell/extensions/just-perfection"
# Désactiver le hot corner (Activities), comme AnduinOS
dconf write ${JP}/activities-button false 2>/dev/null || true
dconf write ${JP}/clock-menu-position 1 2>/dev/null || true  # horloge à droite
log_ok "Just Perfection : Activities masqué, horloge à droite"

# ── 8. Locale régionale + clavier fr_CH (niveau session GNOME) ───────────────
# GNOME/Wayland N'UTILISE PAS /etc/default/locale ni /etc/default/keyboard pour
# la session graphique — il lit ses propres clés dconf par utilisateur.
# D'où : bonne langue (en_US) mais formats/clavier ignorés sans ces réglages.
log_section "Locale régionale + clavier GNOME"

# Format régional fr_CH (dates, monnaie, mesures) — interface reste en_US
gsettings set org.gnome.system.locale region 'fr_CH.UTF-8' 2>/dev/null || true

# Clavier suisse romand (ch + variante fr) pour la session GNOME
# Format : [('xkb', 'LAYOUT+VARIANT')]
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'ch+fr')]" 2>/dev/null || true
gsettings set org.gnome.desktop.input-sources xkb-options "[]" 2>/dev/null || true

# Cohérence : aligner aussi le niveau système (console TTY + X11) si root dispo
if command -v localectl &>/dev/null; then
  sudo localectl set-x11-keymap ch pc105 fr 2>/dev/null || true
  sudo localectl set-keymap ch-fr 2>/dev/null || true
fi

log_ok "Format régional fr_CH + clavier ch/fr appliqués (session GNOME)"
log_warn "Relogin requis pour que le clavier GNOME prenne effet"

# ── 8. Réglages GNOME globaux (cohérence Win11) ──────────────────────────────
log_section "Réglages GNOME"
# Boutons de titre min/max/close (comme Windows)
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' 2>/dev/null || true
# Thème sombre par défaut (AnduinOS est sombre)
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
# Clic-clic pour minimiser depuis la taskbar
gsettings set org.gnome.shell.app-switcher current-workspace-only true 2>/dev/null || true
# Police (si Hack Nerd Font installée par post-install)
gsettings set org.gnome.desktop.interface monospace-font-name 'Hack Nerd Font Mono 11' 2>/dev/null || true
log_ok "Boutons fenêtre Win-style, thème sombre, raccourcis"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗\n"
printf "║  GNOME façon AnduinOS — configuré ✓                  ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  ⚠  RELOGIN REQUIS (extensions + clavier fr_CH) :    ║\n"
printf "║     déconnexion/reconnexion (ou reboot)              ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  Installé :                                          ║\n"
printf "║  • Dash to Panel  → taskbar en bas, apps centrées    ║\n"
printf "║  • Arc Menu       → menu démarrer Windows 11         ║\n"
printf "║  • Tiling Shell   → zones de fenêtres (FancyZones)   ║\n"
printf "║  • Blur My Shell · Just Perfection · Emoji Copy      ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  Ajustements fins : Extension Manager (déjà installé)║\n"
printf "║  Si Arc Menu n'apparaît pas : vérifier gir1.2-gmenu  ║\n"
printf "╚══════════════════════════════════════════════════════╝${NC}\n"
