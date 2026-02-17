#!/usr/bin/env bash
# =============================================================================
# DE-SYSTEM-SETUP  –  Deutsche Sprache, Zeitzone, Tastatur + nano/mc
#
# Kompatibel mit:
#   Debian  11 (Bullseye) · 12 (Bookworm) · 13 (Trixie)
#   Ubuntu  20.04 · 22.04 · 24.04 · 25.04 · 25.10
#   Derivate (Proxmox VE, Raspberry Pi OS, Pop!_OS, …)
#
# Aufruf:
#   sudo bash de_system_setup.sh
#   KEEP_OPEN=1 sudo -E bash de_system_setup.sh
# =============================================================================
set -euo pipefail

# ── Farben ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Root-Check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "Bitte als root oder mit 'sudo -E bash $0' ausfuehren."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export UCF_FORCE_CONFFNEW=1
export TZ=Europe/Berlin

# =============================================================================
section "SYSTEM ERKENNUNG"
# =============================================================================

DISTRO_ID=""; DISTRO_VERSION_ID=""; DISTRO_CODENAME=""
IS_SYSTEMD=0; SYSTEMD_VERSION=0

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_VERSION_ID="${VERSION_ID:-0}"
    DISTRO_CODENAME="${VERSION_CODENAME:-unknown}"
fi

DEBIAN_MAJOR=0
[[ "$DISTRO_ID" == "debian" ]] && DEBIAN_MAJOR="${DISTRO_VERSION_ID%%.*}"

UBUNTU_VERSION_NUM=0
[[ "$DISTRO_ID" == "ubuntu" ]] && \
    UBUNTU_VERSION_NUM=$(echo "$DISTRO_VERSION_ID" | tr -d '.' 2>/dev/null || echo 0)

if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    IS_SYSTEMD=1
    SYSTEMD_VERSION=$(systemctl --version 2>/dev/null | awk 'NR==1{print $2}' || echo 0)
fi

IS_CONTAINER=0
if [[ -f /.dockerenv ]] || \
   (command -v systemd-detect-virt &>/dev/null && systemd-detect-virt -c &>/dev/null 2>&1); then
    IS_CONTAINER=1
fi

info "Distribution : ${DISTRO_ID} ${DISTRO_VERSION_ID} (${DISTRO_CODENAME})"
info "systemd      : v${SYSTEMD_VERSION} (aktiv: ${IS_SYSTEMD})"
info "Container    : ${IS_CONTAINER}"

USE_LOCALE_CONF=0
if [[ "$DISTRO_ID" == "debian" && "$DEBIAN_MAJOR" -ge 13 ]] || \
   [[ "$DISTRO_ID" == "ubuntu" && "$UBUNTU_VERSION_NUM" -ge 2504 ]] || \
   [[ "$SYSTEMD_VERSION" -ge 253 ]]; then
    USE_LOCALE_CONF=1
    info "Locale-Modus  : /etc/locale.conf (Trixie/25.x+ nativ)"
else
    info "Locale-Modus  : /etc/default/locale (klassisch)"
fi

# =============================================================================
section "1 · PAKETQUELLEN AKTUALISIEREN"
# =============================================================================
apt-get update -qq
ok "apt-get update abgeschlossen"

# =============================================================================
section "2 · PAKETE INSTALLIEREN"
# =============================================================================
PACKAGES=(locales tzdata nano mc ca-certificates)
[[ "$IS_CONTAINER" -eq 0 ]] && PACKAGES+=(keyboard-configuration console-setup kbd)

apt-get install -y --no-install-recommends "${PACKAGES[@]}" \
    -o Dpkg::Options::="--force-confnew" \
    -o Dpkg::Options::="--force-confdef" \
    2>&1 | grep -Ev "^$|^Reading|^Building|^Calculating|^Hit:|^Get:|^Fetched|Unpacking|Selecting" \
    || true
ok "Pakete installiert: ${PACKAGES[*]}"

# =============================================================================
section "3 · ZEITZONE  →  Europe/Berlin"
# =============================================================================
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
[[ "$USE_LOCALE_CONF" -eq 0 ]] && echo "Europe/Berlin" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true
if [[ "$IS_SYSTEMD" -eq 1 ]]; then
    timedatectl set-timezone Europe/Berlin 2>/dev/null \
        && ok "Zeitzone via timedatectl bestaetigt" \
        || warn "timedatectl set-timezone schlug fehl (normal in Containern)"
fi
ok "Zeitzone gesetzt: Europe/Berlin"

# =============================================================================
section "4 · LOCALE GENERIEREN  →  de_DE.UTF-8 + en_US.UTF-8"
# =============================================================================
LOCALE_GEN=/etc/locale.gen

