#!/usr/bin/env bash
set -uo pipefail

cache_log() {
  printf '[cache-pressure] %s\n' "$*"
}

ci_storage_usage_percent() {
  df -P /cache 2>/dev/null | awk 'NR == 2 {gsub(/%/, "", $5); print $5}'
}

clear_dir_contents() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

reclaim_runner_cache_if_needed() {
  local reason="${1:-job}"
  local pressure="${RUNNER_CACHE_PRESSURE_PERCENT:-78}"
  local emergency="${RUNNER_CACHE_EMERGENCY_PERCENT:-88}"
  local usage

  usage="$(ci_storage_usage_percent)"
  [[ "$usage" =~ ^[0-9]+$ ]] || {
    cache_log "No se pudo medir el filesystem de /cache; se omite limpieza preventiva"
    return 0
  }

  if (( usage < pressure )); then
    cache_log "Uso ${usage}% (< ${pressure}%); no hace falta limpiar caches"
    return 0
  fi

  cache_log "${reason}: uso ${usage}% >= ${pressure}%; limpiando caches regenerables npm/pip/nuget"
  clear_dir_contents /cache/npm
  clear_dir_contents /cache/pip
  clear_dir_contents /cache/nuget

  usage="$(ci_storage_usage_percent)"
  if [[ "$usage" =~ ^[0-9]+$ ]] && (( usage >= emergency )); then
    cache_log "${reason}: uso ${usage}% >= ${emergency}%; limpiando también toolcache regenerable"
    clear_dir_contents /cache/toolcache
    usage="$(ci_storage_usage_percent)"
  fi

  cache_log "${reason}: uso después de limpieza ${usage:-desconocido}%"
  df -h /cache 2>/dev/null || true
}
