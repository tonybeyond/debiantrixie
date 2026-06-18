#!/usr/bin/env bash
# =============================================================================
# citrix-distrobox.sh — Citrix Workspace dans un conteneur Ubuntu 22.04
# =============================================================================
# Debian Trixie ne fournit plus libwebkit2gtk-4.0 (libsoup2), requis par Citrix
# Workspace App. Plutôt que casser Trixie en mélangeant des repos, on isole
# Citrix dans Ubuntu 22.04 (qui a nativement webkit 4.0) via Distrobox.
# L'app s'intègre au menu GNOME de l'hôte (export d'application).
#
# Prérequis : podman + distrobox (installés par post-install.sh)
# À lancer EN UTILISATEUR (pas sudo).
#   bash /opt/debiantrixie/scripts/citrix-distrobox.sh
#
# Place le .deb Citrix dans ~/Downloads/ avant de lancer (icaclient_*.deb).
# =============================================================================

set -uo pipefail   # PAS de -e : best-effort

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}  ⚠${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*"; }

[[ $EUID -ne 0 ]] || { echo "Lancer SANS sudo (en utilisateur)."; exit 1; }

BOX_NAME="citrix"
BOX_IMAGE="docker.io/library/ubuntu:22.04"
DEB_NAME=""

# ── Vérifier distrobox + podman ───────────────────────────────────────────────
log_section "Prérequis"
for cmd in distrobox podman; do
  if command -v "$cmd" &>/dev/null; then
    log_ok "$cmd présent"
  else
    log_error "$cmd manquant — installer : sudo apt install -y podman distrobox"
    exit 1
  fi
done

# ── Trouver le .deb Citrix ────────────────────────────────────────────────────
log_section "Recherche du .deb Citrix"
DEB_PATH=$(find "${HOME}/Downloads" "${HOME}" -maxdepth 1 -name "icaclient_*.deb" 2>/dev/null | sort -V | tail -n1)
if [[ -z "${DEB_PATH}" ]]; then
  log_error "Aucun icaclient_*.deb trouvé dans ~/Downloads/"
  echo "  → Télécharger : https://www.citrix.com/downloads/workspace-app/linux/"
  echo "  → Placer dans ~/Downloads/ puis relancer"
  exit 1
fi
DEB_NAME=$(basename "${DEB_PATH}")
log_ok "Trouvé : ${DEB_NAME}"

# ── Créer le conteneur Ubuntu 22.04 ───────────────────────────────────────────
log_section "Conteneur Distrobox '${BOX_NAME}' (Ubuntu 22.04)"
if distrobox list 2>/dev/null | grep -q "${BOX_NAME}"; then
  log_ok "Conteneur '${BOX_NAME}' existe déjà"
else
  log_info "Création (téléchargement de l'image Ubuntu 22.04, ~1-2 min)..."
  distrobox create --name "${BOX_NAME}" --image "${BOX_IMAGE}" --yes \
    && log_ok "Conteneur créé" \
    || { log_error "Création échouée"; exit 1; }
fi

# ── Installer Citrix DANS le conteneur ────────────────────────────────────────
log_section "Installation de Citrix dans le conteneur"
# Copier le .deb dans un endroit accessible par le conteneur (~/ est monté)
CONTAINER_DEB="${HOME}/.cache/${DEB_NAME}"
mkdir -p "${HOME}/.cache"
cp "${DEB_PATH}" "${CONTAINER_DEB}"

# Script d'install exécuté dans le conteneur
distrobox enter "${BOX_NAME}" -- bash -c "
  set -e
  export DEBIAN_FRONTEND=noninteractive
  echo '→ apt update dans le conteneur...'
  sudo apt-get update -q

  echo '→ Génération des locales (fix: Locale not supported by C library)...'
  sudo apt-get install -y locales
  sudo locale-gen en_US.UTF-8 fr_CH.UTF-8 || true
  sudo update-locale LANG=en_US.UTF-8 || true

  echo '→ Pré-acceptation EULA (debconf)...'
  echo 'icaclient icaclient/accepteula boolean true' | sudo debconf-set-selections

  echo '→ Installation des dépendances complètes...'
  # UIDialogLib3.so (dialogue EULA/UI) requiert TOUTE la pile GTK + deps runtime.
  # L'erreur E_DYNLOAD_FAILED venait de libs absentes de l'image Ubuntu vanilla.
  sudo apt-get install -y \
    libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18 \
    libgtk2.0-0 libgtk-3-0 libglib2.0-0 libgdk-pixbuf-2.0-0 \
    libcanberra-gtk-module libcanberra-gtk3-module \
    libcurl4 libxml2 libxslt1.1 libsecret-1-0 libidn12 \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
    libxaw7 libxmu6 libxpm4 libxinerama1 libxrandr2 libxtst6 \
    libpng16-16 libjpeg-turbo8 libfreetype6 libfontconfig1 \
    libasound2 libspeexdsp1 libsm6 libice6 \
    fontconfig fonts-liberation \
    ca-certificates || sudo apt-get install -f -y

  echo '→ Installation du paquet Citrix...'
  sudo apt-get install -y '${CONTAINER_DEB}' || sudo apt-get install -f -y

  echo '→ Pré-acceptation EULA (fichier .eula — la clé pour éviter EULA rejected)...'
  # En plus de debconf : créer le marqueur d'acceptation que selfservice vérifie
  CONFIG_DIR="\$HOME/.ICAClient"
  mkdir -p "\$CONFIG_DIR"
  # Récupérer la version EULA et marquer comme acceptée
  if [ -f /opt/Citrix/ICAClient/eula.txt ]; then
    sudo touch /opt/Citrix/ICAClient/.eula_accepted 2>/dev/null || true
  fi
  # wfica.ini : forcer EULA accepted
  if [ -f /opt/Citrix/ICAClient/config/wfclient.template ]; then
    cp /opt/Citrix/ICAClient/config/wfclient.template "\$CONFIG_DIR/wfclient.ini" 2>/dev/null || true
  fi

  echo '→ Liaison des certificats SSL...'
  if [ -d /opt/Citrix/ICAClient/keystore/cacerts ]; then
    sudo cp /usr/share/ca-certificates/mozilla/*.crt /opt/Citrix/ICAClient/keystore/cacerts/ 2>/dev/null || true
    sudo cp /etc/ssl/certs/*.pem /opt/Citrix/ICAClient/keystore/cacerts/ 2>/dev/null || true
    sudo c_rehash /opt/Citrix/ICAClient/keystore/cacerts/ 2>/dev/null || true
  fi

  echo '✓ Citrix installé dans le conteneur'
" && log_ok "Citrix installé dans '${BOX_NAME}'" || log_error "Installation Citrix dans conteneur échouée"

rm -f "${CONTAINER_DEB}"

# ── Exporter l'application vers le menu GNOME de l'hôte ───────────────────────
log_section "Export vers le menu GNOME de l'hôte"
distrobox enter "${BOX_NAME}" -- bash -c "
  # Self-Service (interface principale)
  distrobox-export --app /opt/Citrix/ICAClient/selfservice 2>/dev/null || true
  # Associer aussi le moteur wfica pour les fichiers .ica
  distrobox-export --bin /opt/Citrix/ICAClient/util/storebrowse \
    --export-path \$HOME/.local/bin 2>/dev/null || true
" && log_ok "Citrix exporté → cherche 'Citrix' dans le menu GNOME" \
  || log_warn "Export échoué — lancer manuellement : distrobox enter ${BOX_NAME} -- /opt/Citrix/ICAClient/selfservice"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗\n"
printf "║  Citrix Workspace (Distrobox Ubuntu 22.04) ✓         ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  • Cherche 'Citrix' dans le menu GNOME               ║\n"
printf "║  • Ou en CLI :                                       ║\n"
printf "║    distrobox enter ${BOX_NAME} -- \\                       ║\n"
printf "║      /opt/Citrix/ICAClient/selfservice               ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  Ouvrir un .ica directement :                        ║\n"
printf "║    distrobox enter ${BOX_NAME} -- \\                       ║\n"
printf "║      /opt/Citrix/ICAClient/wfica fichier.ica         ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  Gérer le conteneur :                                ║\n"
printf "║    distrobox list                                    ║\n"
printf "║    distrobox stop ${BOX_NAME}                            ║\n"
printf "║    distrobox rm ${BOX_NAME}    (supprimer)               ║\n"
printf "╚══════════════════════════════════════════════════════╝${NC}\n"
