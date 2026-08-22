#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  cat >&2 <<'USAGE'
Uso:
  ./scripts/compare-host-surveys.sh ANTES.metrics DESPUES.metrics
USAGE
  exit 1
fi

BEFORE_FILE="$1"
AFTER_FILE="$2"
[[ -f "$BEFORE_FILE" ]] || { echo "No existe: $BEFORE_FILE" >&2; exit 1; }
[[ -f "$AFTER_FILE" ]] || { echo "No existe: $AFTER_FILE" >&2; exit 1; }

# Los archivos son generados por host-survey.sh y contienen asignaciones shell escapadas.
# shellcheck disable=SC1090
source "$BEFORE_FILE"
B_LABEL="${survey_label:-before}"
B_TIMESTAMP="${survey_timestamp:-n/a}"
B_CPU_COUNT="${cpu_count:-0}"
B_LOAD_1="${load_1:-0}"
B_LOAD_5="${load_5:-0}"
B_LOAD_15="${load_15:-0}"
B_MEMORY_USED="${memory_used_bytes:-0}"
B_MEMORY_AVAILABLE="${memory_available_bytes:-0}"
B_SWAP_USED="${swap_used_bytes:-0}"
B_ROOT_USED="${root_used_bytes:-0}"
B_ROOT_AVAILABLE="${root_available_bytes:-0}"
B_ROOT_PERCENT="${root_used_percent:-0}"
B_CI_MOUNTED="${ci_mounted:-false}"
B_CI_USED="${ci_used_bytes:-0}"
B_CI_PERCENT="${ci_used_percent:-0}"
B_DOCKER_CONTAINERS="${docker_containers:-0}"
B_DOCKER_RUNNING="${docker_running:-0}"
B_DOCKER_IMAGES="${docker_images:-0}"
B_DOCKER_VOLUMES="${docker_volumes:-0}"

unset survey_label survey_timestamp cpu_count load_1 load_5 load_15 memory_used_bytes memory_available_bytes \
  swap_used_bytes root_used_bytes root_available_bytes root_used_percent ci_mounted ci_used_bytes ci_used_percent \
  docker_containers docker_running docker_images docker_volumes

# shellcheck disable=SC1090
source "$AFTER_FILE"
A_LABEL="${survey_label:-after}"
A_TIMESTAMP="${survey_timestamp:-n/a}"
A_CPU_COUNT="${cpu_count:-0}"
A_LOAD_1="${load_1:-0}"
A_LOAD_5="${load_5:-0}"
A_LOAD_15="${load_15:-0}"
A_MEMORY_USED="${memory_used_bytes:-0}"
A_MEMORY_AVAILABLE="${memory_available_bytes:-0}"
A_SWAP_USED="${swap_used_bytes:-0}"
A_ROOT_USED="${root_used_bytes:-0}"
A_ROOT_AVAILABLE="${root_available_bytes:-0}"
A_ROOT_PERCENT="${root_used_percent:-0}"
A_CI_MOUNTED="${ci_mounted:-false}"
A_CI_USED="${ci_used_bytes:-0}"
A_CI_PERCENT="${ci_used_percent:-0}"
A_DOCKER_CONTAINERS="${docker_containers:-0}"
A_DOCKER_RUNNING="${docker_running:-0}"
A_DOCKER_IMAGES="${docker_images:-0}"
A_DOCKER_VOLUMES="${docker_volumes:-0}"

human_bytes() {
  numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || printf '%s B' "$1"
}

signed_bytes() {
  local delta="$1"
  if (( delta > 0 )); then
    printf '+%s' "$(human_bytes "$delta")"
  elif (( delta < 0 )); then
    printf -- '-%s' "$(human_bytes "$((-delta))")"
  else
    printf '0 B'
  fi
}

signed_int() {
  local delta="$1"
  (( delta > 0 )) && printf '+%s' "$delta" || printf '%s' "$delta"
}

printf 'Comparación de relevamientos de la VM\n\n'
printf 'Antes:   %s — %s\n' "$B_LABEL" "$B_TIMESTAMP"
printf 'Después: %s — %s\n\n' "$A_LABEL" "$A_TIMESTAMP"

