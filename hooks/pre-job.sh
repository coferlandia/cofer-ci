#!/usr/bin/env bash
# Cada runner tiene su propio Docker daemon. El lease compartido impide que
# la limpieza del host toque este runner mientras comienza un job.
set -uo pipefail
# shellcheck source=cache-pressure.sh
source "/opt/runner-hooks/cache-pressure.sh"
# shellcheck source=runner-lease.sh
source "/opt/runner-hooks/runner-lease.sh"

log() {
  printf '[pre-job] %s\n' "$*"
}

pre_job_main() {
  if ! docker info >/dev/null 2>&1; then
    log "ERROR: Docker CI no responde"
    return 1
  fi

  clear_runner_tmp "pre-job"
  reclaim_runner_cache_if_needed "pre-job"

  log "Eliminando residuos del job anterior en este Docker CI aislado"
  docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  docker volume prune -f >/dev/null 2>&1 || true

  docker system df || true
}

if with_runner_cleanup_lease pre_job_main; then
  exit 0
fi

rc=$?
if [[ "$rc" -eq 75 ]]; then
  log "ERROR: no se obtuvo el lease de almacenamiento; se evita iniciar el job durante una limpieza"
else
  log "ERROR: falló la preparación del runner (rc=$rc)"
fi
exit 1
