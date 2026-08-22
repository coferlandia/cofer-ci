#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
load_env

any_runner_is_busy && \
  fatal "Hay al menos un job en ejecución. Actualice cuando ambos runners estén idle."

log "Actualizando Docker-in-Docker y reconstruyendo la imagen compartida de runners"
compose pull docker-ci-01 docker-ci-02
compose build --pull --no-cache runner-01
compose up -d
"${SCRIPT_DIR}/status.sh"
