#!/usr/bin/env bash
set -Eeuo pipefail

RUNNER_HOME="/opt/actions-runner"
RUNNER_DIST="/opt/actions-runner-dist"

log() {
  printf '[runner] %s\n' "$*"
}

sync_distribution() {
  mkdir -p "$RUNNER_HOME"

  if [[ ! -x "$RUNNER_HOME/run.sh" ]]; then
    log "Inicializando distribución del runner en el volumen persistente"
    rsync -a "$RUNNER_DIST/" "$RUNNER_HOME/"
  fi
}

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf 'Falta la variable requerida %s\n' "$name" >&2
    exit 2
  fi
}

register_runner() {
  sync_distribution
  require_value RUNNER_URL
  require_value RUNNER_TOKEN
  require_value RUNNER_NAME

  cd "$RUNNER_HOME"

  if [[ -f .runner ]]; then
    log "El runner ya está registrado. No se modifica la configuración existente."
    exit 0
  fi

  local args=(
    --url "$RUNNER_URL"
    --token "$RUNNER_TOKEN"
    --name "$RUNNER_NAME"
    --work "${RUNNER_WORKDIR:-_work}"
    --unattended
    --replace
  )

  if [[ -n "${RUNNER_LABELS:-}" ]]; then
    args+=(--labels "$RUNNER_LABELS")
  fi

  if [[ -n "${RUNNER_GROUP:-}" && "${RUNNER_GROUP}" != "Default" ]]; then
    args+=(--runnergroup "$RUNNER_GROUP")
  fi

  log "Registrando ${RUNNER_NAME} en ${RUNNER_URL}"
  ./config.sh "${args[@]}"
  log "Registro completado"
}

remove_runner() {
  sync_distribution
  require_value RUNNER_TOKEN
  cd "$RUNNER_HOME"

  if [[ ! -f .runner ]]; then
    log "El runner no está registrado localmente"
    exit 0
  fi

  ./config.sh remove --unattended --token "$RUNNER_TOKEN"
  log "Runner eliminado de GitHub"
}

run_runner() {
  sync_distribution
  cd "$RUNNER_HOME"

  if [[ ! -f .runner ]]; then
    printf 'El runner todavía no está registrado. Ejecute scripts/register-runner.sh.\n' >&2
    exit 3
  fi

  mkdir -p "${RUNNER_WORKDIR:-_work}" /cache/toolcache /cache/nuget /cache/npm /cache/pip

  log "Iniciando listener ${RUNNER_NAME:-sin-nombre}"
  exec ./run.sh
}

case "${1:-run}" in
  register)
    register_runner
    ;;
  remove|unregister)
    remove_runner
    ;;
  run)
    run_runner
    ;;
  shell)
    exec /bin/bash
    ;;
  *)
    exec "$@"
    ;;
esac
