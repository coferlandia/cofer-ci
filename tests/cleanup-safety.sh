#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GUARDS="${ROOT}/scripts/cleanup-guards.sh"

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS  %s\n' "$*"
}

[[ -f "$GUARDS" ]] || fail "missing scripts/cleanup-guards.sh"

# shellcheck source=../scripts/common.sh
source "${ROOT}/scripts/common.sh"
# shellcheck source=../scripts/cleanup-guards.sh
source "$GUARDS"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
CI_STORAGE_ROOT="${TEST_ROOT}/ci"
CI_STORAGE_IMAGE="${TEST_ROOT}/coferlandia-ci.img"
mkdir -p "$CI_STORAGE_ROOT/cache-01" "$TEST_ROOT/outside"
: > "$CI_STORAGE_IMAGE"

MOCK_MOUNTED=true
MOCK_SOURCE=/dev/loop7
MOCK_LOOP_IMAGE="$CI_STORAGE_IMAGE"
MOCK_ACTIVITY=idle

mountpoint() {
  [[ "${1:-}" == "-q" ]] || return 2
  [[ "$MOCK_MOUNTED" == true ]]
}

findmnt() {
  printf '%s\n' "$MOCK_SOURCE"
}

losetup() {
  printf '%s: []: (%s)\n' "$MOCK_SOURCE" "$MOCK_LOOP_IMAGE"
}

compose() {
  if [[ "${1:-}" == "ps" && "${2:-}" == "-q" ]]; then
    printf 'mock-cid\n'
    return 0
  fi
  return 2
}

docker() {
  case "${1:-}" in
    inspect)
      [[ "$MOCK_ACTIVITY" != unknown ]] || return 125
      printf 'true\n'
      ;;
    exec)
      [[ "$MOCK_ACTIVITY" != unknown ]] || return 125
      if [[ "${3:-}" == "true" ]]; then
        return 0
      fi
      [[ "$MOCK_ACTIVITY" == busy ]] && return 0
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}

MOCK_MOUNTED=false
if ci_storage_verified; then
  fail "unmounted CI storage accepted"
fi
pass "unmounted CI storage rejected"

MOCK_MOUNTED=true
MOCK_SOURCE=/dev/sda1
if ci_storage_verified; then
  fail "non-loop CI storage accepted"
fi
pass "wrong CI storage source rejected"

MOCK_SOURCE=/dev/loop7
MOCK_LOOP_IMAGE="$CI_STORAGE_IMAGE"
ci_storage_verified || fail "expected loop mount rejected"
pass "expected loop mount accepted"

mkdir -p "$CI_STORAGE_ROOT/remount-check"
printf keep > "$CI_STORAGE_ROOT/remount-check/file"
MOCK_MOUNTED=false
set +e
safe_clean_dir "$CI_STORAGE_ROOT/remount-check"
remount_rc=$?
set -e
[[ "$remount_rc" -eq 74 ]] || fail "lost mount did not block cleanup (rc=$remount_rc)"
[[ -f "$CI_STORAGE_ROOT/remount-check/file" ]] || fail "cleanup modified data after mount disappeared"
MOCK_MOUNTED=true
pass "destructive helper revalidates mount immediately before delete"

mkdir -p "$CI_STORAGE_ROOT/safe"
printf x > "$CI_STORAGE_ROOT/safe/file"
safe_clean_dir "$CI_STORAGE_ROOT/safe"
[[ -z "$(find "$CI_STORAGE_ROOT/safe" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
  fail "safe directory was not cleared"
pass "safe directory cleared"

ln -s "$TEST_ROOT/outside" "$CI_STORAGE_ROOT/escape"
if safe_clean_dir "$CI_STORAGE_ROOT/escape"; then
  fail "symlink escape accepted"
fi
pass "symlink escape rejected"

MOCK_ACTIVITY=busy
[[ "$(runner_activity runner-01)" == busy ]] || fail "busy runner not detected"
MOCK_ACTIVITY=idle
[[ "$(runner_activity runner-01)" == idle ]] || fail "idle runner not detected"
MOCK_ACTIVITY=unknown
[[ "$(runner_activity runner-01)" == unknown ]] || fail "unknown runner not fail-closed"
pass "runner activity is tri-state"

MOCK_ACTIVITY=idle
set +e
runner_activity runner-01 >/dev/null
flags_after_activity="$-"
set -e
[[ "$flags_after_activity" != *e* ]] || fail "runner_activity changed caller errexit state"
pass "runner_activity preserves caller shell options"

set +e
with_cleanup_lock false
lock_rc=$?
flags_after_lock="$-"
set -e
[[ "$lock_rc" -eq 1 ]] || fail "cleanup lock did not propagate command rc"
[[ "$flags_after_lock" != *e* ]] || fail "with_cleanup_lock changed caller errexit state"
pass "cleanup lock preserves caller shell options and rc"

set +e
with_runner_lease runner-01 false
runner_lease_rc=$?
flags_after_runner_lease="$-"
set -e
[[ "$runner_lease_rc" -eq 1 ]] || fail "runner lease did not propagate command rc"
[[ "$flags_after_runner_lease" != *e* ]] || fail "with_runner_lease changed caller errexit state"
pass "runner lease preserves caller shell options and rc"

MOCK_ACTIVITY=idle

exec 8>"$CI_STORAGE_ROOT/.cleanup.lock"
flock -n 8
set +e
with_cleanup_lock true
rc=$?
set -e
[[ "$rc" -eq 75 ]] || fail "cleanup lock contention did not return 75 (got $rc)"
flock -u 8
exec 8>&-
pass "global cleanup lock serializes callers"

exec 9>"$CI_STORAGE_ROOT/cache-01/.cleanup.lock"
flock -n 9
set +e
with_runner_lease runner-01 true
rc=$?
set -e
[[ "$rc" -eq 75 ]] || fail "runner lease contention did not return 75 (got $rc)"
flock -u 9
exec 9>&-
pass "runner lease serializes cleanup and job hook"

printf '\ncleanup safety tests passed\n'
