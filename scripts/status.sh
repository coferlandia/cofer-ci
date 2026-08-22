#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

load_env
load_monitor_env

printf 'Coferlandia CI - dos runners concurrentes\n\n'

if ! docker info >/dev/null 2>&1; then
  printf 'Docker host:             ERROR - no responde\n'
  exit 1
fi
printf 'Docker host:             OK\n'

compose ps || true
printf '\n'

container_ids=()
for service in "${ALL_CI_SERVICES[@]}"; do
  cid="$(compose ps -q "$service" 2>/dev/null || true)"
  if [[ -z "$cid" ]]; then
    printf '%-24s %s\n' "${service}:" "missing"
    continue
  fi

  container_ids+=("$cid")
  state="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
  health="$(
    docker inspect \
      -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' \
      "$cid" 2>/dev/null || echo unknown
  )"
  restarts="$(docker inspect -f '{{.RestartCount}}' "$cid" 2>/dev/null || echo '?')"
  printf '%-24s state=%s health=%s restarts=%s\n' \
    "${service}:" "$state" "$health" "$restarts"
done

for dind in "${DIND_SERVICES[@]}"; do
  if compose exec -T "$dind" docker info >/dev/null 2>&1; then
    printf '%-24s %s\n' "${dind}:" 'Docker OK'
  else
    printf '%-24s %s\n' "${dind}:" 'Docker ERROR'
  fi
done

if mountpoint -q "${CI_STORAGE_ROOT}"; then
  usage="$(storage_usage_percent)"
  printf '%-24s %s%% usado\n' 'Filesystem CI:' "$usage"
  df -h "${CI_STORAGE_ROOT}" | tail -n 1
else
  printf '%-24s %s\n' 'Filesystem CI:' 'NO MONTADO'
fi

printf '\nRecursos actuales:\n'
if (( ${#container_ids[@]} > 0 )); then
  docker stats --no-stream \
    --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}' \
    "${container_ids[@]}" 2>/dev/null || true
fi

for dind in "${DIND_SERVICES[@]}"; do
  printf '\nUso interno de %s:\n' "$dind"
  compose exec -T "$dind" docker system df 2>/dev/null || true
done

if [[ -n "${GITHUB_MONITOR_TOKEN:-}" ]]; then
  if [[ "${GITHUB_SCOPE_TYPE:-org}" == "repo" ]]; then
    api="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners?per_page=100"
  else
    api="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners?per_page=100"
  fi

  response="$(
    curl -fsS \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer ${GITHUB_MONITOR_TOKEN}" \
      -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION:-2026-03-10}" \
      "$api" 2>/dev/null || true
  )"

  printf '\nEstado remoto en GitHub:\n'
  for service in "${RUNNER_SERVICES[@]}"; do
    name="$(runner_name "$service")"
    remote="$(
      jq -r --arg name "$name" \
        '.runners[]? | select(.name == $name) | "status=" + .status + " busy=" + (.busy|tostring) + " version=" + (.version // "n/a")' \
        <<<"$response" |
        head -n1
    )"
    printf '%-24s %s\n' "${name}:" "${remote:-no encontrado}"
  done
else
  printf '\nGitHub runners:          consulta remota no configurada\n'
fi
