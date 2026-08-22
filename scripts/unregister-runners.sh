#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

load_env

found=false
for service in "${RUNNER_SERVICES[@]}"; do
  [[ -f "$(runner_storage_dir "$service")/.runner" ]] && found=true
done

if [[ "$found" != true ]]; then
  log "No existen registros locales"
  exit 0
fi

cat <<EOF_MESSAGE
Obtenga tokens de eliminación desde la pantalla de cada runner en GitHub.
Un token de registro anterior puede haber vencido y no necesariamente sirve.
EOF_MESSAGE

for service in "${RUNNER_SERVICES[@]}"; do
  storage="$(runner_storage_dir "$service")"
  [[ -f "$storage/.runner" ]] || continue
  name="$(runner_name "$service")"

  read -r -s -p "Token temporal para eliminar ${name}: " token
  printf '\n'
  [[ -n "$token" ]] || fatal "El token no puede estar vacío"

  compose stop "$service" || true
  RUNNER_TOKEN="$token" compose run --rm --no-deps \
    -e RUNNER_TOKEN="$token" \
    "$service" remove
  unset token RUNNER_TOKEN
done

log "Runners desregistrados. Deteniendo el stack."
compose down
