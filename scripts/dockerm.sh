#!/usr/bin/env bash
#####################################################################
#              AdronTec – IT Security Department                     #
#         Ultimate Docker Manager 2025 - by M.Tuppek                #
#                                                                    #
# Kompatibel: Debian 12 (Bookworm) · Debian 13 (Trixie)             #
#             Ubuntu 22.04 · 24.04 · 25.04 · 25.10                  #
#             Docker CE v20+ · Compose V2 (Plugin)                  #
#                                                                    #
# Idempotent: Ja – beliebig oft ausführbar                           #
#                                                                    #
# Erster Aufruf:   sudo bash dockerm.sh                             #
# Danach überall:  dockerm                                           #
#####################################################################

set -euo pipefail

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly BOLD=$'\033[1m'
readonly NC=$'\033[0m'

COMPOSE_CMD=""
DOCKER_VERSION=""
COMPOSE_VERSION=""
DISTRO_ID=""
DISTRO_VERSION_ID=""
DISTRO_CODENAME=""
SCRIPT_ARG="${1:-}"
SELF_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"
INSTALL_TARGET="/usr/local/bin/dockerm"
GITHUB_RAW="https://raw.githubusercontent.com/halonke/snippet/main/scripts/dockerm.sh"

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR]${NC}   $*" >&2; }
section() {
  echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $*${NC}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}"
}
pause()   { echo ""; read -rp "$(echo -e "${CYAN}")[Enter] zum Fortfahren...$(echo -e "${NC}") " _; }
confirm() {
  local ans
  read -rp "$(echo -e "${YELLOW}")${1:-Fortfahren}? (j/n): $(echo -e "${NC}")" ans
  [[ $ans =~ ^[JjYy]$ ]]
}
select_item() {
  local prompt="$1"; shift; local items=("$@")
  [[ ${#items[@]} -eq 0 ]] && { err "Keine Einträge vorhanden."; return 1; }
  echo -e "${CYAN}${prompt}${NC}"
  PS3="$(echo -e "${CYAN}")Auswahl [0=Abbruch]: $(echo -e "${NC}")"
  select item in "${items[@]}"; do
    [[ $REPLY == 0 ]] && return 1
    [[ -n "$item" ]] && { echo "$item"; return 0; }
    err "Ungültige Auswahl."
  done
}

get_containers() { docker ps "${1:--a}" --format '{{.Names}}' 2>/dev/null; }
get_images()     { docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v '<none>'; }
get_networks()   { docker network ls --format '{{.Name}}' 2>/dev/null; }
get_volumes()    { docker volume ls --format '{{.Name}}' 2>/dev/null; }

self_install() {
  section "Selbst-Installation als 'dockerm'"
  [[ $EUID -ne 0 ]] && { err "Installation erfordert root. Bitte: sudo bash $0"; exit 1; }
  if [[ "$SELF_PATH" != "$INSTALL_TARGET" ]]; then
    cp "$SELF_PATH" "$INSTALL_TARGET"
    chmod +x "$INSTALL_TARGET"
    ok "Installiert als: ${INSTALL_TARGET}"
  else
    ok "Bereits installiert als: ${INSTALL_TARGET}"
  fi
  if ! echo "$PATH" | grep -q "/usr/local/bin"; then
    warn "/usr/local/bin nicht im PATH."
    grep -q "/usr/local/bin" /etc/environment 2>/dev/null || \
      sed -i 's|PATH="\(.*\)"|PATH="/usr/local/bin:\1"|' /etc/environment 2>/dev/null || \
      echo 'PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"' >> /etc/environment
  fi
  echo ""
  echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║  ✅  'dockerm' ist jetzt systemweit       ║${NC}"
  echo -e "${BOLD}${GREEN}║     verfügbar!                             ║${NC}"
  echo -e "${BOLD}${GREEN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "${BOLD}${GREEN}║  Aufruf:  dockerm                          ║${NC}"
  echo -e "${BOLD}${GREEN}║           sudo dockerm                     ║${NC}"
  echo -e "${BOLD}${GREEN}║  Update:  sudo dockerm --update-self       ║${NC}"
  echo -e "${BOLD}${GREEN}║  Docker:  sudo dockerm --install-docker    ║${NC}"
  echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════╝${NC}"
  echo ""
}

detect_distro() {
  [[ -f /etc/os-release ]] || return
  . /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_VERSION_ID="${VERSION_ID:-0}"
  DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
}

install_docker() {
  section "Docker Installation"
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    ok "Docker bereits installiert (v$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')) – kein Eingriff nötig."
    pause; return 0
  fi
  [[ $EUID -ne 0 ]] && { err "Docker-Installation erfordert root-Rechte."; pause; return 1; }
  detect_distro
  case "$DISTRO_ID" in
    debian|ubuntu) ;;
    *) err "Nicht unterstützt: $DISTRO_ID"; echo "  https://docs.docker.com/engine/install/"; pause; return 1 ;;
  esac
  info "Installiere Docker für: ${DISTRO_ID} ${DISTRO_VERSION_ID} (${DISTRO_CODENAME})"
  apt-get remove -y docker docker-engine docker.io containerd runc podman-docker 2>/dev/null || true
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release apt-transport-https
  install -m 0755 -d /etc/apt/keyrings
  local KEY_PATH="/etc/apt/keyrings/docker.asc"
  if [[ ! -f "$KEY_PATH" ]] || [[ $(find "$KEY_PATH" -mtime +30 2>/dev/null | wc -l) -gt 0 ]]; then
    curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o "$KEY_PATH"
    chmod a+r "$KEY_PATH"
    info "Docker GPG-Key aktualisiert"
  fi
  local REPO_FILE="/etc/apt/sources.list.d/docker.list"
  local ARCH; ARCH=$(dpkg --print-architecture)
  local CODENAME="$DISTRO_CODENAME"
  [[ -z "$CODENAME" || "$CODENAME" == "unknown" ]] && CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
  [[ -z "$CODENAME" ]] && { err "Konnte Codename nicht ermitteln."; pause; return 1; }
  local REPO_LINE="deb [arch=${ARCH} signed-by=${KEY_PATH}] https://download.docker.com/linux/${DISTRO_ID} ${CODENAME} stable"
  if [[ ! -f "$REPO_FILE" ]] || ! grep -qF "$CODENAME" "$REPO_FILE" 2>/dev/null; then
    echo "$REPO_LINE" > "$REPO_FILE"
    info "Docker Repository konfiguriert (${CODENAME})"
  fi
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker 2>/dev/null || true
  systemctl start docker 2>/dev/null || true
  ok "Docker erfolgreich installiert!"
  if [[ -n "${SUDO_USER:-}" ]] && id "$SUDO_USER" &>/dev/null; then
    groups "$SUDO_USER" | grep -q docker || { usermod -aG docker "$SUDO_USER"; ok "User '${SUDO_USER}' zur docker-Gruppe hinzugefügt"; }
  fi
  pause
}

check_requirements() {
  detect_distro
  if ! command -v docker &>/dev/null; then
    warn "Docker ist nicht installiert."
    if confirm "Docker jetzt automatisch installieren"; then
      install_docker || { err "Installation fehlgeschlagen."; exit 1; }
    else
      err "Docker erforderlich. Abbruch."
      echo -e "${CYAN}Installieren mit:${NC}  sudo dockerm --install-docker"
      exit 1
    fi
  fi
  DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
  if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null | head -1 || echo "v2.x")
  elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    COMPOSE_VERSION=$(docker-compose version --short 2>/dev/null || echo "v1.x")
    warn "Docker Compose V1 erkannt (EOL). Upgrade: sudo apt install docker-compose-plugin"
  else
    warn "Docker Compose nicht gefunden."
    confirm "docker-compose-plugin jetzt installieren" && \
      { apt-get install -y docker-compose-plugin 2>/dev/null || true; COMPOSE_CMD="docker compose"; }
  fi
  if ! docker info &>/dev/null 2>&1; then
    warn "Docker Daemon läuft nicht. Versuche Start..."
    if [[ $EUID -eq 0 ]]; then
      systemctl start docker && ok "Docker Daemon gestartet" || \
        { err "Docker konnte nicht gestartet werden."; err "Prüfe: sudo journalctl -xeu docker"; exit 1; }
    else
      err "Docker Daemon inaktiv. Bitte: sudo systemctl start docker"; exit 1
    fi
  fi
  export DOCKER_BUILDKIT=1
  local docker_major="${DOCKER_VERSION%%.*}"
  if [[ "$docker_major" =~ ^[0-9]+$ ]] && [[ "$docker_major" -ge 29 ]]; then
    local api_override="/etc/systemd/system/docker.service.d/api-version.conf"
    if [[ ! -f "$api_override" ]] && [[ $EUID -eq 0 ]]; then
      warn "Docker v29+ erkannt – DOCKER_MIN_API_VERSION empfohlen"
      if confirm "API-Kompatibilität konfigurieren (1.24)"; then
        mkdir -p "$(dirname "$api_override")"
        printf '[Service]\nEnvironment="DOCKER_MIN_API_VERSION=1.24"\n' > "$api_override"
        systemctl daemon-reload && systemctl restart docker
        ok "API-Version konfiguriert"
      fi
    fi
  fi
}