activate_locale() {
    local entry="$1" name="${1%% *}"
    if grep -q "^# *${name} " "$LOCALE_GEN" 2>/dev/null; then
        sed -i "s|^# *\(${name} .*\)|\1|" "$LOCALE_GEN"
        info "${name}: auskommentiert → aktiv"
    elif ! grep -q "^${name} " "$LOCALE_GEN" 2>/dev/null; then
        echo "$entry" >> "$LOCALE_GEN"
        info "${name}: neu eingetragen"
    else
        info "${name}: bereits aktiv"
    fi
}

activate_locale "de_DE.UTF-8 UTF-8"
activate_locale "en_US.UTF-8 UTF-8"
locale-gen
ok "Locales generiert: de_DE.UTF-8, en_US.UTF-8"

LOCALE_CONTENT='LANG=de_DE.UTF-8\nLANGUAGE=de_DE:de\nLC_ALL=de_DE.UTF-8'

if [[ "$USE_LOCALE_CONF" -eq 1 ]]; then
    printf '%s\n' 'LANG=de_DE.UTF-8' 'LANGUAGE=de_DE:de' 'LC_ALL=de_DE.UTF-8' > /etc/locale.conf
    if [[ ! -L /etc/default/locale ]]; then
        [[ -f /etc/default/locale ]] && cp /etc/default/locale /etc/default/locale.bak 2>/dev/null || true
        rm -f /etc/default/locale
        ln -sf /etc/locale.conf /etc/default/locale
        info "Symlink: /etc/default/locale -> /etc/locale.conf angelegt"
    fi
    ok "Locale in /etc/locale.conf (Trixie/25.x+ Methode)"
else
    printf '%s\n' 'LANG=de_DE.UTF-8' 'LANGUAGE=de_DE:de' 'LC_ALL=de_DE.UTF-8' > /etc/default/locale
    update-locale LANG=de_DE.UTF-8 LANGUAGE="de_DE:de" LC_ALL=de_DE.UTF-8 2>/dev/null || true
    ok "Locale in /etc/default/locale (klassische Methode)"
fi

{ export LANG=de_DE.UTF-8; export LANGUAGE=de_DE:de; export LC_ALL=de_DE.UTF-8; } 2>/dev/null || true

# =============================================================================
section "5 · TASTATURBELEGUNG  →  de / PC105"
# =============================================================================
cat > /etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="de"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

if [[ "$IS_CONTAINER" -eq 0 ]]; then
    if command -v debconf-set-selections &>/dev/null; then
        printf '%s\n' \
            "keyboard-configuration keyboard-configuration/layoutcode string de" \
            "keyboard-configuration keyboard-configuration/modelcode string pc105" \
            "keyboard-configuration keyboard-configuration/variantcode string " \
            "keyboard-configuration keyboard-configuration/xkb-keymap select de" \
            | debconf-set-selections 2>/dev/null || true
    fi
    command -v setupcon &>/dev/null && \
        { setupcon -k 2>/dev/null && ok "Tastatur via setupcon aktiviert" || warn "setupcon -k schlug fehl"; }
    command -v udevadm &>/dev/null && \
        udevadm trigger --subsystem-match=input --action=change 2>/dev/null || true
fi
ok "Tastaturbelegung: de (PC105)"

# =============================================================================
section "6 · NANO KONFIGURIEREN"
# =============================================================================
NANORC_SYSTEM=/etc/nanorc

add_nanorc_option() {
    grep -qF "$1" "$NANORC_SYSTEM" 2>/dev/null || echo "$1" >> "$NANORC_SYSTEM"
}

for nanodir in /usr/share/nano /usr/share/nano/extra; do
    if [[ -d "$nanodir" ]]; then
        GLOB_LINE="include \"${nanodir}/*.nanorc\""
        if ! grep -qF "$GLOB_LINE" "$NANORC_SYSTEM" 2>/dev/null && \
           ! grep -qE "^include.*${nanodir}" "$NANORC_SYSTEM" 2>/dev/null; then
            echo "$GLOB_LINE" >> "$NANORC_SYSTEM"
            info "Syntax-Highlighting: ${nanodir}"
        fi
    fi
done

add_nanorc_option "set mouse"
add_nanorc_option "set linenumbers"
add_nanorc_option "set constantshow"
add_nanorc_option "set autoindent"
add_nanorc_option "set tabsize 4"
add_nanorc_option "set tabstospaces"
add_nanorc_option "set trimblanks"
add_nanorc_option "set historylog"
add_nanorc_option "set positionlog"
add_nanorc_option "set softwrap"
add_nanorc_option "set afterends"
ok "nano konfiguriert (/etc/nanorc)"

