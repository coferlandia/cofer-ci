#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LEASE="${ROOT}/hooks/runner-lease.sh"

fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

[[ -f "$LEASE" ]] || fail "missing hooks/runner-lease.sh"
# shellcheck source=../hooks/runner-lease.sh
source "$LEASE"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RUNNER_CLEANUP_LOCK_FILE="$TMP/runner.lock"
RUNNER_CLEANUP_LEASE_WAIT_SECONDS=0

called="$TMP/called"
mark_called() { : > "$called"; }

with_runner_cleanup_lease mark_called || fail "free runner lease rejected"
[[ -f "$called" ]] || fail "runner lease did not execute protected command"
pass "free runner lease executes protected command"

rm -f "$called"
exec 8>"$RUNNER_CLEANUP_LOCK_FILE"
flock -n 8
set +e
with_runner_cleanup_lease mark_called
rc=$?
set -e
flock -u 8
exec 8>&-
[[ "$rc" -eq 75 ]] || fail "contended runner lease returned $rc instead of 75"
[[ ! -f "$called" ]] || fail "contended runner lease executed protected command"
pass "contended runner lease blocks protected command"

grep -q 'source "/opt/runner-hooks/runner-lease.sh"' "$ROOT/hooks/pre-job.sh" ||
  fail "pre-job does not use runner lease"
grep -q 'with_runner_cleanup_lease' "$ROOT/hooks/pre-job.sh" ||
  fail "pre-job does not execute under runner lease"
grep -q 'source "/opt/runner-hooks/runner-lease.sh"' "$ROOT/hooks/post-job.sh" ||
  fail "post-job does not use runner lease"
grep -q 'util-linux' "$ROOT/runner/Dockerfile" ||
  fail "runner image does not guarantee flock/util-linux"

pass "runner hooks and image include cleanup lease contract"
printf '\njob lease tests passed\n'
