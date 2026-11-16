#!/usr/bin/env bash
set -uo pipefail

cache_log() {
  printf '[cache-pressure] %s\n' "$*"
}

runner_cache_root() {
  printf '%s' "${RUNNER_CACHE_ROOT:-/cache}"
}

ci_storage_usage_percent() {
  local root
  root="$(runner_cache_root)"
  df -P "$root" 2>/dev/null | awk 'NR == 2 {gsub(/%/, "", $5); print $5}'
}

clear_dir_contents() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

clear_runner_tmp() {
  local reason="${1:-job}" root
  root="$(runner_cache_root)"
  mkdir -p "$root/tmp"
  clear_dir_contents "$root/tmp"
  cache_log "${reason}: temporales regenerables limpiados en ${root}/tmp"
}

reclaim_runner_cache_if_needed() {
  local reason="${1:-job}"
  local pressure="${RUNNER_CACHE_PRESSURE_PERCENT:-78}"
  local emergency="${RUNNER_CACHE_EMERGENCY_PERCENT:-88}"
  local root usage

  root="$(runner_cache_root)"
  usage="$(ci_storage_usage_percent)"
  [[ "$usage" =~ ^[0-9]+$ ]] || {
    cache_log "No se pudo medir el filesystem de ${root}; se omite limpieza preventiva"
    return 0
  }

  if (( usage < pressure )); then
    cache_log "Uso ${usage}% (< ${pressure}%); no hace falta limpiar caches"
    return 0
  fi

  cache_log "${reason}: uso ${usage}% >= ${pressure}%; limpiando caches regenerables npm/pip/nuget"
  clear_dir_contents "$root/npm"
  clear_dir_contents "$root/pip"
  clear_dir_contents "$root/nuget"

  usage="$(ci_storage_usage_percent)"
  if [[ "$usage" =~ ^[0-9]+$ ]] && (( usage >= emergency )); then
    cache_log "${reason}: uso ${usage}% >= ${emergency}%; limpiando también toolcache regenerable"
    clear_dir_contents "$root/toolcache"
    usage="$(ci_storage_usage_percent)"
  fi

  cache_log "${reason}: uso después de limpieza ${usage:-desconocido}%"
  df -h "$root" 2>/dev/null || true
}
