#!/usr/bin/env bash
#
# vm-storage-audit.sh
#
# Relevamiento y limpieza conservadora de almacenamiento para la VM de Coferlandia.
#
# Uso:
#   ./vm-storage-audit.sh audit
#   ./vm-storage-audit.sh clean
#   ./vm-storage-audit.sh audit-clean
#
# Variables opcionales:
#   AUDIT_DIR="$HOME/vm-storage-audits"
#   SECTION_TIMEOUT=90
#
# La limpieza conservadora NO elimina:
#   - volúmenes Docker
#   - imágenes Docker en uso
#   - contenedores detenidos
#   - datos de aplicaciones
#

set -uo pipefail

MODE="${1:-audit}"
AUDIT_DIR="${AUDIT_DIR:-$HOME/vm-storage-audits}"
SECTION_TIMEOUT="${SECTION_TIMEOUT:-90}"

case "$MODE" in
  audit|clean|audit-clean) ;;
  *)
    echo "Uso: $0 [audit|clean|audit-clean]" >&2
    exit 2
    ;;
esac

for command_name in timeout df du sort awk sed grep find numfmt docker; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Falta el comando requerido: $command_name" >&2
    exit 1
  fi
done

mkdir -p "$AUDIT_DIR"

HOST_NAME="$(hostname)"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$AUDIT_DIR/${STAMP}-${HOST_NAME}-${MODE}.txt"
METRICS="$AUDIT_DIR/${STAMP}-${HOST_NAME}-${MODE}.metrics"

sudo -v
(
  while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" 2>/dev/null || exit
  done
) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

cleanup_keepalive() {
  kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}
trap cleanup_keepalive EXIT INT TERM

exec > >(tee -a "$REPORT") 2>&1

print_header() {
  local title="$1"
  echo
  echo "============================================================"
  echo "$title"
  echo "============================================================"
}

run_shell() {
  local title="$1"
  local seconds="$2"
  local command_text="$3"

  print_header "$title"
  echo "[inicio] $(date --iso-8601=seconds)"
  echo "[timeout] ${seconds}s"

  if timeout --foreground "${seconds}s" bash -lc "$command_text"; then
    echo "[resultado] OK"
  else
    local status=$?
    if [[ "$status" -eq 124 ]]; then
      echo "[resultado] TIMEOUT después de ${seconds}s"
    else
      echo "[resultado] ERROR, código $status"
    fi
  fi

  echo "[fin] $(date --iso-8601=seconds)"
}

bytes_for_path() {
  local path="$1"
  local seconds="${2:-$SECTION_TIMEOUT}"

  if [[ ! -e "$path" ]]; then
    printf '%-32s %s\n' "$path" "no existe"
    return 0
  fi

  printf '%-32s ' "$path"

  local output
  if output="$(timeout --foreground "${seconds}s" sudo du -sxB1 "$path" 2>/dev/null)"; then
    local bytes
    bytes="$(awk '{print $1}' <<<"$output")"
    numfmt --to=iec-i --suffix=B "$bytes"
  else
    local status=$?
    if [[ "$status" -eq 124 ]]; then
      echo "TIMEOUT (${seconds}s)"
    else
      echo "ERROR ($status)"
    fi
  fi
}

