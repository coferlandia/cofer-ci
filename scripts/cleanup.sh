#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=cleanup-guards.sh
source "${SCRIPT_DIR}/cleanup-guards.sh"
# shellcheck source=storage-policy.sh
source "${SCRIPT_DIR}/storage-policy.sh"
# shellcheck source=loop-maintenance.sh
source "${SCRIPT_DIR}/loop-maintenance.sh"

CLEANUP_DRY_RUN=false
case "${1:-}" in
  "")
    ;;
  --dry-run)
    CLEANUP_DRY_RUN=true
    ;;
  *)
    printf 'Uso: %s [--dry-run]\n' "$0" >&2
    exit 64
    ;;
esac
export CLEANUP_DRY_RUN

load_env
for command in docker mountpoint findmnt losetup flock readlink; do
  require_command "$command"
done

ci_storage_verified ||
  fatal "CI storage no coincide con la imagen loop esperada: ${CI_STORAGE_ROOT} <- ${CI_STORAGE_IMAGE}"

clear_cache_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  if [[ "$CLEANUP_DRY_RUN" == true ]]; then
    safe_clean_dir "$dir" --dry-run || {
      warn "Se rechazó la previsualización de una ruta no segura: $dir"
      return 1
    }
  else
    safe_clean_dir "$dir" || {
      warn "Se rechazó la limpieza de una ruta no segura: $dir"
      return 1
    }
  fi
}

runner_idle_now() {
  local runner="$1" activity
  activity="$(runner_activity "$runner")"
  if [[ "$activity" != idle ]]; then
    log "${runner}: actividad=${activity}; operación destructiva omitida"
    return 1
  fi
  return 0
}

workspace_policy_values() {
  local budget retention
  budget="$(gib_to_bytes "${WORKSPACE_MAX_GIB_PER_RUNNER:-4}" 2>/dev/null || true)"
  retention="${WORKSPACE_IDLE_RETENTION_HOURS:-$((${WORKSPACE_RETENTION_DAYS:-2} * 24))}"
  [[ "$budget" =~ ^[0-9]+$ && "$retention" =~ ^[0-9]+$ ]] || return 1
  printf '%s %s\n' "$budget" "$retention"
}

apply_workspace_policy() {
  local runner="$1" work="$2" force="${3:-false}" values budget retention
  runner_idle_now "$runner" || return 0
  values="$(workspace_policy_values)" || {
    warn "${runner}: configuración de workspace inválida; se omite retención"
    return 0
  }
  read -r budget retention <<<"$values"
  cleanup_idle_workspaces "$work" "$budget" "$retention" "$force" ||
    warn "${runner}: no se pudo aplicar política de workspace"
}

apply_cache_budget() {
  local runner="$1" cache="$2" package_budget tool_budget
  runner_idle_now "$runner" || return 0
  package_budget="$(gib_to_bytes "${PACKAGE_CACHE_MAX_GIB_PER_RUNNER:-2}" 2>/dev/null || true)"
  tool_budget="$(gib_to_bytes "${TOOLCACHE_MAX_GIB_PER_RUNNER:-4}" 2>/dev/null || true)"

  if [[ "$package_budget" =~ ^[0-9]+$ && "$tool_budget" =~ ^[0-9]+$ ]]; then
    cleanup_idle_cache_budget "$cache" "$package_budget" "$tool_budget" ||
      warn "${runner}: no se pudo aplicar presupuesto de cache"
  else
    warn "${runner}: configuración de presupuesto de cache inválida"
  fi
}

apply_dind_budget() {
  local runner="$1" index="$2" dind="$3" budget size path
  runner_idle_now "$runner" || return 0
  path="${CI_STORAGE_ROOT}/docker-${index}"
  budget="$(gib_to_bytes "${DIND_MAX_GIB_PER_RUNNER:-6}" 2>/dev/null || true)"
  [[ "$budget" =~ ^[0-9]+$ ]] || {
    warn "${runner}: DIND_MAX_GIB_PER_RUNNER inválido"
    return 0
  }

  size="$(path_size_bytes "$path")"
  [[ "$size" =~ ^[0-9]+$ ]] || size=0
  if (( size > budget )); then
    log "${runner}: DinD sobre presupuesto (${size}B > ${budget}B); reclaim agresivo"
    prune_dind_aggressive "$dind"
  fi
}

