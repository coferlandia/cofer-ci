#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

load_env
require_command docker

[[ -d "${CI_STORAGE_ROOT}" ]] || \
  fatal "No existe ${CI_STORAGE_ROOT}; ejecute sudo scripts/install-host.sh"
mountpoint -q "${CI_STORAGE_ROOT}" || \
  fatal "${CI_STORAGE_ROOT} no está montado"

wait_healthy() {
  local service="$1" cid status=""
  log "Esperando que ${service} esté saludable"

  for _ in $(seq 1 60); do
    cid="$(compose ps -q "$service" 2>/dev/null || true)"
    if [[ -n "$cid" ]]; then
      status="$(
        docker inspect \
          -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
          "$cid" 2>/dev/null || true
      )"
    fi

    [[ "$status" == "healthy" ]] && return 0
    sleep 2
  done

  fatal "${service} no alcanzó estado healthy. Revise: docker compose logs ${service}"
}

missing=()
for service in "${RUNNER_SERVICES[@]}"; do
  if [[ ! -f "$(runner_storage_dir "$service")/.runner" ]]; then
    missing+=("$service")
  fi
done

if (( ${#missing[@]} == 0 )); then
  fatal "Los dos runners ya están registrados. Use scripts/status.sh o desregistre primero."
fi

cat <<EOF_MESSAGE
Obtenga un token temporal desde GitHub:
  Organización o repositorio > Settings > Actions > Runners > New self-hosted runner

URL configurada: ${RUNNER_URL}
Runner 01:       ${RUNNER_01_NAME}
Runner 02:       ${RUNNER_02_NAME}
Etiquetas:       ${RUNNER_LABELS}
Grupo:           ${RUNNER_GROUP}

El token suele poder reutilizarse mientras no venza. El script permite ingresar
uno distinto para el segundo runner si GitHub lo requiere.
EOF_MESSAGE

log "Construyendo una única imagen compartida por ambos listeners"
compose build --pull runner-01

log "Iniciando los dos daemons Docker CI para generar certificados TLS"
compose up -d docker-ci-01 docker-ci-02
wait_healthy docker-ci-01
wait_healthy docker-ci-02

first_token=""
for service in "${missing[@]}"; do
  name="$(runner_name "$service")"
  token=""

  if [[ -z "$first_token" ]]; then
    read -r -s -p "Token temporal para ${name}: " token
    printf '\n'
    [[ -n "$token" ]] || fatal "El token no puede estar vacío"
    first_token="$token"
  else
    read -r -s -p "Token para ${name} [Enter=reutilizar el anterior]: " token
    printf '\n'
    [[ -n "$token" ]] || token="$first_token"
  fi

  log "Registrando ${name} mediante ${service}"
  RUNNER_TOKEN="$token" compose run --rm --no-deps \
    -e RUNNER_TOKEN="$token" \
    "$service" register
  unset token RUNNER_TOKEN
done
unset first_token

log "Iniciando los dos runners persistentes"
compose up -d runner-01 runner-02

log "Registro terminado"
"${SCRIPT_DIR}/status.sh" || true
