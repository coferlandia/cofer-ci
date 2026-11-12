#!/usr/bin/env bash
# Storage retention helpers. Destructive callers must already hold the runner lease.
# shellcheck shell=bash

storage_policy_log() {
  if declare -F log >/dev/null 2>&1; then
    log "$*"
  else
    printf '[storage-policy] %s\n' "$*"
  fi
}

gib_to_bytes() {
  local gib="${1:-}"
  [[ "$gib" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$((gib * 1024 * 1024 * 1024))"
}

path_size_bytes() {
  local path="${1:-}"
  [[ -e "$path" ]] || {
    printf '0\n'
    return 0
  }
  du -s -B1 -- "$path" 2>/dev/null | awk '{print $1}'
}

path_age_hours() {
  local path="${1:-}" now modified
  [[ -e "$path" ]] || return 1
  now="$(date +%s)"
  modified="$(stat -c %Y -- "$path" 2>/dev/null)" || return 1
  printf '%s\n' "$(((now - modified) / 3600))"
}

cleanup_idle_workspaces() {
  local work="${1:-}" budget_bytes="${2:-}" retention_hours="${3:-}" force="${4:-false}"
  local candidate size age total=0
  local -a candidates=()

  [[ -d "$work" ]] || return 0
  safe_path_in_ci_storage "$work" || return 1
  [[ "$budget_bytes" =~ ^[0-9]+$ ]] || return 1
  [[ "$retention_hours" =~ ^[0-9]+$ ]] || return 1
  [[ "$force" == true || "$force" == false ]] || return 1

  while IFS= read -r -d '' candidate; do
    candidates+=("$candidate")
    size="$(path_size_bytes "$candidate")"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    total=$((total + size))
  done < <(
    find "$work" -mindepth 1 -maxdepth 1 -type d ! -name '_*' -print0 2>/dev/null
  )

  for candidate in "${candidates[@]}"; do
    age="$(path_age_hours "$candidate" 2>/dev/null || printf '0')"
    if [[ "$force" == true ]] || (( total > budget_bytes )) || (( age >= retention_hours )); then
      size="$(path_size_bytes "$candidate")"
      storage_policy_log "workspace reclaim: ${candidate} size=${size}B age=${age}h force=${force}"
      safe_remove_path "$candidate" || return 1
      if [[ "$size" =~ ^[0-9]+$ ]] && (( size <= total )); then
        total=$((total - size))
      fi
    fi
  done
}
