#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

LABEL="${1:-manual}"
OUTPUT_DIR="${2:-${PROJECT_DIR}/reports/host-surveys}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
HOST="$(hostname -s 2>/dev/null || hostname)"
BASE_NAME="${TIMESTAMP}-${HOST}-${LABEL}"
REPORT_FILE="${OUTPUT_DIR}/${BASE_NAME}.txt"
METRICS_FILE="${OUTPUT_DIR}/${BASE_NAME}.metrics"

mkdir -p "$OUTPUT_DIR"

have() {
  command -v "$1" >/dev/null 2>&1
}

metric() {
  printf '%s=%q\n' "$1" "$2" >> "$METRICS_FILE"
}

section() {
  printf '\n================================================================================\n'
  printf '%s\n' "$1"
  printf '================================================================================\n'
}

bytes_human() {
  local value="${1:-0}"
  if have numfmt; then
    numfmt --to=iec-i --suffix=B "$value" 2>/dev/null || printf '%s B' "$value"
  else
    printf '%s B' "$value"
  fi
}

: > "$METRICS_FILE"

CPU_COUNT="$(nproc 2>/dev/null || echo 0)"
LOAD_1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo n/a)"
LOAD_5="$(awk '{print $2}' /proc/loadavg 2>/dev/null || echo n/a)"
LOAD_15="$(awk '{print $3}' /proc/loadavg 2>/dev/null || echo n/a)"
UPTIME_SECONDS="$(awk '{printf "%.0f", $1}' /proc/uptime 2>/dev/null || echo 0)"

if have free; then
  read -r MEM_TOTAL MEM_USED MEM_FREE MEM_SHARED MEM_BUFF_CACHE MEM_AVAILABLE < <(free -b | awk '/^Mem:/ {print $2,$3,$4,$5,$6,$7}')
  read -r SWAP_TOTAL SWAP_USED SWAP_FREE < <(free -b | awk '/^Swap:/ {print $2,$3,$4}')
else
  MEM_TOTAL=0; MEM_USED=0; MEM_FREE=0; MEM_SHARED=0; MEM_BUFF_CACHE=0; MEM_AVAILABLE=0
  SWAP_TOTAL=0; SWAP_USED=0; SWAP_FREE=0
fi

read -r ROOT_SIZE ROOT_USED ROOT_AVAILABLE ROOT_PERCENT ROOT_TARGET < <(df -B1 --output=size,used,avail,pcent,target / | tail -n1)
ROOT_PERCENT="${ROOT_PERCENT%%%}"

CI_STORAGE_ROOT="/srv/coferlandia-ci"
if [[ -f "${PROJECT_DIR}/.env" ]]; then
  # Only read the storage path; do not source the whole file into this diagnostic script.
  configured_root="$(awk -F= '/^CI_STORAGE_ROOT=/ {sub(/^[^=]*=/, ""); print; exit}' "${PROJECT_DIR}/.env")"
  [[ -n "$configured_root" ]] && CI_STORAGE_ROOT="$configured_root"
fi

CI_MOUNTED=false
CI_SIZE=0; CI_USED=0; CI_AVAILABLE=0; CI_PERCENT=0
if mountpoint -q "$CI_STORAGE_ROOT" 2>/dev/null; then
  CI_MOUNTED=true
  read -r CI_SIZE CI_USED CI_AVAILABLE CI_PERCENT _ < <(df -B1 --output=size,used,avail,pcent,target "$CI_STORAGE_ROOT" | tail -n1)
  CI_PERCENT="${CI_PERCENT%%%}"
fi

