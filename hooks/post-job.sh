#!/usr/bin/env bash
# Limpieza liviana del Docker CI asignado exclusivamente a este runner.
# Conserva imágenes y build cache para acelerar el siguiente job de ese runner.
set -uo pipefail

log() {
  printf '[post-job] %s\n' "$*"
}

if ! docker info >/dev/null 2>&1; then
  log "ADVERTENCIA: Docker CI no responde; el watchdog realizará el diagnóstico"
  exit 0
fi

log "Eliminando contenedores, redes y volúmenes temporales de este runner"
docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1 || true
docker network prune -f >/dev/null 2>&1 || true
docker volume prune -f >/dev/null 2>&1 || true

log "Se conservan imágenes y build cache reutilizables"
docker system df || true
exit 0
