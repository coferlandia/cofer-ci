#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env
load_monitor_env

failures=0

check() {
  local description="$1"
  shift

  if "$@"; then
    printf 'OK    %s\n' "$description"
  else
    printf 'ERROR %s\n' "$description"
    failures=$((failures + 1))
  fi
}

container_is_healthy() {
  local service="$1" cid
  cid="$(compose ps -q "$service")"
  [[ -n "$cid" ]] || return 1
  [[ "$(docker inspect -f '{{.State.Health.Status}}' "$cid")" == "healthy" ]]
}

github_runners_response=""
if [[ -n "${GITHUB_MONITOR_TOKEN:-}" ]]; then
  if [[ "${GITHUB_SCOPE_TYPE:-org}" == "repo" ]]; then
    github_runners_api="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners?per_page=100"
  else
    github_runners_api="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners?per_page=100"
  fi

  github_runners_response="$(
    curl -fsS --max-time 15 \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer ${GITHUB_MONITOR_TOKEN}" \
      -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION:-2026-03-10}" \
      "$github_runners_api" 2>/dev/null || true
  )"
fi

github_runner_is_online() {
  local name="$1"
  [[ -n "$github_runners_response" ]] || return 1
  [[ "$(
    jq -r --arg name "$name" \
      '.runners[]? | select(.name == $name) | .status' \
      <<<"$github_runners_response" |
      head -n1
  )" == "online" ]]
}

check "Docker host responde" docker info
check "Filesystem CI montado" mountpoint -q "$CI_STORAGE_ROOT"

for index in 01 02; do
  runner="runner-${index}"
  dind="docker-ci-${index}"
  name="$(runner_name "$runner")"
  storage="$(runner_storage_dir "$runner")"

  check "${name} registrado localmente" test -f "$storage/.runner"
  check "Contenedor ${runner} healthy" container_is_healthy "$runner"
  check "${dind} responde" compose exec -T "$dind" docker info
  check "Docker Compose dentro de ${runner}" \
    compose exec -T "$runner" docker compose version
  check "Salida HTTPS de ${runner} hacia GitHub" \
    compose exec -T "$runner" curl -fsS --max-time 15 https://api.github.com/zen
  check "Broker de GitHub Actions accesible desde ${runner}" \
    compose exec -T "$runner" curl -fsS --max-time 15 https://broker.actions.githubusercontent.com/health

done

check "Timer watchdog habilitado" \
  systemctl is-enabled --quiet coferlandia-ci-watchdog.timer
check "Timer cleanup habilitado" \
  systemctl is-enabled --quiet coferlandia-ci-cleanup.timer

if [[ -n "${GITHUB_MONITOR_TOKEN:-}" ]]; then
  if jq -e '.runners | arrays' <<<"$github_runners_response" >/dev/null 2>&1; then
    for service in "${RUNNER_SERVICES[@]}"; do
      name="$(runner_name "$service")"
      check "GitHub reporta ${name} online" github_runner_is_online "$name"
    done
  else
    printf 'ERROR No se pudo consultar la API de runners de GitHub\n'
    failures=$((failures + 1))
  fi
else
  printf 'SKIP  Estado remoto en GitHub: GITHUB_MONITOR_TOKEN no disponible\n'
fi

check "Salida HTTPS del host hacia Telegram" \
  curl -sS -o /dev/null --max-time 15 https://api.telegram.org

if (( failures > 0 )); then
  printf '\nFallaron %s comprobaciones.\n' "$failures"
  exit 1
fi

printf '\nInstalación de dos runners verificada localmente y en los controles remotos disponibles.\n'
