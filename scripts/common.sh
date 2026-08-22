#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
MONITOR_ENV_FILE="/etc/coferlandia-ci-watchdog.env"

RUNNER_SERVICES=(runner-01 runner-02)
DIND_SERVICES=(docker-ci-01 docker-ci-02)
ALL_CI_SERVICES=(runner-01 runner-02 docker-ci-01 docker-ci-02)

log() {
  printf '[coferlandia-ci] %s\n' "$*"
}

warn() {
  printf '[coferlandia-ci] ADVERTENCIA: %s\n' "$*" >&2
}

fatal() {
  printf '[coferlandia-ci] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fatal "No se encontró el comando requerido: $1"
}

load_env() {
  [[ -f "$ENV_FILE" ]] || fatal "No existe ${ENV_FILE}. Copie .env.example a .env y edítelo."
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

load_monitor_env() {
  if [[ -f "$MONITOR_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$MONITOR_ENV_FILE"
    set +a
  fi
}

compose() {
  docker compose --project-directory "$PROJECT_DIR" --env-file "$ENV_FILE" "$@"
}

storage_usage_percent() {
  df --output=pcent "${CI_STORAGE_ROOT}" | tail -n 1 | tr -dc '0-9'
}

runner_index() {
  printf '%s' "${1##*-}"
}

runner_name() {
  local index variable
  index="$(runner_index "$1")"
  variable="RUNNER_${index}_NAME"
  printf '%s' "${!variable:-coferlandia-ci-${index}}"
}

runner_storage_dir() {
  printf '%s/runner-%s' "$CI_STORAGE_ROOT" "$(runner_index "$1")"
}

runner_work_dir() {
  printf '%s/work-%s' "$CI_STORAGE_ROOT" "$(runner_index "$1")"
}

runner_cache_dir() {
  printf '%s/cache-%s' "$CI_STORAGE_ROOT" "$(runner_index "$1")"
}

runner_is_busy() {
  local service="${1:-}" cid
  [[ -n "$service" ]] || return 1
  cid="$(compose ps -q "$service" 2>/dev/null || true)"
  [[ -n "$cid" ]] || return 1
  docker exec "$cid" pgrep -f 'Runner.Worker' >/dev/null 2>&1
}

any_runner_is_busy() {
  local service
  for service in "${RUNNER_SERVICES[@]}"; do
    runner_is_busy "$service" && return 0
  done
  return 1
}

service_health() {
  local service="$1" cid
  cid="$(compose ps -q "$service" 2>/dev/null || true)"
  [[ -n "$cid" ]] || return 1
  docker inspect \
    -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' \
    "$cid" 2>/dev/null
}