show_system_info() {
  clear
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${BLUE}║         AdronTec ⋄ Ultimate Docker Manager 2025              ║${NC}"
  echo -e "${BOLD}${BLUE}║                    by M.Tuppek                               ║${NC}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${CYAN}System:${NC}      $(uname -s) $(uname -r) | ${DISTRO_ID} ${DISTRO_VERSION_ID}"
  echo -e "  ${CYAN}Docker:${NC}      ${DOCKER_VERSION:-n/a}"
  echo -e "  ${CYAN}Compose:${NC}     ${COMPOSE_VERSION:-n/a}  (${COMPOSE_CMD:-nicht verfügbar})"
  echo -e "  ${CYAN}BuildKit:${NC}    $([[ "${DOCKER_BUILDKIT:-0}" == "1" ]] && echo -e "${GREEN}✓ Aktiv${NC}" || echo -e "${YELLOW}✗ Inaktiv${NC}")"
  echo -e "  ${CYAN}Befehl:${NC}      ${BOLD}dockerm${NC}"
  echo ""
  local running total images volumes networks
  running=$(docker ps -q 2>/dev/null | wc -l)
  total=$(docker ps -aq 2>/dev/null | wc -l)
  images=$(docker images -q 2>/dev/null | wc -l)
  volumes=$(docker volume ls -q 2>/dev/null | wc -l)
  networks=$(docker network ls -q 2>/dev/null | wc -l)
  echo -e "  ${CYAN}Container:${NC}   ${GREEN}${running}${NC} laufend / ${total} gesamt"
  echo -e "  ${CYAN}Images:${NC}      ${images}"
  echo -e "  ${CYAN}Volumes:${NC}     ${volumes}"
  echo -e "  ${CYAN}Netzwerke:${NC}   ${networks}"
  echo ""
}

