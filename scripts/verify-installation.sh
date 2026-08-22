#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env

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

done

check "Salida HTTPS del host hacia Telegram" \
  curl -sS -o /dev/null --max-time 15 https://api.telegram.org

if (( failures > 0 )); then
  printf '\nFallaron %s comprobaciones.\n' "$failures"
  exit 1
fi

printf '\nInstalación local de dos runners verificada. Ejecute el workflow smoke test paralelo.\n'
