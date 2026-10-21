#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

load_env
require_command docker
mountpoint -q "${CI_STORAGE_ROOT}" || fatal "${CI_STORAGE_ROOT} no está montado"

clear_cache_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

usage_before="$(storage_usage_percent)"
log "Limpieza iniciada. Uso=${usage_before}%"

docker image prune -af   --filter 'label=io.coferlandia.ci=true'   --filter "until=${IMAGE_RETENTION_HOURS:-72}h"   >/dev/null 2>&1 || true

for index in 01 02 03; do
  runner="runner-${index}"
  dind="docker-ci-${index}"
  cache="${CI_STORAGE_ROOT}/cache-${index}"
  work="${CI_STORAGE_ROOT}/work-${index}"
  marker="${CI_STORAGE_ROOT}/.${runner}-paused-disk"
  busy=false
  runner_is_busy "$runner" && busy=true

  log "${runner}: busy=${busy}"

  compose exec -T "$dind" docker container prune -f >/dev/null 2>&1 || true
  compose exec -T "$dind" docker network prune -f >/dev/null 2>&1 || true
  compose exec -T "$dind" docker volume prune -f >/dev/null 2>&1 || true
  compose exec -T "$dind" docker image prune -af     --filter "until=${IMAGE_RETENTION_HOURS:-72}h"     >/dev/null 2>&1 || true
  compose exec -T "$dind" docker builder prune -af     --keep-storage "${BUILDKIT_CACHE_KEEP:-2GB}"     >/dev/null 2>&1 || true
  compose exec -T "$dind" docker buildx prune -af     --max-used-space "${BUILDKIT_CACHE_KEEP:-2GB}"     >/dev/null 2>&1 || true

  if [[ "$busy" == false ]]; then
    find "$cache" -type f       -mtime "+${PACKAGE_CACHE_RETENTION_DAYS:-7}"       -delete 2>/dev/null || true
  fi

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_AGGRESSIVE_PERCENT:-82} )) && [[ "$busy" == false ]]; then
    log "${runner}: umbral agresivo (${usage}%). Reduciendo cachés y workspace."

    compose exec -T "$dind" docker image prune -af       --filter 'until=24h' >/dev/null 2>&1 || true
    compose exec -T "$dind" docker builder prune -af       --keep-storage "${BUILDKIT_CACHE_EMERGENCY_KEEP:-512MB}"       >/dev/null 2>&1 || true
    compose exec -T "$dind" docker buildx prune -af       --max-used-space "${BUILDKIT_CACHE_EMERGENCY_KEEP:-512MB}"       >/dev/null 2>&1 || true

    find "$work"       -mindepth 1 -maxdepth 1       ! -name '_actions' ! -name '_tool' ! -name '_temp'       -mtime "+${WORKSPACE_RETENTION_DAYS:-2}"       -exec rm -rf -- {} + 2>/dev/null || true

    clear_cache_dir "$cache/npm"
    clear_cache_dir "$cache/pip"
    clear_cache_dir "$cache/nuget"
  fi

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )) && [[ "$busy" == false ]]; then
    warn "${runner}: emergencia de disco (${usage}%). Limpiando toolcache antes de pausar."
    clear_cache_dir "$cache/toolcache"
    usage="$(storage_usage_percent)"
    warn "${runner}: uso tras toolcache=${usage}%. Se pausa este runner si sigue en emergencia."
    if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
      compose stop "$runner" >/dev/null 2>&1 || true
      touch "$marker"
    fi
  elif [[ -f "$marker" ]] && (( usage <= ${DISK_RECOVERY_PERCENT:-70} )); then
    log "${runner}: almacenamiento recuperado (${usage}%). Reiniciando."
    compose up -d "$runner" >/dev/null
    rm -f "$marker"
  fi
done

usage_after="$(storage_usage_percent)"
log "Limpieza terminada. Uso antes=${usage_before}% después=${usage_after}%"

for dind in "${DIND_SERVICES[@]}"; do
  printf '\n%s:\n' "$dind"
  compose exec -T "$dind" docker system df 2>/dev/null || true
done


# The Gate runner has no Docker daemon. Only its package cache/workspace require retention.
gate_runner="runner-04"
gate_cache="${CI_STORAGE_ROOT}/cache-04"
gate_work="${CI_STORAGE_ROOT}/work-04"
gate_busy=false
runner_is_busy "$gate_runner" && gate_busy=true
log "${gate_runner}: busy=${gate_busy} (lightweight Gate lane)"
if [[ "$gate_busy" == false ]]; then
  find "$gate_cache" -type f -mtime "+${PACKAGE_CACHE_RETENTION_DAYS:-7}" -delete 2>/dev/null || true
  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_AGGRESSIVE_PERCENT:-82} )); then
    find "$gate_work" -mindepth 1 -maxdepth 1 ! -name '_actions' ! -name '_tool' ! -name '_temp' -mtime "+${WORKSPACE_RETENTION_DAYS:-2}" -exec rm -rf -- {} + 2>/dev/null || true
    clear_cache_dir "$gate_cache/npm"
    clear_cache_dir "$gate_cache/pip"
    clear_cache_dir "$gate_cache/nuget"
    usage="$(storage_usage_percent)"
    if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
      clear_cache_dir "$gate_cache/toolcache"
    fi
  fi
fi