show_containers() {
  clear
  echo -e "${BOLD}${BLUE}═══ Container Übersicht ═══${NC}"
  docker ps "${1:--a}" --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  pause
}

container_action() {
  local action="$1" filter="${2:-}"
  mapfile -t containers < <(get_containers "$filter")
  local container
  container=$(select_item "Container auswählen:" "${containers[@]}") || return 0
  case "$action" in
    start)   docker start "$container"   && ok "Container '${container}' gestartet" ;;
    stop)    docker stop "$container"    && ok "Container '${container}' gestoppt" ;;
    restart) docker restart "$container" && ok "Container '${container}' neu gestartet" ;;
    remove)  confirm "Container '${container}' wirklich entfernen" && \
             docker rm -f "$container" && ok "Container entfernt" ;;
    logs)
      echo -e "${CYAN}Logs für '${container}' (Ctrl+C zum Beenden)${NC}"
      docker logs -f --tail 100 "$container" 2>/dev/null || \
        { err "Logging-Treiber unterstützt kein Lesen."; confirm "JSON-File Logging aktivieren" && configure_logging; } ;;
    exec)
      echo -e "${CYAN}Verbinde zu '${container}'...${NC}"
      docker exec -it "$container" bash 2>/dev/null || \
      docker exec -it "$container" sh   2>/dev/null || \
      err "Keine Shell im Container verfügbar." ;;
    inspect) docker inspect "$container" | less ;;
    top)     docker top "$container" ;;
  esac
  pause
}