DOCKER_AVAILABLE=false
DOCKER_VERSION="n/a"
DOCKER_CONTAINERS=0
DOCKER_RUNNING=0
DOCKER_PAUSED=0
DOCKER_STOPPED=0
DOCKER_IMAGES=0
DOCKER_VOLUMES=0
if have docker && docker info >/dev/null 2>&1; then
  DOCKER_AVAILABLE=true
  DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"
  DOCKER_CONTAINERS="$(docker info --format '{{.Containers}}' 2>/dev/null || echo 0)"
  DOCKER_RUNNING="$(docker info --format '{{.ContainersRunning}}' 2>/dev/null || echo 0)"
  DOCKER_PAUSED="$(docker info --format '{{.ContainersPaused}}' 2>/dev/null || echo 0)"
  DOCKER_STOPPED="$(docker info --format '{{.ContainersStopped}}' 2>/dev/null || echo 0)"
  DOCKER_IMAGES="$(docker info --format '{{.Images}}' 2>/dev/null || echo 0)"
  DOCKER_VOLUMES="$(docker volume ls -q 2>/dev/null | wc -l | tr -d ' ')"
fi

metric survey_label "$LABEL"
metric survey_timestamp "$(date --iso-8601=seconds)"
metric hostname "$HOST"
metric cpu_count "$CPU_COUNT"
metric load_1 "$LOAD_1"
metric load_5 "$LOAD_5"
metric load_15 "$LOAD_15"
metric uptime_seconds "$UPTIME_SECONDS"
metric memory_total_bytes "$MEM_TOTAL"
metric memory_used_bytes "$MEM_USED"
metric memory_available_bytes "$MEM_AVAILABLE"
metric swap_total_bytes "$SWAP_TOTAL"
metric swap_used_bytes "$SWAP_USED"
metric root_size_bytes "$ROOT_SIZE"
metric root_used_bytes "$ROOT_USED"
metric root_available_bytes "$ROOT_AVAILABLE"
metric root_used_percent "$ROOT_PERCENT"
metric ci_storage_root "$CI_STORAGE_ROOT"
metric ci_mounted "$CI_MOUNTED"
metric ci_size_bytes "$CI_SIZE"
metric ci_used_bytes "$CI_USED"
metric ci_available_bytes "$CI_AVAILABLE"
metric ci_used_percent "$CI_PERCENT"
metric docker_available "$DOCKER_AVAILABLE"
metric docker_version "$DOCKER_VERSION"
metric docker_containers "$DOCKER_CONTAINERS"
metric docker_running "$DOCKER_RUNNING"
metric docker_paused "$DOCKER_PAUSED"
metric docker_stopped "$DOCKER_STOPPED"
metric docker_images "$DOCKER_IMAGES"
metric docker_volumes "$DOCKER_VOLUMES"

