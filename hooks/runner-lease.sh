#!/usr/bin/env bash
# Shared lease between GitHub runner hooks and host-side cleanup.
# shellcheck shell=bash

with_runner_cleanup_lease() {
  local timeout="${RUNNER_CLEANUP_LEASE_WAIT_SECONDS:-120}"
  local lock_file="${RUNNER_CLEANUP_LOCK_FILE:-/cache/.cleanup.lock}"
  local fd rc=0

  mkdir -p "$(dirname -- "$lock_file")"
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
