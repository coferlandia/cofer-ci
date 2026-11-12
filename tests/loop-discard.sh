#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/scripts/loop-maintenance.sh"
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

[[ -f "$MODULE" ]] || fail "missing scripts/loop-maintenance.sh"
# shellcheck source=../scripts/loop-maintenance.sh
source "$MODULE"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
CI_STORAGE_ROOT="$TMP_ROOT/ci"
CI_STORAGE_IMAGE="$TMP_ROOT/coferlandia-ci.img"
CI_TRIM_STATE_FILE="$TMP_ROOT/last-trim"
CI_TRIM_INTERVAL_HOURS=24
RUNNER_SERVICES=(runner-01 runner-02 runner-03 runner-04)
mkdir -p "$CI_STORAGE_ROOT"
truncate -s 1M "$CI_STORAGE_IMAGE"

MOCK_VERIFIED=true
MOCK_ACTIVITY=idle
TRIM_CALLS=0
ci_storage_verified() { [[ "$MOCK_VERIFIED" == true ]]; }
runner_activity() { printf '%s\n' "$MOCK_ACTIVITY"; }
fstrim() { TRIM_CALLS=$((TRIM_CALLS + 1)); printf 'trimmed-test\n'; }

MOCK_VERIFIED=false
trim_ci_storage_if_due
[[ "$TRIM_CALLS" -eq 0 ]] || fail "trim ran on unverified storage"
pass "trim skips unverified storage"

MOCK_VERIFIED=true
MOCK_ACTIVITY=busy
trim_ci_storage_if_due
[[ "$TRIM_CALLS" -eq 0 ]] || fail "trim ran while runner busy"
pass "trim skips non-idle runners"

MOCK_ACTIVITY=idle
trim_ci_storage_if_due
[[ "$TRIM_CALLS" -eq 1 ]] || fail "due trim did not run exactly once"
[[ -s "$CI_TRIM_STATE_FILE" ]] || fail "successful trim did not persist state"
pass "due trim runs and persists state"

trim_ci_storage_if_due
[[ "$TRIM_CALLS" -eq 1 ]] || fail "trim ignored interval state"
pass "trim interval prevents hourly re-trim"

grep -q '^CI_TRIM_INTERVAL_HOURS=' "$ROOT/.env.example" || fail "trim interval setting missing"
grep -q 'trim_ci_storage_if_due' "$ROOT/scripts/cleanup.sh" || fail "cleanup does not invoke safe trim"
grep -q 'CI image physical' "$ROOT/scripts/status.sh" || fail "status lacks physical image telemetry"
pass "trim and telemetry are wired into operations"

printf '\nloop discard tests passed\n'