show_stats() {
  clear
  echo -e "${BOLD}${BLUE}═══ Container Ressourcen (Ctrl+C zum Beenden) ═══${NC}"
  docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
}

show_healthchecks() {
  clear
  echo -e "${BOLD}${BLUE}═══ Container Healthchecks ═══${NC}"
  printf "%-32s %-15s %s\n" "CONTAINER" "STATUS" "LETZTER OUTPUT"
  echo "────────────────────────────────────────────────────────────────"
  local found=0
  for container in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    found=1
    local hs
    hs=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null)
    local log=""
    [[ "$hs" != "none" ]] && log=$(docker inspect --format \
      '{{if .State.Health.Log}}{{(index .State.Health.Log 0).Output}}{{end}}' \
      "$container" 2>/dev/null | tr -d '\n' | head -c 50)
    case "$hs" in
      healthy)   printf "%-32s ${GREEN}%-15s${NC} %s\n"  "$container" "$hs" "$log" ;;
      unhealthy) printf "%-32s ${RED}%-15s${NC} %s\n"    "$container" "$hs" "$log" ;;
      starting)  printf "%-32s ${YELLOW}%-15s${NC} %s\n" "$container" "$hs" "$log" ;;
      *)         printf "%-32s ${CYAN}%-15s${NC} %s\n"   "$container" "$hs" "kein Healthcheck" ;;
    esac
  done
  [[ $found -eq 0 ]] && warn "Keine laufenden Container."
  pause
}

show_images() {
  clear
  echo -e "${BOLD}${BLUE}═══ Images Übersicht ═══${NC}"
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedAt}}"
  pause
}

pull_image() {
  read -rp "Image (z.B. nginx:latest): " imgname
  [[ -z "$imgname" ]] && { err "Kein Name angegeben."; pause; return; }
  docker pull "$imgname" && ok "Image '${imgname}' heruntergeladen"
  pause
}

remove_image() {
  mapfile -t images < <(get_images)
  local image
  image=$(select_item "Image entfernen:" "${images[@]}") || return 0
  confirm "Image '${image}' entfernen" && docker rmi "$image" && ok "Image entfernt"
  pause
}

scan_image_vulnerabilities() {
  local has_scout=0
  command -v docker-scout &>/dev/null && has_scout=1
  docker scout version &>/dev/null 2>&1 && has_scout=1
  if [[ $has_scout -eq 0 ]]; then
    warn "Docker Scout nicht installiert."
    echo -e "${CYAN}Installation:${NC} curl -sSfL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh | sh"
    pause; return
  fi
  mapfile -t images < <(get_images)
  local image
  image=$(select_item "Image scannen:" "${images[@]}") || return 0
  clear; echo -e "${BOLD}${BLUE}═══ Scout-Scan: '${image}' ═══${NC}"
  docker scout cves "$image" 2>/dev/null || err "Scout-Scan fehlgeschlagen."
  pause
}

prune_images() {
  confirm "ALLE unbenutzten Images löschen" || return 0
  docker image prune -af && ok "Ungenutzte Images entfernt."
  pause
}

show_networks() {
  clear
  echo -e "${BOLD}${BLUE}═══ Netzwerke Übersicht ═══${NC}"
  docker network ls --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"
  pause
}

create_network() {
  read -rp "Netzwerkname: " netname
  [[ -z "$netname" ]] && { err "Name erforderlich."; pause; return; }
  docker network inspect "$netname" &>/dev/null 2>&1 && { warn "Netzwerk '${netname}' existiert bereits."; pause; return; }
  read -rp "Driver [bridge]: " driver; driver="${driver:-bridge}"
  read -rp "Subnet (optional, z.B. 172.20.0.0/16): " subnet
  local cmd="docker network create --driver ${driver}"
  [[ -n "$subnet" ]] && cmd+=" --subnet ${subnet}"
  $cmd "$netname" && ok "Netzwerk '${netname}' erstellt."
  pause
}

remove_network() {
  mapfile -t networks < <(get_networks)
  local network
  network=$(select_item "Netzwerk entfernen:" "${networks[@]}") || return 0
  confirm "Netzwerk '${network}' entfernen" && docker network rm "$network" && ok "Netzwerk entfernt."
  pause
}

