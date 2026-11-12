#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=cleanup-guards.sh
source "${SCRIPT_DIR}/cleanup-guards.sh"

load_env
for command in docker mountpoint findmnt losetup flock readlink; do
  require_command "$command"
done

ci_storage_verified ||
  fatal "CI storage no coincide con la imagen loop esperada: ${CI_STORAGE_ROOT} <- ${CI_STORAGE_IMAGE}"

clear_cache_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  safe_clean_dir "$dir" || {
    warn "Se rechazó la limpieza de una ruta no segura: $dir"
    return 1
  }
}

prune_dind_normal() {
  local dind="$1"

  if ! compose exec -T "$dind" docker info >/dev/null 2>&1; then
    warn "${dind}: Docker CI no responde; se omite prune de este daemon"
    return 0
  fi

  compose exec -T "$dind" docker container prune -f >/dev/null 2>&1 || true
  compose exec -T "$dind" docker network prune -f >/dev/null 2>&1 || true
  compose exec -T "$dind" docker volume prune -f >/dev/null 2>&1 || true
  compose exec -T "$dind" docker image prune -af     --filter "until=${IMAGE_RETENTION_HOURS:-72}h" >/dev/null 2>&1 || true
  compose exec -T "$dind" docker builder prune -af     --keep-storage "${BUILDKIT_CACHE_KEEP:-2GB}" >/dev/null 2>&1 || true
  compose exec -T "$dind" docker buildx prune -af     --max-used-space "${BUILDKIT_CACHE_KEEP:-2GB}" >/dev/null 2>&1 || true
}

prune_dind_aggressive() {
  local dind="$1"

  if ! compose exec -T "$dind" docker info >/dev/null 2>&1; then
    warn "${dind}: Docker CI no responde; se omite prune agresivo"
    return 0
  fi

  compose exec -T "$dind" docker image prune -af --filter 'until=24h' >/dev/null 2>&1 || true
  compose exec -T "$dind" docker builder prune -af     --keep-storage "${BUILDKIT_CACHE_EMERGENCY_KEEP:-512MB}" >/dev/null 2>&1 || true
  compose exec -T "$dind" docker buildx prune -af     --max-used-space "${BUILDKIT_CACHE_EMERGENCY_KEEP:-512MB}" >/dev/null 2>&1 || true
}

recover_paused_runner_if_possible() {
  local runner="$1" marker="$2" usage

  [[ -f "$marker" ]] || return 0
  usage="$(storage_usage_percent)"
  if (( usage <= ${DISK_RECOVERY_PERCENT:-70} )); then
    log "${runner}: almacenamiento recuperado (${usage}%). Reiniciando runner pausado."
    compose up -d "$runner" >/dev/null
    rm -f -- "$marker"
  fi
}

cleanup_heavy_runner_locked() {
  local index="$1"
  local runner="runner-${index}"
  local dind="docker-ci-${index}"
  local cache="${CI_STORAGE_ROOT}/cache-${index}"
  local work="${CI_STORAGE_ROOT}/work-${index}"
  local marker="${CI_STORAGE_ROOT}/.${runner}-paused-disk"
  local activity usage

  activity="$(runner_activity "$runner")"
  if [[ "$activity" != idle ]]; then
    log "${runner}: actividad=${activity}; limpieza destructiva omitida"
    return 0
  fi

  log "${runner}: idle confirmado bajo lease"
  prune_dind_normal "$dind"

  if safe_path_in_ci_storage "$cache"; then
    find "$cache" -type f       -mtime "+${PACKAGE_CACHE_RETENTION_DAYS:-7}"       -delete 2>/dev/null || true
  else
    warn "${runner}: cache fuera del storage verificado; se omite"
  fi

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_AGGRESSIVE_PERCENT:-82} )); then
    log "${runner}: umbral agresivo (${usage}%). Reduciendo cachés y workspace."
    prune_dind_aggressive "$dind"

    if safe_path_in_ci_storage "$work"; then
      find "$work"         -mindepth 1 -maxdepth 1         ! -name '_actions' ! -name '_tool' ! -name '_temp' ! -name '_update' ! -name '_PipelineMapping'         -mtime "+${WORKSPACE_RETENTION_DAYS:-2}"         -exec rm -rf -- {} + 2>/dev/null || true
    else
      warn "${runner}: workspace fuera del storage verificado; se omite"
    fi

    clear_cache_dir "$cache/npm"
    clear_cache_dir "$cache/pip"
    clear_cache_dir "$cache/nuget"
  fi

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
    warn "${runner}: emergencia de disco (${usage}%). Limpiando toolcache antes de pausar."
    clear_cache_dir "$cache/toolcache"
    usage="$(storage_usage_percent)"
    if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
      warn "${runner}: uso ${usage}% después de reclaim; se pausa el listener idle"
      compose stop "$runner" >/dev/null 2>&1 || true
      touch "$marker"
    fi
  fi
}