write_metrics() {
  {
    echo "timestamp=$(date --iso-8601=seconds)"
    echo "hostname=$HOST_NAME"
    echo "mode=$MODE"
    echo "root_total_bytes=$(df -B1 --output=size / | tail -n1 | tr -d ' ')"
    echo "root_used_bytes=$(df -B1 --output=used / | tail -n1 | tr -d ' ')"
    echo "root_available_bytes=$(df -B1 --output=avail / | tail -n1 | tr -d ' ')"
    echo "root_used_percent=$(df --output=pcent / | tail -n1 | tr -dc '0-9')"
    echo "memory_total_bytes=$(awk '/MemTotal:/ {print $2 * 1024}' /proc/meminfo | awk '{printf \"%.0f\", $1}')"
    echo "memory_available_bytes=$(awk '/MemAvailable:/ {print $2 * 1024}' /proc/meminfo | awk '{printf \"%.0f\", $1}')"
    echo "swap_total_bytes=$(awk '/SwapTotal:/ {print $2 * 1024}' /proc/meminfo | awk '{printf \"%.0f\", $1}')"
    echo "swap_free_bytes=$(awk '/SwapFree:/ {print $2 * 1024}' /proc/meminfo | awk '{printf \"%.0f\", $1}')"
    echo "docker_containers_total=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
    echo "docker_containers_running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    echo "docker_images_total=$(docker image ls -q 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    echo "docker_volumes_total=$(docker volume ls -q 2>/dev/null | wc -l | tr -d ' ')"
  } > "$METRICS"
}

audit_system() {
  print_header "RELEVAMIENTO DE ALMACENAMIENTO"
  echo "Fecha:        $(date --iso-8601=seconds)"
  echo "Host:         $HOST_NAME"
  echo "Modo:         $MODE"
  echo "Arquitectura: $(uname -m)"
  echo "Kernel:       $(uname -r)"
  echo "Informe:      $REPORT"
  echo "Métricas:     $METRICS"

  run_shell "FILESYSTEMS E INODOS" 30 \
    'df -hT; echo; df -ih'

  run_shell "MEMORIA, CPU Y CARGA" 30 \
    'nproc; echo; free -h; echo; uptime; echo; ps -eo pid,user,comm,%cpu,%mem,rss --sort=-rss | head -n 25'

  print_header "TAMAÑO DE DIRECTORIOS IMPORTANTES"
  echo "Cada directorio tiene timeout individual para evitar bloqueos."
  echo
  bytes_for_path "/home" 60
  bytes_for_path "/home/ubuntu" 60
  bytes_for_path "/opt" 45
  bytes_for_path "/srv" 45
  bytes_for_path "/tmp" 30
  bytes_for_path "/var/log" 45
  bytes_for_path "/var/cache" 45
  bytes_for_path "/var/backups" 30
  bytes_for_path "/var/lib/apt" 45
  bytes_for_path "/var/lib/snapd" 60
  bytes_for_path "/var/lib/docker" 90
  bytes_for_path "/var/lib/containerd" 90

  run_shell "SUBDIRECTORIOS GRANDES DE /home/ubuntu" 75 \
    'sudo du -xB1 --max-depth=2 /home/ubuntu 2>/dev/null | sort -nr | head -n 80 | numfmt --field=1 --to=iec-i --suffix=B'

  run_shell "SUBDIRECTORIOS GRANDES DE /var/log" 60 \
    'sudo du -xB1 --max-depth=2 /var/log 2>/dev/null | sort -nr | head -n 80 | numfmt --field=1 --to=iec-i --suffix=B'

  run_shell "SUBDIRECTORIOS DE /var SIN ESCANEAR DATOS PESADOS DE DOCKER" 90 \
    'sudo du -xB1 --max-depth=2 \
      --exclude=/var/lib/docker \
      --exclude=/var/lib/containerd \
      /var 2>/dev/null | sort -nr | head -n 100 | numfmt --field=1 --to=iec-i --suffix=B'

  run_shell "DOCKER: RESUMEN DE USO" 60 \
    'docker system df'

  run_shell "DOCKER: DETALLE DE USO" 120 \
    'docker system df -v'

  run_shell "DOCKER: CONTENEDORES Y CAPA ESCRIBIBLE" 60 \
    'docker ps -a --size --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Size}}"'

  run_shell "DOCKER: IMÁGENES" 60 \
    'docker image ls --digests --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"'

  run_shell "DOCKER: CACHÉ DEL BUILDER" 90 \
    'docker builder du 2>&1 || true; echo; docker buildx du 2>&1 || true'

  run_shell "DOCKER: VOLÚMENES Y CONTENEDORES QUE LOS USAN" 90 \
    'for volume in $(docker volume ls -q); do
       echo
       echo "=== $volume ==="
       docker ps -a --filter volume="$volume" \
         --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
     done'

  run_shell "DOCKER: TAMAÑO REAL DE VOLÚMENES" 150 \
    'while read -r volume; do
       mountpoint="$(docker volume inspect --format "{{.Mountpoint}}" "$volume" 2>/dev/null)"
       if [[ -n "$mountpoint" && -d "$mountpoint" ]]; then
         bytes="$(sudo du -sxB1 "$mountpoint" 2>/dev/null | awk "{print \\$1}")"
         printf "%s\t%s\t%s\n" "${bytes:-0}" "$volume" "$mountpoint"
       fi
     done < <(docker volume ls -q) |
       sort -nr |
       numfmt --field=1 --to=iec-i --suffix=B'

  run_shell "LOGS JSON DE CONTENEDORES MÁS GRANDES" 60 \
    'sudo find /var/lib/docker/containers \
       -type f -name "*-json.log" \
       -printf "%s\t%p\n" 2>/dev/null |
       sort -nr |
       head -n 40 |
       numfmt --field=1 --to=iec-i --suffix=B'

  run_shell "JOURNAL DE SYSTEMD" 30 \
    'sudo journalctl --disk-usage'

  run_shell "SNAPS INSTALADOS Y REVISIONES ANTIGUAS" 45 \
    'if command -v snap >/dev/null 2>&1; then
       snap list --all
       echo
       sudo du -sh /var/lib/snapd/snaps 2>/dev/null || true
     else
       echo "snap no está instalado"
     fi'

  run_shell "ARCHIVOS GRANDES EN RUTAS DE USUARIO Y LOGS" 120 \
    'sudo find /home /opt /srv /var/log /var/backups /tmp \
       -xdev -type f -size +500M \
       -printf "%s\t%p\n" 2>/dev/null |
       sort -nr |
       head -n 80 |
       numfmt --field=1 --to=iec-i --suffix=B'

  run_shell "ARCHIVOS ELIMINADOS QUE SIGUEN ABIERTOS" 45 \
    'if command -v lsof >/dev/null 2>&1; then
       sudo lsof +L1
     else
       echo "lsof no está instalado. Para agregarlo: sudo apt install -y lsof"
     fi'

  run_shell "SERVICIOS FALLIDOS Y PUERTOS" 45 \
    'systemctl --failed --no-pager || true; echo; sudo ss -tulpen'

  write_metrics

  print_header "RESUMEN"
  df -h /
  echo
  docker system df || true
  echo
  sudo journalctl --disk-usage || true
}

safe_cleanup() {
  print_header "LIMPIEZA CONSERVADORA"
  echo "Esta limpieza NO elimina volúmenes Docker, contenedores detenidos ni imágenes en uso."
  echo

  echo "[1/6] Limpiando caché de APT..."
  sudo apt clean
  sudo apt autoclean

  echo "[2/6] Rotando y reduciendo journal a 14 días / 500 MB..."
  sudo journalctl --rotate
  sudo journalctl --vacuum-time=14d --vacuum-size=500M

  echo "[3/6] Eliminando imágenes Docker dangling..."
  docker image prune -f

  echo "[4/6] Eliminando caché clásica de builds con más de 7 días..."
  docker builder prune -f --filter 'until=168h' || true

  echo "[5/6] Eliminando caché Buildx con más de 7 días..."
  docker buildx prune -f --filter 'until=168h' || true

  echo "[6/6] Eliminando redes Docker no utilizadas..."
  docker network prune -f

  print_header "RESULTADO DE LA LIMPIEZA"
  df -h /
  echo
  docker system df
  echo
  sudo journalctl --disk-usage
}

case "$MODE" in
  audit)
    audit_system
    ;;
  clean)
    safe_cleanup
    ;;
  audit-clean)
    echo "Se generará un relevamiento, se aplicará limpieza conservadora y se generará otro relevamiento."
    audit_system

    BEFORE_REPORT="$REPORT"
    BEFORE_METRICS="$METRICS"

    safe_cleanup

    STAMP="$(date +%Y%m%d-%H%M%S)"
    REPORT="$AUDIT_DIR/${STAMP}-${HOST_NAME}-after-clean.txt"
    METRICS="$AUDIT_DIR/${STAMP}-${HOST_NAME}-after-clean.metrics"

    exec > >(tee -a "$REPORT") 2>&1
    audit_system

    print_header "ARCHIVOS GENERADOS"
    echo "Antes:          $BEFORE_REPORT"
    echo "Métricas antes: $BEFORE_METRICS"
    echo "Después:        $REPORT"
    echo "Métricas desp.: $METRICS"
    ;;
esac

echo
echo "Proceso terminado."
echo "Informe principal: $REPORT"
echo "Métricas:          $METRICS"
