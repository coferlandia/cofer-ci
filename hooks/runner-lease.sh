#!/usr/bin/env bash
# Shared lease between GitHub runner hooks and host-side cleanup.
# shellcheck shell=bash

with_runner_cleanup_lease() {
  local timeout="${RUNNER_CLEANUP_LEASE_WAIT_SECONDS:-120}"
  local lock_file="${RUNNER_CLEANUP_LOCK_FILE:-/cache/.cleanup.lock}"
  local fd rc=0 old_umask

  mkdir -p "$(dirname -- "$lock_file")"

  # The host-side cleanup service and the runner hooks intentionally share this
  # advisory lock across different Unix users. Keep the lock file non-secret
  # and writable by both sides regardless of which one creates it first.
  old_umask="$(umask)"
  umask 000
  : > "$lock_file"
  chmod 0666 "$lock_file" 2>/dev/null || true
  umask "$old_umask"

  exec {fd}>"$lock_file"
  if ! flock -w "$timeout" "$fd"; then
    exec {fd}>&-
    return 75
  fi

  "$@" || rc=$?

  flock -u "$fd" || true
  exec {fd}>&-
  return "$rc"
}
