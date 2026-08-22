#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

for cmd in docker curl jq mountpoint findmnt; do
  require_command "$cmd"
done

docker info >/dev/null 2>&1 || fatal "Docker Engine no responde para el usuario actual"
docker compose version >/dev/null 2>&1 || fatal "Docker Compose v2 no está disponible"

arch="$(uname -m)"
case "$arch" in
  x86_64|aarch64|arm64) ;;
  *) fatal "Arquitectura no soportada por este proyecto: ${arch}" ;;
esac

log "Docker: $(docker version --format '{{.Server.Version}}')"
log "Compose: $(docker compose version --short)"
log "Arquitectura: ${arch}"
log "Memoria: $(free -h | awk '/^Mem:/ {print $2}')"
log "Disco raíz: $(df -h / | awk 'NR==2 {print $4 " libres de " $2}')"
log "Prerrequisitos básicos correctos"