inspect_network() {
  mapfile -t networks < <(get_networks)
  local network
  network=$(select_item "Netzwerk inspizieren:" "${networks[@]}") || return 0
  clear; docker network inspect "$network" | less
}

show_volumes() {
  clear
  echo -e "${BOLD}${BLUE}═══ Volumes Übersicht ═══${NC}"
  docker volume ls --format "table {{.Driver}}\t{{.Name}}\t{{.Mountpoint}}"
  pause
}

create_volume() {
  read -rp "Volume-Name: " volname
  [[ -z "$volname" ]] && { err "Name erforderlich."; pause; return; }
  docker volume inspect "$volname" &>/dev/null 2>&1 && { warn "Volume '${volname}' existiert bereits."; pause; return; }
  docker volume create "$volname" && ok "Volume '${volname}' erstellt."
  pause
}

remove_volume() {
  mapfile -t volumes < <(get_volumes)
  local volume
  volume=$(select_item "Volume entfernen:" "${volumes[@]}") || return 0
  confirm "Volume '${volume}' entfernen (DATENVERLUST!)" && docker volume rm "$volume" && ok "Volume entfernt."
  pause
}

prune_volumes() {
  confirm "WARNUNG: Alle unbenutzten Volumes löschen (DATENVERLUST!)" || return 0
  docker volume prune -f && ok "Ungenutzte Volumes entfernt."
  pause
}

backup_volume() {
  mapfile -t volumes < <(get_volumes)
  local volume
  volume=$(select_item "Volume sichern:" "${volumes[@]}") || return 0
  local backup_dir="/tmp/docker_volume_backups"
  mkdir -p "$backup_dir"
  local ts; ts=$(date +"%Y%m%d_%H%M%S")
  echo -e "${CYAN}Sichere Volume '${volume}'...${NC}"
  docker run --rm \
    -v "${volume}:/data:ro" -v "${backup_dir}:/backup" \
    alpine tar czf "/backup/${volume}_${ts}.tar.gz" -C /data . \
    && ok "Backup: ${backup_dir}/${volume}_${ts}.tar.gz" \
    || err "Backup fehlgeschlagen."
  pause
}

find_compose_file() {
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [[ -f "$f" ]] && echo "$f" && return 0
  done
  return 1
}

compose_menu() {
  local compose_file=""
  compose_file=$(find_compose_file) || read -rp "Pfad zur Compose-Datei: " compose_file
  [[ ! -f "$compose_file" ]] && { err "Datei nicht gefunden: $compose_file"; pause; return; }
  while true; do
    clear
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║       Docker Compose Menü            ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Datei:${NC} ${compose_file}\n"
    echo "  1) Up · 2) Down · 3) Restart · 4) Logs · 5) PS"
    echo "  6) Pull · 7) Build · 8) Config · 9) Exec · 10) Scale"
    echo "  0) Zurück"
    echo ""
    read -rp "$(echo -e "${CYAN}")Auswahl: $(echo -e "${NC}")" opt
    case $opt in
      0) return ;;
      1) $COMPOSE_CMD -f "$compose_file" up -d ;;
      2) $COMPOSE_CMD -f "$compose_file" down ;;
      3) $COMPOSE_CMD -f "$compose_file" restart ;;
      4) $COMPOSE_CMD -f "$compose_file" logs -f --tail=100 ;;
      5) $COMPOSE_CMD -f "$compose_file" ps; pause; continue ;;
      6) $COMPOSE_CMD -f "$compose_file" pull ;;
      7) $COMPOSE_CMD -f "$compose_file" build --no-cache ;;
      8) $COMPOSE_CMD -f "$compose_file" config | less; continue ;;
      9)
        mapfile -t services < <($COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null)
        local svc; svc=$(select_item "Service:" "${services[@]}") || continue
        read -rp "Befehl [sh]: " cmd; cmd="${cmd:-sh}"
        $COMPOSE_CMD -f "$compose_file" exec "$svc" $cmd ;;
      10)
        mapfile -t services < <($COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null)
        local svc; svc=$(select_item "Service skalieren:" "${services[@]}") || continue
        read -rp "Anzahl Replicas: " replicas
        $COMPOSE_CMD -f "$compose_file" up -d --scale "${svc}=${replicas}" ;;
      *) err "Ungültige Auswahl." ;;
    esac
    pause
  done
}

