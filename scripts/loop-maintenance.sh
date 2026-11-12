#!/usr/bin/env bash
# Safe discard/telemetry for the sparse CI loopback image.
# shellcheck shell=bash

loop_maintenance_log() {
  if declare -F log >/dev/null 2>&1; then
    log "$*"
  else
    printf '[loop-maintenance] %s\n' "$*"
  fi
}

loop_maintenance_warn() {
  if declare -F warn >/dev/null 2>&1; then
    warn "$*"
  else
    printf '[loop-maintenance] WARNING: %s\n' "$*" >&2
  fi
}

ci_image_physical_bytes() {
  [[ -f "${CI_STORAGE_IMAGE:-}" ]] || {
    printf '0\n'
    return 0
  }
  du -s -B1 -- "$CI_STORAGE_IMAGE" 2>/dev/null | awk '{print $1}'
}

ci_trim_is_due() {
  local interval="${CI_TRIM_INTERVAL_HOURS:-24}" state_file
  local now last=0

  [[ "$interval" =~ ^[1-9][0-9]*$ ]] || return 1
  state_file="${CI_TRIM_STATE_FILE:-${CI_STORAGE_ROOT}/.last-trim-epoch}"
  now="$(date +%s)"

  if [[ -r "$state_file" ]]; then
    read -r last < "$state_file" || last=0
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
  fi

  (( now - last >= interval * 3600 ))
}

all_runners_idle_for_storage_maintenance() {
  local service activity
  local -a services=(runner-01 runner-02 runner-03 runner-04)
  if declare -p RUNNER_SERVICES >/dev/null 2>&1 && (( ${#RUNNER_SERVICES[@]} > 0 )); then
    services=("${RUNNER_SERVICES[@]}")
  fi
  for service in "${services[@]}"; do
    activity="$(runner_activity "$service")"
    if [[ "$activity" != idle ]]; then
      loop_maintenance_log "trim omitido: ${service} actividad=${activity}"
      return 1
    fi
  done
  return 0
}

trim_ci_storage_if_due() {
  local state_file before after reclaimed output_file now

  ci_storage_verified || {
    loop_maintenance_warn "trim omitido: mount/origen de CI no verificado"
    return 0
  }

  ci_trim_is_due || return 0
  all_runners_idle_for_storage_maintenance || return 0

  if [[ "${CLEANUP_DRY_RUN:-false}" == true ]]; then
    loop_maintenance_log "dry-run: fstrim se ejecutaría sobre ${CI_STORAGE_ROOT}"
    return 0
  fi

  if ! command -v fstrim >/dev/null 2>&1; then
    loop_maintenance_warn "trim omitido: fstrim no disponible"
    return 0
  fi

  state_file="${CI_TRIM_STATE_FILE:-${CI_STORAGE_ROOT}/.last-trim-epoch}"
  before="$(ci_image_physical_bytes)"
  output_file="$(mktemp)"

  if ! fstrim -v "$CI_STORAGE_ROOT" >"$output_file" 2>&1; then
    loop_maintenance_warn "fstrim falló; no se actualiza el estado"
    rm -f -- "$output_file"
    return 0
  fi

  after="$(ci_image_physical_bytes)"
  reclaimed=0
  if [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]] && (( before > after )); then
    reclaimed=$((before - after))
  fi

  now="$(date +%s)"
  printf '%s\n' "$now" > "$state_file"
  cat "$output_file"
  rm -f -- "$output_file"

  loop_maintenance_log "trim completado: image_before=${before}B image_after=${after}B physical_reclaimed=${reclaimed}B"
}