prune_dind_normal() {
  local dind="$1"

  if ! compose exec -T "$dind" docker info >/dev/null 2>&1; then
    warn "${dind}: Docker CI no responde; se omite prune de este daemon"
    return 0
  fi

  if [[ "$CLEANUP_DRY_RUN" == true ]]; then
    log "dry-run: ${dind} ejecutaría prune normal de contenedores/redes/volúmenes/imágenes/build cache"
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

  if [[ "$CLEANUP_DRY_RUN" == true ]]; then
    log "dry-run: ${dind} ejecutaría prune agresivo de imágenes/build cache"
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
    if [[ "$CLEANUP_DRY_RUN" == true ]]; then
      log "dry-run: ${runner} sería reiniciado al estar bajo el umbral de recuperación"
      return 0
    fi
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

  if ! runner_idle_now "$runner"; then
    return 0
  fi

  log "${runner}: idle confirmado bajo lease"

  runner_idle_now "$runner" && prune_dind_normal "$dind"

  if safe_path_in_ci_storage "$cache"; then
    if runner_idle_now "$runner"; then
      delete_expired_package_cache "$cache" "${PACKAGE_CACHE_RETENTION_DAYS:-7}" ||
        warn "${runner}: no se pudo aplicar retención por edad de package cache"
    fi
  else
    warn "${runner}: cache fuera del storage verificado; se omite"
  fi

  apply_cache_budget "$runner" "$cache"
  apply_dind_budget "$runner" "$index" "$dind"

  # Workspaces/checkouts are regenerable. Reclaim them while idle based on
  # their own age/size, independently of the global pressure threshold.
  apply_workspace_policy "$runner" "$work" false

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_AGGRESSIVE_PERCENT:-82} )); then
    if ! runner_idle_now "$runner"; then
      return 0
    fi
    log "${runner}: umbral agresivo (${usage}%). Reduciendo cachés y workspace."
    prune_dind_aggressive "$dind"
    apply_workspace_policy "$runner" "$work" true
    if runner_idle_now "$runner"; then
      clear_cache_dir "$cache/npm"
      clear_cache_dir "$cache/pip"
      clear_cache_dir "$cache/nuget"
    fi
  fi

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
    if ! runner_idle_now "$runner"; then
      return 0
    fi
    warn "${runner}: emergencia de disco (${usage}%). Limpiando toolcache antes de pausar."
    clear_cache_dir "$cache/toolcache"
    usage="$(storage_usage_percent)"
    if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
      if ! runner_idle_now "$runner"; then
        return 0
      fi
      if [[ "$CLEANUP_DRY_RUN" == true ]]; then
        warn "dry-run: ${runner} sería pausado por emergencia de disco (${usage}%)"
      else
        warn "${runner}: uso ${usage}% después de reclaim; se pausa el listener idle"
        compose stop "$runner" >/dev/null 2>&1 || true
        touch "$marker"
      fi
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

  if ! runner_idle_now "$runner"; then
    return 0
  fi

  log "${runner}: idle confirmado bajo lease (Gate sin DinD)"

  if safe_path_in_ci_storage "$cache"; then
    if runner_idle_now "$runner"; then
      delete_expired_package_cache "$cache" "${PACKAGE_CACHE_RETENTION_DAYS:-7}" ||
        warn "${runner}: no se pudo aplicar retención por edad de package cache"
    fi
  fi

  apply_cache_budget "$runner" "$cache"
  apply_workspace_policy "$runner" "$work" false

  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_AGGRESSIVE_PERCENT:-82} )); then
    if ! runner_idle_now "$runner"; then
      return 0
    fi
    apply_workspace_policy "$runner" "$work" true
    if runner_idle_now "$runner"; then
      clear_cache_dir "$cache/npm"
      clear_cache_dir "$cache/pip"
      clear_cache_dir "$cache/nuget"
    fi

    usage="$(storage_usage_percent)"
    if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )) && runner_idle_now "$runner"; then
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
  if [[ "$CLEANUP_DRY_RUN" == true ]]; then
    log "dry-run: host Docker ejecutaría image prune de imágenes CI no referenciadas"
  else
    docker image prune -af \
      --filter 'label=io.coferlandia.ci=true' \
      --filter "until=${IMAGE_RETENTION_HOURS:-72}h" >/dev/null 2>&1 || true
  fi

  for index in 01 02 03; do
    cleanup_heavy_runner "$index"
  done
  cleanup_gate

  trim_ci_storage_if_due

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