system_prune() {
  clear
  echo -e "${BOLD}${RED}⚠  SYSTEM CLEANUP – WARNUNG  ⚠${NC}\n"
  docker system df
  echo ""
  echo "  Wird entfernt: gestoppte Container · ungenutzte Images · Netzwerke · Volumes · Build-Cache"
  echo ""
  confirm "Wirklich ALLES bereinigen (DATENVERLUST möglich)" || return 0
  docker system prune -af --volumes && ok "System bereinigt."
  pause
}

configure_logging() {
  local daemon_json="/etc/docker/daemon.json"
  section "JSON-File Logging konfigurieren"
  if [[ -f "$daemon_json" ]] && grep -q '"json-file"' "$daemon_json" 2>/dev/null; then
    ok "JSON-File Logging bereits konfiguriert:"; cat "$daemon_json"; pause; return
  fi
  [[ -f "$daemon_json" ]] && cp "$daemon_json" "${daemon_json}.bak.$(date +%s)" && ok "Backup erstellt"
  mkdir -p /etc/docker
  cat > "$daemon_json" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  }
}
EOF
  systemctl restart docker 2>/dev/null && ok "Docker neu gestartet mit json-file Logging." || \
    warn "Neustart fehlgeschlagen. Bitte: sudo systemctl restart docker"
  pause
}

show_disk_usage() {
  clear; echo -e "${BOLD}${BLUE}═══ Docker Speichernutzung ═══${NC}"
  docker system df -v; pause
}

export_container() {
  mapfile -t containers < <(get_containers)
  local container
  container=$(select_item "Container exportieren:" "${containers[@]}") || return 0
  local dir="/tmp/docker_exports/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$dir"
  echo -e "${CYAN}Exportiere '${container}'...${NC}"
  docker export "$container" -o "${dir}/${container}.tar" \
    && ok "Export: ${dir}/${container}.tar" || err "Export fehlgeschlagen."
  pause
}

update_docker() {
  section "Docker Update"
  [[ $EUID -ne 0 ]] && { err "Update erfordert root."; pause; return; }
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --only-upgrade \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || \
  apt-get upgrade -y docker-ce 2>/dev/null || true
  DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "?")
  COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "n/a")
  ok "Docker aktualisiert: v${DOCKER_VERSION}"
  pause
}

docker_info_full() {
  clear
  echo -e "${BOLD}${BLUE}═══ Vollständige Docker-Info ═══${NC}"
  docker info; echo ""
  echo -e "${BOLD}${BLUE}═══ Docker Version ═══${NC}"
  docker version; pause
}

add_user_to_docker_group() {
  read -rp "Username: " uname
  [[ -z "$uname" ]] && { err "Kein Username."; pause; return; }
  if ! id "$uname" &>/dev/null; then
    err "User '${uname}' existiert nicht."
  elif groups "$uname" | grep -q docker; then
    warn "User '${uname}' ist bereits in der docker-Gruppe."
  else
    usermod -aG docker "$uname"
    ok "User '${uname}' hinzugefügt. Neu einloggen erforderlich."
  fi
  pause
}

update_self() {
  section "dockerm von GitHub aktualisieren"
  [[ $EUID -ne 0 ]] && { err "Erfordert root."; pause; return; }
  info "Lade aktuelle Version von GitHub..."
  if command -v curl &>/dev/null; then
    curl -fsSL "$GITHUB_RAW" -o "$INSTALL_TARGET" \
      && chmod +x "$INSTALL_TARGET" \
      && ok "dockerm aktualisiert von GitHub" \
      || err "Update fehlgeschlagen."
  elif command -v wget &>/dev/null; then
    wget -qO "$INSTALL_TARGET" "$GITHUB_RAW" \
      && chmod +x "$INSTALL_TARGET" \
      && ok "dockerm aktualisiert von GitHub" \
      || err "Update fehlgeschlagen."
  else
    err "Weder curl noch wget verfügbar."
  fi
  pause
}