printf '%-30s %18s %18s %16s\n' 'Métrica' 'Antes' 'Después' 'Diferencia'
printf '%-30s %18s %18s %16s\n' '------------------------------' '------------------' '------------------' '----------------'
printf '%-30s %18s %18s %16s\n' 'CPU lógicas' "$B_CPU_COUNT" "$A_CPU_COUNT" "$(signed_int $((A_CPU_COUNT-B_CPU_COUNT)))"
printf '%-30s %18s %18s %16s\n' 'Carga 1 minuto' "$B_LOAD_1" "$A_LOAD_1" 'ver contexto'
printf '%-30s %18s %18s %16s\n' 'Carga 5 minutos' "$B_LOAD_5" "$A_LOAD_5" 'ver contexto'
printf '%-30s %18s %18s %16s\n' 'Memoria usada' "$(human_bytes "$B_MEMORY_USED")" "$(human_bytes "$A_MEMORY_USED")" "$(signed_bytes $((A_MEMORY_USED-B_MEMORY_USED)))"
printf '%-30s %18s %18s %16s\n' 'Memoria disponible' "$(human_bytes "$B_MEMORY_AVAILABLE")" "$(human_bytes "$A_MEMORY_AVAILABLE")" "$(signed_bytes $((A_MEMORY_AVAILABLE-B_MEMORY_AVAILABLE)))"
printf '%-30s %18s %18s %16s\n' 'Swap usada' "$(human_bytes "$B_SWAP_USED")" "$(human_bytes "$A_SWAP_USED")" "$(signed_bytes $((A_SWAP_USED-B_SWAP_USED)))"
printf '%-30s %18s %18s %16s\n' 'Disco raíz usado' "$(human_bytes "$B_ROOT_USED")" "$(human_bytes "$A_ROOT_USED")" "$(signed_bytes $((A_ROOT_USED-B_ROOT_USED)))"
printf '%-30s %18s %18s %16s\n' 'Disco raíz disponible' "$(human_bytes "$B_ROOT_AVAILABLE")" "$(human_bytes "$A_ROOT_AVAILABLE")" "$(signed_bytes $((A_ROOT_AVAILABLE-B_ROOT_AVAILABLE)))"
printf '%-30s %18s %18s %16s\n' 'Disco raíz % usado' "${B_ROOT_PERCENT}%" "${A_ROOT_PERCENT}%" "$(signed_int $((A_ROOT_PERCENT-B_ROOT_PERCENT))) pp"
printf '%-30s %18s %18s %16s\n' 'Contenedores Docker' "$B_DOCKER_CONTAINERS" "$A_DOCKER_CONTAINERS" "$(signed_int $((A_DOCKER_CONTAINERS-B_DOCKER_CONTAINERS)))"
printf '%-30s %18s %18s %16s\n' 'Contenedores ejecutándose' "$B_DOCKER_RUNNING" "$A_DOCKER_RUNNING" "$(signed_int $((A_DOCKER_RUNNING-B_DOCKER_RUNNING)))"
printf '%-30s %18s %18s %16s\n' 'Imágenes Docker' "$B_DOCKER_IMAGES" "$A_DOCKER_IMAGES" "$(signed_int $((A_DOCKER_IMAGES-B_DOCKER_IMAGES)))"
printf '%-30s %18s %18s %16s\n' 'Volúmenes Docker' "$B_DOCKER_VOLUMES" "$A_DOCKER_VOLUMES" "$(signed_int $((A_DOCKER_VOLUMES-B_DOCKER_VOLUMES)))"
printf '%-30s %18s %18s %16s\n' 'Filesystem CI montado' "$B_CI_MOUNTED" "$A_CI_MOUNTED" '-'
printf '%-30s %18s %18s %16s\n' 'Filesystem CI usado' "$(human_bytes "$B_CI_USED")" "$(human_bytes "$A_CI_USED")" "$(signed_bytes $((A_CI_USED-B_CI_USED)))"
printf '%-30s %18s %18s %16s\n' 'Filesystem CI % usado' "${B_CI_PERCENT}%" "${A_CI_PERCENT}%" "$(signed_int $((A_CI_PERCENT-B_CI_PERCENT))) pp"

cat <<'NOTE'

Interpretación:
- Tome los relevamientos con la VM sin jobs de CI y, de ser posible, a una hora de carga comparable.
- La carga y la memoria usada fluctúan naturalmente; el dato más estable es la memoria disponible y el consumo en reposo tras varios minutos.
- El archivo loopback de CI es sparse: el tamaño lógico configurado no equivale necesariamente a espacio físico ya consumido en la raíz.
- Para medir el impacto durante un job, genere un tercer relevamiento con la etiqueta "during-ci" mientras corre el smoke test.
NOTE
