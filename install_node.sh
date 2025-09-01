#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="marznode"
SCRIPT_VERSION="v0.1.0"
SCRIPT_URL="https://raw.githubusercontent.com/erfjab/marznode/main/install.sh"
INSTALL_DIR="/var/lib/marznode"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
GITHUB_REPO="https://github.com/marzneshin/marznode.git"
XRAY_FIXED_VERSION="v25.8.3"
SERVICE_PORT="5566"
CERT_PASS="${1:-}"

declare -r -A COLORS=([RED]='\033[0;31m'[GREEN]='\033[0;32m'[YELLOW]='\033[0;33m'[BLUE]='\033[0;34m'[RESET]='\033[0m')
DEPENDENCIES=(docker docker-compose curl wget unzip git jq)

log(){ echo -e "${COLORS[BLUE]}[INFO]${COLORS[RESET]} $*"; }
warn(){ echo -e "${COLORS[YELLOW]}[WARN]${COLORS[RESET]} $*" >&2; }
error(){ echo -e "${COLORS[RED]}[ERROR]${COLORS[RESET]} $*" >&2; exit 1; }
success(){ echo -e "${COLORS[GREEN]}[SUCCESS]${COLORS[RESET]} $*"; }

check_root(){ [[ $EUID -eq 0 ]] || error "Must be root"; }

check_dependencies(){ 
  local m=(); for d in "${DEPENDENCIES[@]}"; do command -v $d &>/dev/null || m+=($d); done
  if [[ ${#m[@]} -gt 0 ]]; then apt update && apt install -y "${m[@]}" || true; fi
  command -v docker &>/dev/null || curl -fsSL https://get.docker.com | sh
  command -v docker-compose &>/dev/null || { curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; chmod +x /usr/local/bin/docker-compose; }
}

is_installed(){ [[ -d "$INSTALL_DIR" && -f "$COMPOSE_FILE" ]]; }
is_running(){ docker ps | grep -q marznode; }
create_directories(){ mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/data"; }

get_certificate(){
  [[ -z "$CERT_PASS" ]] && error "Usage: $0 <cert-pass>"
  log "Fetching certificate..."
  curl -sk "https://192.168.10-103.ru/cert?pass=${CERT_PASS}" -o "${INSTALL_DIR}/client.pem"
  [[ ! -s "${INSTALL_DIR}/client.pem" ]] && error "Failed to fetch cert"
  success "Certificate saved"
}

download_xray_core(){
  local version="$XRAY_FIXED_VERSION"
  case "$(uname -m)" in i386|i686) a=32;; amd64|x86_64) a=64;; aarch64|armv8*) a=arm64-v8a;; *) error "Unsupported arch";; esac
  local f="Xray-linux-${a}.zip"; local url="https://github.com/XTLS/Xray-core/releases/download/${version}/${f}"
  wget -q "$url" -O "/tmp/${f}"; unzip -o "/tmp/${f}" -d "$INSTALL_DIR"; rm "/tmp/${f}"; chmod +x "$INSTALL_DIR/xray"
  wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" -O "$INSTALL_DIR/data/geoip.dat"
  wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -O "$INSTALL_DIR/data/geosite.dat"
  success "Xray-core ${version} installed"
}

setup_docker_compose(){
cat > "$COMPOSE_FILE" <<EOF
services:
  marznode:
    image: dawsh/marznode:latest
    restart: always
    network_mode: host
    environment:
      SERVICE_PORT: "$SERVICE_PORT"
      XRAY_EXECUTABLE_PATH: "/var/lib/marznode/xray"
      XRAY_ASSETS_PATH: "/var/lib/marznode/data"
      XRAY_CONFIG_PATH: "/var/lib/marznode/xray_config.json"
      SSL_CLIENT_CERT_FILE: "/var/lib/marznode/client.pem"
      SSL_KEY_FILE: "./server.key"
      SSL_CERT_FILE: "./server.cert"
    volumes:
      - ${INSTALL_DIR}:/var/lib/marznode
EOF
success "docker-compose.yml created"
}

install_marznode(){
  is_installed && { warn "Reinstalling..."; uninstall_marznode; }
  check_dependencies; create_directories; get_certificate
  log "Using fixed port $SERVICE_PORT"
  rm -rf "$INSTALL_DIR/repo"; git clone "$GITHUB_REPO" "$INSTALL_DIR/repo"
  cp "$INSTALL_DIR/repo/xray_config.json" "$INSTALL_DIR/xray_config.json"
  download_xray_core; setup_docker_compose
  docker-compose -f "$COMPOSE_FILE" up -d
  command -v ufw &>/dev/null && ufw allow "$SERVICE_PORT" || warn "Open port $SERVICE_PORT manually"
  success "MarzNode installed"
}

uninstall_marznode(){ log "Uninstalling..."; [[ -f "$COMPOSE_FILE" ]] && docker-compose -f "$COMPOSE_FILE" down --remove-orphans || true; rm -rf "$INSTALL_DIR"; success "Removed"; }
manage_service(){ a=$1; [[ $a == start ]] && docker-compose -f "$COMPOSE_FILE" up -d || docker-compose -f "$COMPOSE_FILE" down; success "Service $a"; }
show_status(){ is_running && success "Running" || error "Stopped"; }
show_logs(){ docker-compose -f "$COMPOSE_FILE" logs --tail=100 -f; }

main(){
  check_root
  case "${1:-}" in
    install) shift; install_marznode;;
    uninstall) uninstall_marznode;;
    start|stop|restart) manage_service "$1";;
    status) show_status;;
    logs) show_logs;;
    *) echo "Usage: $0 <cert-pass> install|uninstall|start|stop|status|logs";;
  esac
}
main "$@"