{
  printf 'Coferlandia VM host survey\n'
  printf 'Etiqueta: %s\n' "$LABEL"
  printf 'Fecha:    %s\n' "$(date --iso-8601=seconds)"
  printf 'Host:     %s\n' "$HOST"

  section '1. Sistema operativo y kernel'
  if [[ -r /etc/os-release ]]; then
    cat /etc/os-release
  fi
  printf '\nKernel y arquitectura:\n'
  uname -a
  printf '\nUptime:\n'
  uptime || true

  section '2. CPU y carga'
  printf 'CPU lógicas: %s\n' "$CPU_COUNT"
  printf 'Carga 1/5/15 min: %s / %s / %s\n' "$LOAD_1" "$LOAD_5" "$LOAD_15"
  if have lscpu; then
    lscpu
  fi

  section '3. Memoria y swap'
  free -h || true
  printf '\nResumen en bytes:\n'
  printf 'Memoria total:      %s\n' "$(bytes_human "$MEM_TOTAL")"
  printf 'Memoria usada:      %s\n' "$(bytes_human "$MEM_USED")"
  printf 'Memoria disponible: %s\n' "$(bytes_human "$MEM_AVAILABLE")"
  printf 'Swap total:         %s\n' "$(bytes_human "$SWAP_TOTAL")"
  printf 'Swap usada:         %s\n' "$(bytes_human "$SWAP_USED")"

  section '4. Filesystems, espacio e inodos'
  df -hT
  printf '\nInodos:\n'
  df -hi
  printf '\nMontajes relevantes:\n'
  findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || mount
  printf '\nFilesystem raíz: %s usados; %s disponibles; %s%%\n' \
    "$(bytes_human "$ROOT_USED")" "$(bytes_human "$ROOT_AVAILABLE")" "$ROOT_PERCENT"
  if [[ "$CI_MOUNTED" == true ]]; then
    printf 'Filesystem CI:   %s usados; %s disponibles; %s%% en %s\n' \
      "$(bytes_human "$CI_USED")" "$(bytes_human "$CI_AVAILABLE")" "$CI_PERCENT" "$CI_STORAGE_ROOT"
  else
    printf 'Filesystem CI:   todavía no montado en %s\n' "$CI_STORAGE_ROOT"
  fi

  section '5. Discos y dispositivos de bloque'
  if have lsblk; then
    lsblk -o NAME,TYPE,SIZE,FSTYPE,FSAVAIL,FSUSE%,MOUNTPOINTS
  fi

  section '6. Docker del host'
  if [[ "$DOCKER_AVAILABLE" == true ]]; then
    printf 'Docker Server: %s\n' "$DOCKER_VERSION"
    docker info
    printf '\nUso de almacenamiento Docker:\n'
    docker system df
    printf '\nContenedores:\n'
    docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    printf '\nConsumo actual de contenedores:\n'
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}' || true
    printf '\nVolúmenes Docker:\n'
    docker volume ls
    printf '\nRedes Docker:\n'
    docker network ls
  else
    printf 'Docker no está instalado, no responde o el usuario actual no tiene permisos.\n'
  fi

  section '7. Procesos con mayor consumo'
  printf 'Por CPU:\n'
  ps -eo pid,user,comm,%cpu,%mem,rss --sort=-%cpu | head -n 16 || true
  printf '\nPor memoria:\n'
  ps -eo pid,user,comm,%cpu,%mem,rss --sort=-rss | head -n 16 || true

  section '8. Puertos en escucha'
  if have ss; then
    ss -tulpen || true
  elif have netstat; then
    netstat -tulpen || true
  else
    printf 'No se encontró ss ni netstat.\n'
  fi

  section '9. Estado de servicios base'
  if have systemctl; then
    systemctl is-active docker 2>/dev/null | sed 's/^/docker: /' || true
    systemctl --failed --no-pager 2>/dev/null || true
  fi

  section '10. Resumen medible'
  printf 'CPU lógicas:             %s\n' "$CPU_COUNT"
  printf 'Carga 1/5/15:            %s / %s / %s\n' "$LOAD_1" "$LOAD_5" "$LOAD_15"
  printf 'Memoria usada:           %s\n' "$(bytes_human "$MEM_USED")"
  printf 'Memoria disponible:      %s\n' "$(bytes_human "$MEM_AVAILABLE")"
  printf 'Raíz usada/disponible:   %s / %s (%s%%)\n' "$(bytes_human "$ROOT_USED")" "$(bytes_human "$ROOT_AVAILABLE")" "$ROOT_PERCENT"
  printf 'Docker contenedores:     %s total, %s ejecutándose\n' "$DOCKER_CONTAINERS" "$DOCKER_RUNNING"
  printf 'Docker imágenes:         %s\n' "$DOCKER_IMAGES"
  printf 'Docker volúmenes:        %s\n' "$DOCKER_VOLUMES"
  printf 'Filesystem CI montado:   %s\n' "$CI_MOUNTED"
  if [[ "$CI_MOUNTED" == true ]]; then
    printf 'Filesystem CI usado:     %s (%s%%)\n' "$(bytes_human "$CI_USED")" "$CI_PERCENT"
  fi

  section '11. Archivos generados'
  printf 'Informe:  %s\n' "$REPORT_FILE"
  printf 'Métricas: %s\n' "$METRICS_FILE"
} > "$REPORT_FILE"

printf 'Relevamiento generado:\n  %s\n  %s\n' "$REPORT_FILE" "$METRICS_FILE"