# =============================================================================
section "7 · EDITOR-STANDARD  →  nano"
# =============================================================================
for var in EDITOR VISUAL; do
    if grep -q "^${var}=" /etc/environment 2>/dev/null; then
        sed -i "s|^${var}=.*|${var}=\"/usr/bin/nano\"|" /etc/environment
    else
        echo "${var}=\"/usr/bin/nano\"" >> /etc/environment
    fi
done
command -v update-alternatives &>/dev/null && \
    { update-alternatives --set editor /usr/bin/nano 2>/dev/null || \
      update-alternatives --install /usr/bin/editor editor /usr/bin/nano 50 2>/dev/null || true; }
ok "Standard-Editor: nano"

# =============================================================================
section "8 · MIDNIGHT COMMANDER (mc)"
# =============================================================================
MC_INI=/etc/mc/mc.ini
if [[ -d /etc/mc ]] && [[ ! -f "$MC_INI" ]]; then
    cat > "$MC_INI" <<'MCINI'
[Midnight-Commander]
skin=darkgreen
use_internal_edit=true
editor_syntax_highlighting=true
editor_line_numbering=true
editor_tab_spacing=4
editor_fill_tabs_with_spaces=true
safe_overwrite=true
auto_save_setup=true
MCINI
    ok "mc Systemkonfiguration angelegt ($MC_INI)"
elif [[ -f "$MC_INI" ]]; then
    info "mc Konfiguration vorhanden – nicht uberschrieben"
else
    info "mc Konfigurationsverzeichnis fehlt – ubersprungen"
fi

# =============================================================================
section "9 · BEREINIGUNG"
# =============================================================================
apt-get -y autoremove -qq
apt-get -y autoclean -qq
ok "Paket-Cache bereinigt"

# =============================================================================
section "ZUSAMMENFASSUNG"
# =============================================================================
echo ""
echo -e "${BOLD}┌─────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}│     SYSTEMKONFIGURATION ABGESCHLOSSEN    │${RESET}"
echo -e "${BOLD}└─────────────────────────────────────────┘${RESET}"
echo -e "  Distro       : ${GREEN}${DISTRO_ID} ${DISTRO_VERSION_ID} (${DISTRO_CODENAME})${RESET}"

TZ_ACTIVE="$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo n/a)"
[[ "$IS_SYSTEMD" -eq 1 ]] && \
    TZ_ACTIVE="$(timedatectl show --property=Timezone --value 2>/dev/null || echo "$TZ_ACTIVE")"
echo -e "  Zeitzone     : ${GREEN}${TZ_ACTIVE}${RESET}"

LOCALE_FILE="/etc/locale.conf"
[[ "$USE_LOCALE_CONF" -eq 0 ]] && LOCALE_FILE="/etc/default/locale"
LANG_VAL="$(grep '^LANG=' "$LOCALE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo n/a)"
LC_ALL_VAL="$(grep '^LC_ALL=' "$LOCALE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo n/a)"
echo -e "  LANG         : ${GREEN}${LANG_VAL}${RESET}  [${LOCALE_FILE}]"
echo -e "  LC_ALL       : ${GREEN}${LC_ALL_VAL}${RESET}"

LOCALES_ACTIVE="$(locale -a 2>/dev/null | grep -Ei '^(de_DE|en_US)\.utf' | tr '\n' ' ' || echo n/a)"
echo -e "  Locales      : ${GREEN}${LOCALES_ACTIVE}${RESET}"

KB_LAYOUT="$(grep '^XKBLAYOUT=' /etc/default/keyboard 2>/dev/null | cut -d= -f2 | tr -d '"' || echo n/a)"
echo -e "  Tastatur     : ${GREEN}${KB_LAYOUT}${RESET}"

for pkg in nano mc; do
    VER="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo nicht installiert)"
    printf "  %-13s: ${GREEN}%s${RESET}\n" "$pkg" "$VER"
done
echo ""
[[ "$USE_LOCALE_CONF" -eq 1 ]] && {
    echo -e "  ${YELLOW}[Trixie/25.x+] Locale: /etc/locale.conf (Symlink: /etc/default/locale)${RESET}"
    echo -e "  ${YELLOW}[Trixie/25.x+] /etc/timezone ignoriert – /etc/localtime massgeblich${RESET}"
}
echo -e "  ${YELLOW}Neu einloggen oder 'exec bash' fuer aktive Locale-Uebernahme${RESET}"
echo ""
echo -e "${GREEN}${BOLD}✅  Fertig!${RESET}"
echo ""
[[ "${KEEP_OPEN:-0}" == "1" ]] && read -rp "Druecke ENTER zum Beenden ... " _
