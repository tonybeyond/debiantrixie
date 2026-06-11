# debian-trixie

Configuration Debian 13 Trixie — installation entièrement automatisée via **preseed**.  
Interface : **en_US** · Formats : **fr_CH** · Clavier : **ch/fr** · User : **deby**  
Stack : Brave · Ghostty · Neovim · Zsh · Starship · Hack Nerd Font · Citrix Workspace

---

## Structure

```
debian-trixie/
├── preseed/
│   └── preseed.cfg        # Config d'installation automatique (debian-installer)
├── configs/
│   ├── ghostty/config     # Ghostty : thème Ayu Mirage, splits, Hack Nerd Font
│   └── zshrc              # Zsh : Oh My Zsh + plugins + aliases eza/git
├── scripts/
│   ├── create-iso.sh      # Crée l'ISO preseed (macOS + Linux)
│   ├── post-install.sh    # Setup système (root, pendant installation)
│   ├── bash-setup.sh      # ble.sh — à lancer manuellement post-reboot
│   ├── citrix-setup.sh    # Citrix Workspace App — à lancer manuellement
│   ├── niri-setup.sh      # Niri WM (build Rust ~20 min) — à lancer manuellement
│   ├── refreshos-setup.sh # Setup pour RefreshOS 3 (post-Calamares)
│   ├── edge.sh / outlook.sh / teams.sh / perplexity.sh
│   ├── youtube.sh / textrecon.sh
└── README.md
```

---

## Démarrage rapide

### 1. Préparer le mot de passe

```bash
echo "tonmotdepasse" | openssl passwd -6 -stdin
# → Remplacer la ligne password: dans preseed/preseed.cfg
```

### 2. Créer la clé USB bootable

```bash
git clone https://github.com/tonybeyond/debiantrixie.git
cd debian-trixie
bash scripts/create-iso.sh --usb
```

Le script :
- Détecte macOS ou Linux, installe `xorriso` + `wget` si absent
- Télécharge Debian 13 Trixie netinst (~700 Mo)
- Vérifie le SHA-256 officiel Debian
- Intègre `preseed/preseed.cfg` dans l'ISO
- Patche **GRUB** (UEFI) ET **isolinux** (BIOS) avec les paramètres preseed
- (Optionnel) Écrit l'ISO sur clé USB via `dd`

### 3. Démarrer et installer

Insérer la clé → démarrer (F12/F2/DEL) → l'installation démarre automatiquement.  
⚠ GNOME est téléchargé depuis le miroir Debian CH pendant l'installation (~15-30 min selon la connexion).

---

## Différences clés vs Ubuntu Autoinstall

| Aspect | Ubuntu 24.04 | Debian 13 Trixie |
|--------|-------------|-----------------|
| Format install | `autoinstall.yaml` (cloud-init) | `preseed.cfg` (debian-installer) |
| ISO à télécharger | Desktop (~5.9 Go) | Netinst (~700 Mo) |
| Paquets pendant install | Inclus dans l'ISO | Téléchargés depuis miroir |
| Boot patché | GRUB uniquement | GRUB + **isolinux** (BIOS/UEFI) |
| Durée d'installation | ~15 min | ~20-30 min (dépend du réseau) |

---

## Ce que l'installation installe automatiquement

| Composant | Détail |
|-----------|--------|
| **GNOME** | Bureau complet via `tasksel gnome-desktop` |
| **Locale** | `en_US.UTF-8` interface · `fr_CH.UTF-8` formats |
| **Brave Browser** | Via repo Brave officiel |
| **Ghostty** | Apt natif → mkasberg script → Flatpak (fallback) |
| **Neovim** | Build depuis source (stable) + kickstart.nvim |
| **Oh My Zsh** | Thème bira + autosuggestions/syntax/autocomplete |
| **Starship** | Prompt system-wide (icône Debian ` `) |
| **Hack Nerd Font** | Police terminal avec icônes |
| **Citrix Workspace** | Si `.deb` présent dans `~/Downloads` |
| **Flatpak + Flathub** | Ajouté pour accès aux apps non-repo |

