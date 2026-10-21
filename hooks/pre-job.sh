#!/usr/bin/env bash
# Cada runner tiene su propio Docker daemon. Esta limpieza global es segura
# dentro de ese daemon porque no puede afectar al job concurrente del otro runner.
set -uo pipefail
# shellcheck source=cache-pressure.sh
source "/opt/runner-hooks/cache-pressure.sh"

log() {
  printf '[pre-job] %s\n' "$*"
}

if ! docker info >/dev/null 2>&1; then
  log "ERROR: Docker CI no responde"
  exit 1
fi

reclaim_runner_cache_if_needed "pre-job"

log "Eliminando residuos del job anterior en este Docker CI aislado"
docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1 || true
docker network prune -f >/dev/null 2>&1 || true
docker volume prune -f >/dev/null 2>&1 || true

docker system df || true
exit 0