cleanup_heavy_runner() {
  local index="$1" runner marker rc
  runner="runner-${index}"
  marker="${CI_STORAGE_ROOT}/.${runner}-paused-disk"

  recover_paused_runner_if_possible "$runner" "$marker"

  if with_runner_lease "$runner" cleanup_heavy_runner_locked "$index"; then
    return 0
  fi

  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    log "${runner}: lease ocupado por hook/job; se omite este ciclo"
    return 0
  fi

  warn "${runner}: no se pudo ejecutar cleanup bajo lease (rc=${rc})"
  return "$rc"
}

cleanup_gate_locked() {
  local runner=runner-04
  local cache="${CI_STORAGE_ROOT}/cache-04"
  local work="${CI_STORAGE_ROOT}/work-04"
  local activity usage

  activity="$(runner_activity "$runner")"
  if [[ "$activity" != idle ]]; then
    log "${runner}: actividad=${activity}; limpieza destructiva omitida"
    return 0
  fi

  log "${runner}: idle confirmado bajo lease (Gate sin DinD)"

  if safe_path_in_ci_storage "$cache"; then
    find "$cache" -type f       -mtime "+${PACKAGE_CACHE_RETENTION_DAYS:-7}"       -delete 2>/dev/null || true
  fi

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_AGGRESSIVE_PERCENT:-82} )); then
    if safe_path_in_ci_storage "$work"; then
      find "$work"         -mindepth 1 -maxdepth 1         ! -name '_actions' ! -name '_tool' ! -name '_temp' ! -name '_update' ! -name '_PipelineMapping'         -mtime "+${WORKSPACE_RETENTION_DAYS:-2}"         -exec rm -rf -- {} + 2>/dev/null || true
    fi
    clear_cache_dir "$cache/npm"
    clear_cache_dir "$cache/pip"
    clear_cache_dir "$cache/nuget"

    usage="$(storage_usage_percent)"
    if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
      clear_cache_dir "$cache/toolcache"
    fi
  fi
}

cleanup_gate() {
  local rc
  if with_runner_lease runner-04 cleanup_gate_locked; then
    return 0
  fi

  rc=$?
  if [[ "$rc" -eq 75 ]]; then
    log "runner-04: lease ocupado por hook/job; se omite este ciclo"
    return 0
  fi

  warn "runner-04: no se pudo ejecutar cleanup bajo lease (rc=${rc})"
  return "$rc"
}

run_cleanup() {
  local usage_before usage_after dind

  usage_before="$(storage_usage_percent)"
  log "Limpieza iniciada. Uso=${usage_before}%"

  # Safe on the host: Docker will not remove images referenced by running containers.
  docker image prune -af     --filter 'label=io.coferlandia.ci=true'     --filter "until=${IMAGE_RETENTION_HOURS:-72}h" >/dev/null 2>&1 || true

  for index in 01 02 03; do
    cleanup_heavy_runner "$index"
  done
  cleanup_gate

  usage_after="$(storage_usage_percent)"
  log "Limpieza terminada. Uso antes=${usage_before}% después=${usage_after}%"

  for dind in "${DIND_SERVICES[@]}"; do
    printf '\n%s:\n' "$dind"
    compose exec -T "$dind" docker system df 2>/dev/null || true
  done
}

if with_cleanup_lock run_cleanup; then
  exit 0
fi

rc=$?
if [[ "$rc" -eq 75 ]]; then
  log "Otro cleanup ya está ejecutándose; este ciclo se omite"
  exit 0
fi

fatal "Cleanup falló (rc=${rc})"
