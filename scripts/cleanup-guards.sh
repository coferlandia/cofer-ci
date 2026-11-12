#!/usr/bin/env bash
# Safety primitives shared by host-side CI storage maintenance.
# shellcheck shell=bash

cleanup_guard_warn() {
  if declare -F warn >/dev/null 2>&1; then
    warn "$*"
  else
    printf '[cleanup-guard] WARNING: %s\n' "$*" >&2
  fi
}

ci_storage_verified() {
  local source loop_line loop_device

  [[ -n "${CI_STORAGE_ROOT:-}" && -n "${CI_STORAGE_IMAGE:-}" ]] || return 1
  [[ -d "$CI_STORAGE_ROOT" && -f "$CI_STORAGE_IMAGE" ]] || return 1
  mountpoint -q "$CI_STORAGE_ROOT" || return 1

  source="$(findmnt -n -o SOURCE --target "$CI_STORAGE_ROOT" 2>/dev/null)" || return 1
  [[ "$source" == /dev/loop* ]] || return 1

  while IFS= read -r loop_line; do
    loop_device="${loop_line%%:*}"
    [[ "$loop_device" == "$source" ]] && return 0
  done < <(losetup -j "$CI_STORAGE_IMAGE" 2>/dev/null || true)

  return 1
}

runner_activity() {
  local service="${1:-}" cid running rc

  if [[ -z "$service" ]]; then
    printf 'unknown\n'
    return 0
  fi

  cid="$(compose ps -q "$service" 2>/dev/null || true)"
  if [[ -z "$cid" ]]; then
    printf 'unknown\n'
    return 0
  fi

  running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || true)"
  if [[ "$running" != true ]]; then
    printf 'unknown\n'
    return 0
  fi

  if ! docker exec "$cid" true >/dev/null 2>&1; then
    printf 'unknown\n'
    return 0
  fi

  if docker exec "$cid" pgrep -x Runner.Worker >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi

  case "$rc" in
    0) printf 'busy\n' ;;
    1) printf 'idle\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

with_cleanup_lock() {
  local timeout="${CLEANUP_LOCK_TIMEOUT_SECONDS:-0}" lock_file fd rc

  [[ -n "${CI_STORAGE_ROOT:-}" && -d "$CI_STORAGE_ROOT" ]] || return 78
  lock_file="$CI_STORAGE_ROOT/.cleanup.lock"

  exec {fd}>"$lock_file"
  if ! flock -w "$timeout" "$fd"; then
    exec {fd}>&-
    return 75
  fi

  rc=0
  "$@" || rc=$?

  flock -u "$fd" || true
  exec {fd}>&-
  return "$rc"
}

with_runner_lease() {
  local service="${1:-}" timeout="${HOST_CLEANUP_LEASE_WAIT_SECONDS:-0}"
  local index cache lock_file fd rc
  shift || true

  [[ -n "$service" ]] || return 78
  index="$(runner_index "$service")"
  cache="$CI_STORAGE_ROOT/cache-$index"
  [[ -d "$cache" ]] || return 78
  lock_file="$cache/.cleanup.lock"

  exec {fd}>"$lock_file"
  if ! flock -w "$timeout" "$fd"; then
    exec {fd}>&-
    return 75
  fi

  rc=0
  "$@" || rc=$?

  flock -u "$fd" || true
  exec {fd}>&-
  return "$rc"
}

safe_path_in_ci_storage() {
  local target="${1:-}" root_real target_real

  [[ -n "$target" && -n "${CI_STORAGE_ROOT:-}" ]] || return 1
  [[ -e "$target" ]] || return 1
  [[ ! -L "$target" ]] || return 1

  root_real="$(readlink -f -- "$CI_STORAGE_ROOT" 2>/dev/null)" || return 1
  target_real="$(readlink -f -- "$target" 2>/dev/null)" || return 1

  [[ "$target_real" != "$root_real" ]] || return 1
  [[ "$target_real" == "$root_real/"* ]] || return 1
}

safe_clean_dir() {
  local target="${1:-}" dry_run=false child
  [[ "${2:-}" == "--dry-run" ]] && dry_run=true

  [[ -d "$target" ]] || return 1
  ci_storage_verified || return 74
  safe_path_in_ci_storage "$target" || return 1

  while IFS= read -r -d '' child; do
    if [[ "$dry_run" == true ]]; then
      printf 'would-remove=%s\n' "$child"
    else
      rm -rf -- "$child"
    fi
  done < <(find "$target" -mindepth 1 -maxdepth 1 -print0)
}

safe_remove_path() {
  local target="${1:-}" dry_run=false
  [[ "${2:-}" == "--dry-run" ]] && dry_run=true

  ci_storage_verified || return 74
  safe_path_in_ci_storage "$target" || return 1

  if [[ "$dry_run" == true ]]; then
    printf 'would-remove=%s\n' "$target"
  else
    rm -rf -- "$target"
  fi
}