show_main_menu() {
  show_system_info
  cat <<MENU
${BOLD}${BLUE}┌────────────────────────────────────────────────────────────────┐
│                         HAUPTMENÜ                              │
└────────────────────────────────────────────────────────────────┘${NC}
${BOLD}  CONTAINER${NC}                             ${BOLD}IMAGES${NC}
   1)  Alle Container anzeigen           14) Images anzeigen
   2)  Laufende Container                15) Image pullen
   3)  Container starten                 16) Image entfernen
   4)  Container stoppen                 17) Image scannen (Scout)
   5)  Container neu starten             18) Ungenutzte Images löschen
   6)  Container entfernen
   7)  Container Logs                   ${BOLD}NETZWERK${NC}
   8)  In Container einsteigen           20) Netzwerke anzeigen
   9)  Container inspizieren             21) Netzwerk erstellen
  10)  Container Top (Prozesse)          22) Netzwerk entfernen
  11)  Container Stats (Live)            23) Netzwerk inspizieren
  12)  Healthchecks anzeigen
  13)  Container exportieren            ${BOLD}VOLUMES${NC}
                                         24) Volumes anzeigen
${BOLD}  SYSTEM & WARTUNG${NC}                      25) Volume erstellen
  30)  Docker Compose Menü              26) Volume entfernen
  31)  System bereinigen (prune)         27) Ungenutzte Volumes löschen
  32)  Speichernutzung anzeigen          28) Volume sichern (Backup)
  33)  Logging konfigurieren
  34)  Docker aktualisieren             ${BOLD}SETUP${NC}
  35)  Vollständige Docker-Info          40) Docker installieren/prüfen
  36)  User zu docker-Gruppe             41) dockerm aktualisieren (GitHub)
                                         42) System-Info neu laden
  ${BOLD}0) Beenden${NC}

MENU
}

main_loop() {
  while true; do
    show_main_menu
    read -rp "$(echo -e "${CYAN}")Auswahl: $(echo -e "${NC}")" choice
    case $choice in
      0)  echo -e "${GREEN}Auf Wiedersehen!${NC}"; exit 0 ;;
      1)  show_containers "-a" ;;
      2)  show_containers "" ;;
      3)  container_action "start" "" ;;
      4)  container_action "stop" "" ;;
      5)  container_action "restart" "" ;;
      6)  container_action "remove" "" ;;
      7)  container_action "logs" "" ;;
      8)  container_action "exec" "" ;;
      9)  container_action "inspect" "" ;;
      10) container_action "top" "" ;;
      11) show_stats ;;
      12) show_healthchecks ;;
      13) export_container ;;
      14) show_images ;;
      15) pull_image ;;
      16) remove_image ;;
      17) scan_image_vulnerabilities ;;
      18) prune_images ;;
      20) show_networks ;;
      21) create_network ;;
      22) remove_network ;;
      23) inspect_network ;;
      24) show_volumes ;;
      25) create_volume ;;
      26) remove_volume ;;
      27) prune_volumes ;;
      28) backup_volume ;;
      30) compose_menu ;;
      31) system_prune ;;
      32) show_disk_usage ;;
      33) configure_logging ;;
      34) update_docker ;;
      35) docker_info_full ;;
      36) add_user_to_docker_group ;;
      40) install_docker ;;
      41) update_self ;;
      42) check_requirements ;;
      *)  err "Ungültige Auswahl '${choice}'."; pause ;;
    esac
  done
}

main() {
  case "${SCRIPT_ARG}" in
    --install-docker) install_docker; exit 0 ;;
    --update-self)    self_install;   exit 0 ;;
    --help|-h)
      echo -e "${BOLD}Verwendung:${NC}"
      echo "  dockerm                         – Menü starten"
      echo "  sudo dockerm                    – Menü mit vollen Rechten"
      echo "  sudo dockerm --install-docker   – Docker installieren"
      echo "  sudo dockerm --update-self      – dockerm aktualisieren"
      exit 0 ;;
  esac
  if [[ $EUID -ne 0 ]]; then
    warn "Nicht als root ausgeführt. Installations- und Systemfunktionen benötigen sudo."
    warn "Empfohlen: sudo dockerm"
    echo ""; sleep 1
  fi
  [[ "$SELF_PATH" != "$INSTALL_TARGET" ]] && [[ $EUID -eq 0 ]] && self_install
  check_requirements
  main_loop
}

main "$@"
