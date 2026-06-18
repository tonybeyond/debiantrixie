#!/usr/bin/env bash
# =============================================================================
# citrix-setup.sh — Citrix Workspace App NATIF sur Debian 13 Trixie
# =============================================================================
# Trixie a retiré webkit2gtk-4.0 (libsoup2), requis par Citrix Workspace App.
# Solution : apporter libwebkit2gtk-4.0-37 + ses dépendances depuis Bookworm.
# Ces libs COHABITENT avec celles de Trixie (SONAME distincts : 4.0 vs 4.1,
# libicu72 vs libicu76) — aucun conflit, aucun repo Bookworm permanent ajouté.
#
# Place le .deb Citrix dans ~/Downloads/ (icaclient_*.deb) puis :
#   sudo bash /opt/debiantrixie/scripts/citrix-setup.sh
# =============================================================================

set -uo pipefail   # PAS de -e : best-effort

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log_info()  { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()    { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_warn()  { printf "${YELLOW}  ⚠${NC}  %s\n" "$*"; }
log_error() { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section(){ printf "\n${BOLD}── %s ──${NC}\n" "$*"; }

[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

# Utilisateur réel (pas root) pour trouver ~/Downloads
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -n "${REAL_USER}" && "${REAL_USER}" != "root" ]]; then
  REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
else
  REAL_HOME="/root"
fi

# Miroir Debian (Bookworm) + versions figées des libs webkit 4.0
DEB_MIRROR="http://ftp.debian.org/debian/pool/main"
WEBKIT_VER="2.50.6-1~deb12u1"
ICU_VER="72.1-3+deb12u1"
WORK="/tmp/citrix-webkit40"

# ── 1. Vérifier qu'on est bien sur Trixie ─────────────────────────────────────
log_section "Vérification système"
if ! grep -q "trixie\|13" /etc/debian_version 2>/dev/null && \
   ! grep -qi trixie /etc/os-release 2>/dev/null; then
  log_warn "Ce script cible Debian 13 Trixie. Détecté : $(cat /etc/debian_version 2>/dev/null)"
  printf "  Continuer ? [y/N] "; read -r a </dev/tty; [[ "$a" =~ ^[Yy]$ ]] || exit 0
fi

# Déjà fonctionnel ?
if [[ -e /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37 ]]; then
  log_ok "libwebkit2gtk-4.0 déjà présente"
else
  # ── 2. Télécharger les libs webkit 4.0 + deps depuis Bookworm ──────────────
  log_section "Récupération de webkit2gtk-4.0 (Bookworm)"
  rm -rf "${WORK}"; mkdir -p "${WORK}"; cd "${WORK}"

  # Liste : (sous-chemin pool | nom fichier)
  # webkit 4.0 + javascriptcore 4.0 (même source) + icu72 (data + libs)
  declare -a DEBS=(
    "w/webkit2gtk/libwebkit2gtk-4.0-37_${WEBKIT_VER}_amd64.deb"
    "w/webkit2gtk/libjavascriptcoregtk-4.0-18_${WEBKIT_VER}_amd64.deb"
    "i/icu/libicu72_${ICU_VER}_amd64.deb"
  )

  DL_OK=true
  for sub in "${DEBS[@]}"; do
    fname=$(basename "${sub}")
    log_info "Téléchargement ${fname}..."
    if ! curl -fL --connect-timeout 20 -o "${fname}" "${DEB_MIRROR}/${sub}"; then
      log_error "Échec : ${fname}"
      DL_OK=false
    fi
  done

  if [[ "${DL_OK}" != true ]]; then
    log_error "Téléchargement incomplet. Vérifier la connectivité / les versions."
    exit 1
  fi

  # ── 3. Installer ces .deb (cohabitent avec les libs Trixie) ────────────────
  log_section "Installation des libs Bookworm (cohabitation)"
  # dpkg -i : installe sans toucher aux paquets Trixie existants.
  # Les SONAME diffèrent (4.0 vs 4.1, icu .72 vs .76) → pas de remplacement.
  if dpkg -i "${WORK}"/*.deb 2>/dev/null; then
    log_ok "Libs webkit 4.0 + icu72 installées"
  else
    log_info "Résolution des dépendances manquantes..."
    apt-get install -f -y || log_warn "apt -f a signalé des soucis (souvent bénin ici)"
    dpkg -i "${WORK}"/*.deb 2>/dev/null && log_ok "Libs installées (2e passe)" \
      || log_error "Installation des libs échouée"
  fi

  # Vérification
  if [[ -e /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37 ]]; then
    log_ok "libwebkit2gtk-4.0.so.37 en place"
  else
    log_error "libwebkit2gtk-4.0.so.37 toujours absente — Citrix ne démarrera pas"
  fi
  rm -rf "${WORK}"
fi

# ── 4. Dépendances Citrix classiques (présentes dans Trixie) ─────────────────
log_section "Dépendances Citrix (Trixie)"
apt-get update -q
apt-get install -y \
  libgtk2.0-0 libgtk-3-0t64 libcanberra-gtk-module libcanberra-gtk3-module \
  libcurl4 libxml2 libxslt1.1 libsecret-1-0 libidn12 \
  libxaw7 libxmu6 libxpm4 libxinerama1 libxrandr2 libxtst6 \
  libpng16-16 libfreetype6 libfontconfig1 fontconfig \
  libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
  ca-certificates 2>/dev/null || log_warn "Certaines deps Trixie ont échoué"
log_ok "Dépendances Trixie installées"

# ── 5. Trouver et installer le .deb Citrix ────────────────────────────────────
log_section "Citrix Workspace App"
DEB_PATH=$(find "${REAL_HOME}/Downloads" "${REAL_HOME}" /root/Downloads "$(dirname "$0")" \
  -maxdepth 1 -name "icaclient_*.deb" 2>/dev/null | sort -V | tail -n1)
if [[ -z "${DEB_PATH}" ]]; then
  log_error "icaclient_*.deb introuvable dans ${REAL_HOME}/Downloads/"
  echo "  → https://www.citrix.com/downloads/workspace-app/linux/"
  exit 1
fi
log_ok "Paquet : $(basename "${DEB_PATH}")"

echo "icaclient icaclient/accepteula boolean true" | debconf-set-selections
if dpkg -i "${DEB_PATH}" 2>/dev/null; then
  log_ok "Citrix installé"
else
  apt-get install -f -y && dpkg -i "${DEB_PATH}" 2>/dev/null \
    && log_ok "Citrix installé (2e passe)" \
    || log_error "Installation Citrix échouée"
fi

# ── 6. Store SSL ──────────────────────────────────────────────────────────────
log_section "Certificats SSL"
CERTS="/opt/Citrix/ICAClient/keystore/cacerts"
if [[ -d "${CERTS}" ]]; then
  cp /usr/share/ca-certificates/mozilla/*.crt "${CERTS}/" 2>/dev/null || true
  cp /etc/ssl/certs/*.pem "${CERTS}/" 2>/dev/null || true
  c_rehash "${CERTS}/" 2>/dev/null || /opt/Citrix/ICAClient/util/ctx_rehash 2>/dev/null || true
  log_ok "Certificats liés et réindexés"
fi

# ── 7. Vérification finale (ldd) ──────────────────────────────────────────────
log_section "Vérification"
if [[ -e /opt/Citrix/ICAClient/selfservice ]]; then
  MISSING=$(ldd /opt/Citrix/ICAClient/selfservice 2>/dev/null | grep "not found" || true)
  if [[ -z "${MISSING}" ]]; then
    log_ok "selfservice : toutes les libs résolues"
  else
    log_warn "Libs encore manquantes :"
    echo "${MISSING}" | sed 's/^/      /'
  fi
fi

echo ""
printf "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗\n"
printf "║  Citrix Workspace NATIF sur Trixie ✓                 ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  Lancer : /opt/Citrix/ICAClient/selfservice          ║\n"
printf "║  ou depuis le menu GNOME (Citrix Workspace)          ║\n"
printf "╠══════════════════════════════════════════════════════╣\n"
printf "║  webkit 4.0 (Bookworm) cohabite avec 4.1 (Trixie)    ║\n"
printf "║  Aucun repo Bookworm permanent — libs figées         ║\n"
printf "╚══════════════════════════════════════════════════════╝${NC}\n"
exit 0