---

## Scripts à lancer après le premier reboot

```bash
# 1. Niri WM (compositeur Wayland, build Rust ~20 min)
bash /opt/debiantrixie/scripts/niri-setup.sh

# 2. ble.sh (autosuggestions bash + syntax highlighting)
bash /opt/debiantrixie/scripts/bash-setup.sh

# 3. Citrix Workspace (après téléchargement du .deb)
#    → https://www.citrix.com/downloads/workspace-app/linux/
sudo bash /opt/debiantrixie/scripts/citrix-setup.sh
```

---

## Locale : en_US + fr_CH

`/etc/default/locale` après installation :

```
LANG=en_US.UTF-8            # Interface GNOME en anglais
LC_TIME=fr_CH.UTF-8         # Dates : 29.05.2026
LC_NUMERIC=fr_CH.UTF-8      # Décimales : 1'234,56
LC_MONETARY=fr_CH.UTF-8     # CHF 12.50
LC_PAPER=fr_CH.UTF-8        # A4
LC_MEASUREMENT=fr_CH.UTF-8  # Métrique
```

Vérifier : `locale`

---

## Niri WM

Keybinds (Brave au lieu de Firefox, clavier ch/fr) :

| Raccourci | Action |
|-----------|--------|
| `Super+Enter` | Ghostty |
| `Super+Space` | Fuzzel |
| `Super+W` | Brave |
| `Super+HJKL` | Navigation Vim |
| `Super+Q` | Fermer |
| `Print` | Screenshot |

---


---

## RefreshOS 3 (variante KDE)

[RefreshOS 3](https://refreshos.org) est basé sur Debian 13 Trixie avec KDE Plasma 6, Brave et codecs préinstallés.

⚠️ **Le preseed ne fonctionne PAS sur RefreshOS** : il s'installe via Calamares (live ISO), pas debian-installer.
Le workflow est donc : installation manuelle Calamares (~6 clics, 10 min), puis script automatisé.

```bash
# Après l'installation RefreshOS via Calamares :
sudo git clone https://github.com/tonybeyond/debiantrixie.git /opt/debiantrixie
sudo bash /opt/debiantrixie/scripts/refreshos-setup.sh
```

### Ce que fait refreshos-setup.sh

| Action | Détail |
|--------|--------|
| **Supprime** | Elisa, Kdenlive, Thunderbird, KWave, KolourPaint |
| **Garde** (inclus RefreshOS) | Brave, VLC, LibreOffice, GIMP, PhotoQt |
| **Distrobox + Podman** | Équivalent Toolbox/Silverblue — conteneurs Fedora/Arch/Ubuntu intégrés |
| **VS Code** | Repo Microsoft officiel |
| **Zed** | Script officiel zed.dev |
| **Claude Code** | CLI officiel Anthropic |
| **Claude Desktop** | Build communautaire [aaddrick](https://github.com/aaddrick/claude-desktop-debian) (repo APT signé) |
| **Proton Mail** | .deb officiel (⚠ premium requis après 14j) |
| **Stack habituelle** | Ghostty, Neovim+kickstart, Zsh+OMZ, Starship, Hack Nerd Font, locale en_US+fr_CH |
| **Citrix** | Si .deb présent dans ~/Downloads |

L'utilisateur est détecté dynamiquement (`$SUDO_USER`) puisque créé via Calamares.

### Distrobox — exemple d'usage

```bash
# Créer un conteneur Fedora intégré au desktop
distrobox create --name fedora --image fedora:latest
distrobox enter fedora

# Les apps GUI du conteneur s'intègrent au desktop hôte
```

## Usage standalone

```bash
git clone https://github.com/tonybeyond/debiantrixie.git /opt/debiantrixie
sudo bash /opt/debiantrixie/scripts/post-install.sh
bash /opt/debiantrixie/scripts/niri-setup.sh
bash /opt/debiantrixie/scripts/bash-setup.sh
sudo bash /opt/debiantrixie/scripts/citrix-setup.sh
```
