#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_DIR"

failures=0
ok() { printf 'OK    %s\n' "$1"; }
fail() { printf 'ERROR %s\n' "$1" >&2; failures=$((failures + 1)); }

for file in scripts/*.sh hooks/*.sh runner/*.sh; do
  if bash -n "$file"; then
    ok "Sintaxis Bash: $file"
  else
    fail "Sintaxis Bash: $file"
  fi
done

if jq empty config/docker-daemon.json >/dev/null 2>&1; then
  ok "JSON Docker daemon"
else
  fail "JSON Docker daemon"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  temp_env="$(mktemp)"
  cp .env.example "$temp_env"
  if docker compose --env-file "$temp_env" config >/dev/null; then
    ok "Docker Compose config"
  else
    fail "Docker Compose config"
  fi
  rm -f "$temp_env"
else
  printf 'SKIP  Docker Compose config: Docker no disponible\n'
fi

if grep -RInE '^[[:space:]]+ports:' compose.yml >/dev/null; then
  fail "compose.yml no debe publicar puertos"
else
  ok "Sin puertos publicados"
fi

for service in runner-01 runner-02 runner-03 runner-04 docker-ci-01 docker-ci-02 docker-ci-03; do
  grep -q "^  ${service}:" compose.yml && ok "Servicio ${service}" || fail "Servicio ${service}"
done

for setting in RUNNER_OFFLINE_CHECKS_BEFORE_RESTART RUNNER_RESTART_COOLDOWN_SECONDS; do
  grep -q "^${setting}=" monitoring.env.example && \
    ok "Configuración watchdog ${setting}" || \
    fail "Configuración watchdog ${setting}"
done

for doc in \
  docs/CLEAN_INSTALL.md \
  docs/UPGRADE.md \
  docs/ARCHITECTURE.md \
  docs/GITHUB_CONFIGURATION.md \
  docs/MAINTENANCE.md \
  docs/MONITORING.md \
  docs/TROUBLESHOOTING.md; do
  [[ -s "$doc" ]] && ok "Documento $doc" || fail "Documento $doc"
done

grep -q 'RUNNER_LABELS: ${RUNNER_04_LABELS:-coferlandia-ci-gate}' compose.yml &&
  ok "Runner Gate usa label exclusiva" || fail "Runner Gate debe usar coferlandia-ci-gate"
if awk '/^  runner-04:/{flag=1;next}/^  [a-zA-Z0-9_-]+:/{if(flag) exit}flag' compose.yml | grep -q 'DOCKER_HOST'; then
  fail "Runner Gate no debe recibir Docker-in-Docker"
else
  ok "Runner Gate sin Docker-in-Docker"
fi


grep -q '^CI_STORAGE_SIZE=80G  printf '\nValidación fallida: %s problema(s).\n' "$failures" >&2
  exit 1
fi

printf '\nPaquete validado.\n'
 .env.example &&
  ok "Baseline de almacenamiento CI 80G" || fail "CI_STORAGE_SIZE debe ser 80G"

for hook in hooks/pre-job.sh hooks/post-job.sh; do
  grep -q 'source "/opt/runner-hooks/cache-pressure.sh"' "$hook" &&
    ok "$hook usa protección de cache por presión" ||
    fail "$hook debe cargar cache-pressure.sh"
done

grep -q 'RUNNER_CACHE_PRESSURE_PERCENT' compose.yml &&
  grep -q 'RUNNER_CACHE_EMERGENCY_PERCENT' compose.yml &&
  ok "Compose expone umbrales de presión de cache" ||
  fail "Compose debe exponer los umbrales de presión de cache"

if (( failures > 0 )); then
  printf '\nValidación fallida: %s problema(s).\n' "$failures" >&2
  exit 1
fi

printf '\nPaquete validado.\n'
