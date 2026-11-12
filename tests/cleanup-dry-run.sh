#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

# shellcheck source=../scripts/cleanup-guards.sh
source "$ROOT/scripts/cleanup-guards.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
CI_STORAGE_ROOT="$TMP_ROOT/ci"
mkdir -p "$CI_STORAGE_ROOT/safe"
printf keep > "$CI_STORAGE_ROOT/safe/file"
output="$(safe_clean_dir "$CI_STORAGE_ROOT/safe" --dry-run)"
[[ -f "$CI_STORAGE_ROOT/safe/file" ]] || fail "safe_clean_dir dry-run deleted data"
[[ "$output" == *"would-remove="* ]] || fail "safe_clean_dir dry-run did not report candidate"
pass "primitive dry-run reports without deleting"

grep -q -- '--dry-run' "$ROOT/scripts/cleanup.sh" || fail "cleanup CLI lacks --dry-run"
grep -q 'CLEANUP_DRY_RUN' "$ROOT/scripts/cleanup.sh" || fail "cleanup does not carry dry-run state"
grep -q 'CLEANUP_DRY_RUN' "$ROOT/scripts/storage-policy.sh" || fail "storage policy ignores dry-run state"
grep -q 'CLEANUP_DRY_RUN' "$ROOT/scripts/loop-maintenance.sh" || fail "trim maintenance ignores dry-run state"
pass "dry-run state covers host, policy and trim layers"

printf '\ncleanup dry-run tests passed\n'
