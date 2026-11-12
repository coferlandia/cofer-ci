#!/usr/bin/env bash
# Limpieza liviana del Docker CI asignado exclusivamente a este runner.
# El post-job comparte lease con el mantenimiento del host.
set -uo pipefail
# shellcheck source=cache-pressure.sh
source "/opt/runner-hooks/cache-pressure.sh"
# shellcheck source=runner-lease.sh
source "/opt/runner-hooks/runner-lease.sh"

log() {
  printf '[post-job] %s\n' "$*"
}

post_job_main() {
  if ! docker info >/dev/null 2>&1; then
    log "ADVERTENCIA: Docker CI no responde; el watchdog realizará el diagnóstico"
    return 0
  fi

  log "Eliminando contenedores, redes y volúmenes temporales de este runner"
  docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  docker volume prune -f >/dev/null 2>&1 || true

  reclaim_runner_cache_if_needed "post-job"

  log "Se conservan imágenes y build cache reutilizables"
  docker system df || true
}

if with_runner_cleanup_lease post_job_main; then
  exit 0
fi

rc=$?
if [[ "$rc" -eq 75 ]]; then
  log "ADVERTENCIA: mantenimiento del host en curso; se difiere la limpieza post-job"
else
  log "ADVERTENCIA: limpieza post-job falló (rc=$rc); el timer la reintentará"
fi
exit 0
