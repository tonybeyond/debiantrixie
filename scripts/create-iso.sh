#!/usr/bin/env bash
# =============================================================================
# create-iso.sh — Crée un ISO Debian 13 Trixie avec preseed intégré
# Compatible : macOS (Intel/Apple Silicon) + Linux (x86_64)
#
# Usage :
#   bash scripts/create-iso.sh              # Crée l'ISO uniquement
#   bash scripts/create-iso.sh --usb        # Crée l'ISO + écrit sur USB
#   bash scripts/create-iso.sh --help
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DEBIAN_BASE_URL="https://cdimage.debian.org/cdimage/release/current/amd64/iso-cd"
SHA256_URL="${DEBIAN_BASE_URL}/SHA256SUMS"
OUTPUT_ISO="debian-trixie-preseed.iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
WORK_DIR="/tmp/debian-preseed-work"
WRITE_USB=false

WGET="wget --timeout=30 --tries=2 --dns-timeout=10 --connect-timeout=15"

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}  ⚠${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*"; }
die()         { log_error "$*"; exit 1; }

usage() {
  cat << EOF
${BOLD}create-iso.sh${NC} — ISO Debian 13 Trixie preseed

Usage:
  bash scripts/create-iso.sh [OPTIONS]

Options:
  --usb       Écrire l'ISO sur clé USB après création
  --help      Afficher cette aide

Ce script :
  1. Détecte macOS ou Linux et installe les outils requis
  2. Télécharge Debian 13 Trixie netinst (~700 Mo)
  3. Vérifie le SHA-256 officiel Debian
  4. Intègre preseed/preseed.cfg dans l'ISO
  5. Patche GRUB (UEFI) + isolinux (BIOS) pour démarrer en preseed
  6. (Optionnel) Écrit l'ISO sur clé USB

⚠  Remplacer le hash de mot de passe dans preseed/preseed.cfg avant usage !

EOF
  exit 0
}

[[ "${1:-}" == "--help" ]] && usage
[[ "${1:-}" == "--usb"  ]] && WRITE_USB=true

# ── Détecter l'OS ─────────────────────────────────────────────────────────────
log_section "Détection de l'environnement"
OS_TYPE=""
if [[ "$(uname)" == "Darwin" ]]; then
  OS_TYPE="macos"; ARCH=$(uname -m)
  log_ok "macOS détecté (${ARCH})"
elif [[ "$(uname)" == "Linux" ]]; then
  OS_TYPE="linux"
  log_ok "Linux détecté ($(uname -m))"
else
  die "OS non supporté : $(uname)"
fi

# ── Vérifier les fichiers source ──────────────────────────────────────────────
log_section "Vérification fichiers source"
[[ -f "${REPO_DIR}/preseed/preseed.cfg" ]] \
  || die "preseed/preseed.cfg introuvable. Lancer depuis la racine du repo."

if grep -q "PLEASE_REPLACE_WITH_REAL_HASH" "${REPO_DIR}/preseed/preseed.cfg"; then
  log_warn "Le hash du mot de passe n'a pas été remplacé dans preseed/preseed.cfg !"
  log_warn "Générer un hash : echo 'tonpass' | openssl passwd -6 -stdin"
  printf "  Continuer quand même ? [y/N] "
  read -r answer
  [[ "${answer}" =~ ^[Yy]$ ]] || { log_info "Annulé."; exit 0; }
fi
log_ok "preseed.cfg présent"

# ── Dépendances ───────────────────────────────────────────────────────────────
log_section "Dépendances"
install_deps_macos() {
  if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [[ "${ARCH}" == "arm64" ]] \
      && eval "$(/opt/homebrew/bin/brew shellenv)" \
      || eval "$(/usr/local/bin/brew shellenv)"
  else
    log_ok "Homebrew présent"
  fi
  for tool in xorriso wget; do
    command -v "${tool}" &>/dev/null || brew install "${tool}"
    log_ok "${tool} présent"
  done
}
install_deps_linux() {
  local missing=()
  command -v xorriso &>/dev/null || missing+=("xorriso")
  command -v wget    &>/dev/null || missing+=("wget")
  if [[ ${#missing[@]} -gt 0 ]]; then
    if   command -v apt-get &>/dev/null; then sudo apt-get install -y "${missing[@]}"
    elif command -v dnf     &>/dev/null; then sudo dnf install -y "${missing[@]}"
    elif command -v pacman  &>/dev/null; then sudo pacman -S --noconfirm "${missing[@]}"
    else die "Installer manuellement : ${missing[*]}"
    fi
  fi
  log_ok "Dépendances OK"
}
[[ "${OS_TYPE}" == "macos" ]] && install_deps_macos || install_deps_linux

# ── Détecter et télécharger l'ISO Debian ─────────────────────────────────────
log_section "ISO Debian 13 Trixie"

# Détecter dynamiquement le dernier netinst (debian-13.x.x-amd64-netinst.iso)
log_info "Détection de la dernière version disponible..."
DEBIAN_ISO=$(${WGET} -qO- "${DEBIAN_BASE_URL}/" 2>/dev/null \
  | grep -oE 'debian-13\.[0-9]+\.[0-9]+-amd64-netinst\.iso' \
  | sort -V | tail -1 \
  || echo "debian-13.5.0-amd64-netinst.iso")
DEBIAN_URL="${DEBIAN_BASE_URL}/${DEBIAN_ISO}"
log_ok "Version cible : ${DEBIAN_ISO}"

ISO_PATH="${HOME}/Downloads/${DEBIAN_ISO}"

# Chercher un ISO debian existant
EXISTING_ISO=""
if [[ -f "${ISO_PATH}" ]]; then
  EXISTING_ISO="${ISO_PATH}"
else
  EXISTING_ISO=$(find "${HOME}/Downloads" -maxdepth 1 \
    -name "debian-13.*-amd64-netinst.iso" 2>/dev/null | sort -V | tail -1 || true)
fi

if [[ -n "${EXISTING_ISO}" && "${EXISTING_ISO}" != "${ISO_PATH}" ]]; then
  log_warn "ISO existant : $(basename "${EXISTING_ISO}")"
  printf "  Utiliser cet ISO ? [Y/n] "
  read -r use_existing
  if [[ ! "${use_existing}" =~ ^[Nn]$ ]]; then
    ISO_PATH="${EXISTING_ISO}"
    DEBIAN_ISO=$(basename "${ISO_PATH}")
    log_ok "Utilisation de : ${DEBIAN_ISO}"
  fi
fi

if [[ ! -f "${ISO_PATH}" ]]; then
  log_info "Téléchargement ${DEBIAN_ISO} (~700 Mo)..."
  mkdir -p "${HOME}/Downloads"
  ${WGET} --progress=bar:force -O "${ISO_PATH}.part" "${DEBIAN_URL}" \
    && mv "${ISO_PATH}.part" "${ISO_PATH}" \
    || die "Téléchargement échoué"
  log_ok "ISO téléchargé"
else
  log_ok "ISO présent : ${ISO_PATH}"
fi

# ── Vérification SHA-256 ──────────────────────────────────────────────────────
log_section "Vérification checksum"
SHA256_FILE="/tmp/debian-sha256sums"
log_info "Récupération SHA256SUMS Debian..."
${WGET} -q -O "${SHA256_FILE}" "${SHA256_URL}" \
  || die "Impossible de récupérer SHA256SUMS"

EXPECTED_SHA=$(grep " ${DEBIAN_ISO}$" "${SHA256_FILE}" | awk '{print $1}' || true)
[[ -n "${EXPECTED_SHA}" ]] || die "Checksum pour ${DEBIAN_ISO} introuvable"

log_info "Calcul SHA-256..."
if [[ "${OS_TYPE}" == "macos" ]]; then
  ACTUAL_SHA=$(shasum -a 256 "${ISO_PATH}" | awk '{print $1}')
else
  ACTUAL_SHA=$(sha256sum "${ISO_PATH}" | awk '{print $1}')
fi

if [[ "${ACTUAL_SHA}" == "${EXPECTED_SHA}" ]]; then
  log_ok "Checksum OK : ${EXPECTED_SHA:0:20}..."
else
  log_error "Checksum INCORRECT — ISO corrompu"
  die "Supprimer ${ISO_PATH} et relancer."
fi

# ── Préparer workspace ────────────────────────────────────────────────────────
log_section "Préparation workspace"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# Extraire les configs de boot de l'ISO
extract_from_iso() {
  local iso_path="$1" iso_file="$2" local_dest="$3"
  xorriso -osirrox on -indev "${iso_path}" -extract "${iso_file}" "${local_dest}" > /dev/null 2>&1
}

log_info "Extraction des configs de boot..."

# GRUB (UEFI)
extract_from_iso "${ISO_PATH}" /boot/grub/grub.cfg "${WORK_DIR}/grub.cfg" \
  && log_ok "grub.cfg extrait" \
  || log_warn "grub.cfg non trouvé (UEFI boot peut ne pas fonctionner)"

# Isolinux (BIOS) — txt.cfg = mode texte, gtk.cfg = mode graphique
for cfg_file in txt.cfg gtk.cfg isolinux.cfg adgtk.cfg; do
  if extract_from_iso "${ISO_PATH}" "/isolinux/${cfg_file}" "${WORK_DIR}/${cfg_file}" 2>/dev/null; then
    log_ok "isolinux/${cfg_file} extrait"
  fi
done

# ── Patcher GRUB (UEFI) ───────────────────────────────────────────────────────
log_section "Patch GRUB (UEFI)"
PRESEED_PARAMS='auto=true priority=critical preseed/file=/cdrom/preseed.cfg'

if [[ -f "${WORK_DIR}/grub.cfg" ]]; then
  awk -v params="${PRESEED_PARAMS}" '
    /set timeout=/ { sub(/set timeout=[0-9]*/, "set timeout=5") }
    /\/install\.amd\/vmlinuz/ && !/preseed/ {
      sub(/\/install\.amd\/vmlinuz/, "/install.amd/vmlinuz " params)
    }
    { print }
  ' "${WORK_DIR}/grub.cfg" > "${WORK_DIR}/grub_patched.cfg"
  grep -q "preseed" "${WORK_DIR}/grub_patched.cfg" \
    && log_ok "GRUB patché" \
    || log_warn "Pattern vmlinuz non trouvé dans grub.cfg"
fi

# ── Patcher isolinux (BIOS) ───────────────────────────────────────────────────
log_section "Patch isolinux (BIOS)"

patch_isolinux_cfg() {
  local src="$1" dst="$2"
  awk -v params="${PRESEED_PARAMS}" '
    /^TIMEOUT/ { sub(/^TIMEOUT [0-9]*/, "TIMEOUT 50") }
    /^timeout/ { sub(/^timeout [0-9]*/, "timeout 5") }
    /append/ && !/preseed/ {
      sub(/append /, "append " params " ")
    }
    { print }
  ' "${src}" > "${dst}"
}

for cfg_file in txt.cfg gtk.cfg adgtk.cfg isolinux.cfg; do
  if [[ -f "${WORK_DIR}/${cfg_file}" ]]; then
    patch_isolinux_cfg "${WORK_DIR}/${cfg_file}" "${WORK_DIR}/${cfg_file}_patched"
    grep -q "preseed" "${WORK_DIR}/${cfg_file}_patched" \
      && log_ok "isolinux/${cfg_file} patché" \
      || log_warn "${cfg_file} : pattern append non trouvé"
  fi
done

# ── Construire l'ISO preseed ──────────────────────────────────────────────────
log_section "Construction de l'ISO preseed"
OUTPUT_PATH="${HOME}/Downloads/${OUTPUT_ISO}"
rm -f "${OUTPUT_PATH}"

# Préparer les fichiers à injecter
INJECT_DIR="${WORK_DIR}/inject"
mkdir -p "${INJECT_DIR}"
cp "${REPO_DIR}/preseed/preseed.cfg" "${INJECT_DIR}/preseed.cfg"

log_info "Création de l'ISO (2-5 min)..."

# Construire la commande xorriso avec les fichiers patchés disponibles
XORRISO_MAPS=(
  "-map ${INJECT_DIR}/preseed.cfg /preseed.cfg"
)
[[ -f "${WORK_DIR}/grub_patched.cfg" ]] \
  && XORRISO_MAPS+=("-map ${WORK_DIR}/grub_patched.cfg /boot/grub/grub.cfg")
for cfg_file in txt.cfg gtk.cfg adgtk.cfg isolinux.cfg; do
  [[ -f "${WORK_DIR}/${cfg_file}_patched" ]] \
    && XORRISO_MAPS+=("-map ${WORK_DIR}/${cfg_file}_patched /isolinux/${cfg_file}")
done

# shellcheck disable=SC2068
xorriso \
  -indev  "${ISO_PATH}" \
  -outdev "${OUTPUT_PATH}" \
  -overwrite on \
  ${XORRISO_MAPS[@]} \
  -boot_image any replay \
  2>&1 | grep -Ev "^(xorriso|$)" | tail -8 \
  && log_ok "ISO construit" \
  || die "Construction ISO échouée"

rm -rf "${WORK_DIR}"

ISO_SIZE=$(du -sh "${OUTPUT_PATH}" | cut -f1)
printf "\n${GREEN}${BOLD}  ✓ ISO preseed prêt !${NC}\n\n"
echo "  Fichier : ${OUTPUT_PATH}"
echo "  Taille  : ${ISO_SIZE}"
echo "  Contenu : preseed.cfg · GRUB + isolinux patchés"
echo ""

# ── Sans --usb : instructions manuelles ──────────────────────────────────────
if [[ "${WRITE_USB}" == false ]]; then
  echo "  Écriture USB :"
  if [[ "${OS_TYPE}" == "macos" ]]; then
    echo "    diskutil list"
    echo "    diskutil unmountDisk /dev/diskN"
    echo "    sudo dd if=\"${OUTPUT_PATH}\" of=/dev/rdiskN bs=1m"
    echo "    diskutil eject /dev/diskN"
  else
    echo "    lsblk"
    echo "    sudo dd if=\"${OUTPUT_PATH}\" of=/dev/sdX bs=4M status=progress oflag=sync"
  fi
  echo "  Ou : bash scripts/create-iso.sh --usb"
  exit 0
fi

# ── Mode --usb ────────────────────────────────────────────────────────────────
log_section "Écriture sur clé USB"
log_warn "⚠  Cette opération EFFACE le contenu de la clé USB !"
echo ""
if [[ "${OS_TYPE}" == "macos" ]]; then
  diskutil list external physical 2>/dev/null | grep -E "^/dev|GB|MB" | sed 's/^/    /' || true
  printf "\n  Numéro de disque (ex: 2 pour /dev/disk2) : "
  read -r DISK_NUM
  USB_DEVICE="/dev/disk${DISK_NUM}"
  USB_RAW="/dev/rdisk${DISK_NUM}"
else
  lsblk -d -p -o NAME,SIZE,TYPE,TRAN 2>/dev/null | sed 's/^/    /' || true
  printf "\n  Chemin clé USB (ex: /dev/sdb) : "
  read -r USB_DEVICE
  USB_RAW="${USB_DEVICE}"
fi

echo ""
log_warn "CIBLE  : ${USB_DEVICE}"
log_warn "SOURCE : ${OUTPUT_PATH}"
printf "${RED}${BOLD}\n  CONFIRMER ? [oui/NON] : ${NC}"
read -r confirm
[[ "${confirm}" == "oui" ]] || { log_info "Annulé."; exit 0; }

if [[ "${OS_TYPE}" == "macos" ]]; then
  diskutil unmountDisk "${USB_DEVICE}"
  sudo dd if="${OUTPUT_PATH}" of="${USB_RAW}" bs=1m
  sync; diskutil eject "${USB_DEVICE}"
else
  sudo dd if="${OUTPUT_PATH}" of="${USB_RAW}" bs=4M status=progress oflag=sync; sync
fi

printf "\n${GREEN}${BOLD}  ✓ Clé USB prête.${NC}\n\n"
echo "  Démarrer depuis la clé (F12/F2/DEL) → preseed démarre automatiquement"
echo "  GNOME sera téléchargé depuis le miroir Debian CH (~15-30 min)"
