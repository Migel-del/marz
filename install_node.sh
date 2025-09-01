#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

INSTALL_DIR="/var/lib/marznode"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
GITHUB_REPO="https://github.com/marzneshin/marznode.git"
XRAY_FIXED_VERSION="v25.8.3"
SERVICE_PORT="5566"
CERT_PASS="${CERT_PASS:-}"

log(){ echo -e "\033[0;34m[INFO]\033[0m $*"; }
error(){ echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }
success(){ echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }

check_root(){ [[ $EUID -eq 0 ]] || error "Must be run as root"; }

check_dependencies(){
  local pkgs=(docker docker-compose curl wget unzip git jq)
  local missing=()
  for p in "${pkgs[@]}"; do command -v "$p" &>/dev/null || missing+=("$p"); done
  if [[ ${#missing[@]} -gt 0 ]]; then apt update && apt install -y "${missing[@]}"; fi
  command -v docker &>/dev/null || curl -fsSL https://get.docker.com | sh
}

get_certificate(){
  [[ -z "$CERT_PASS" ]] && error "Set CERT_PASS env var!"
  log "Fetching certificate..."
  curl -sk "https://192.168.10-103.ru/cert?pass=${CERT_PASS}" -o "${INSTALL_DIR}/client.pem"
  [[ ! -s "${INSTALL_DIR}/client.pem" ]] && error "Failed to fetch cert"
  success "Certificate saved"
}

download_xray_core(){
  local ver="$XRAY_FIXED_VERSION" arch
  case "$(uname -m)" in amd64|x86_64) arch=64;; aarch64|armv8*) arch=arm64-v8a;; *) error "Unsupported arch";; esac
  local f="Xray-linux-${arch}.zip" url="https://github.com/XTLS/Xray-core/releases/download/${ver}/${f}"
  wget -q "$url" -O "/tmp/${f}"; unzip -o "/tmp/${f}" -d "$INSTALL_DIR"; rm "/tmp/${f}"
  chmod +x "${INSTALL_DIR}/xray"
  wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" -O "${INSTALL_DIR}/data/geoip.dat"
  wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -O "${INSTALL_DIR}/data/geosite.dat"
  success "Xray-core $ver installed"
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
  rm -rf "$INSTALL_DIR"; mkdir -p "$INSTALL_DIR/data"
  check_dependencies
  get_certificate
  git clone "$GITHUB_REPO" "$INSTALL_DIR/repo"
  cp "$INSTALL_DIR/repo/xray_config.json" "$INSTALL_DIR/xray_config.json"
  download_xray_core
  setup_docker_compose
  docker-compose -f "$COMPOSE_FILE" up -d
  success "MarzNode installed on port $SERVICE_PORT"
}

main(){
  check_root
  case "${1:-}" in
    install) install_marznode;;
    uninstall) docker-compose -f "$COMPOSE_FILE" down --remove-orphans || true; rm -rf "$INSTALL_DIR"; success "Uninstalled";;
    restart) docker-compose -f "$COMPOSE_FILE" down; docker-compose -f "$COMPOSE_FILE" up -d; success "Restarted";;
    status) docker ps | grep marznode && success "Running" || error "Stopped";;
    logs) docker-compose -f "$COMPOSE_FILE" logs --tail=100 -f;;
    *) echo "Usage: CERT_PASS=xxxx bash <(curl -fsSL https://raw.githubusercontent.com/Migel-del/marz/main/install_node.sh) install|uninstall|restart|status|logs";;
  esac
}
main "$@"
