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

for service in runner-01 runner-02 docker-ci-01 docker-ci-02; do
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

if (( failures > 0 )); then
  printf '\nValidación fallida: %s problema(s).\n' "$failures" >&2
  exit 1
fi

printf '\nPaquete validado.\n'
