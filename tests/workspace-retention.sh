#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$ROOT/scripts/storage-policy.sh"
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

[[ -f "$POLICY" ]] || fail "missing scripts/storage-policy.sh"
# shellcheck source=../scripts/cleanup-guards.sh
source "$ROOT/scripts/cleanup-guards.sh"
# shellcheck source=../scripts/storage-policy.sh
source "$POLICY"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
CI_STORAGE_ROOT="$TMP_ROOT/ci"
mkdir -p "$CI_STORAGE_ROOT/work-01/_actions" "$CI_STORAGE_ROOT/work-01/secretarIA/secretarIA/.git/objects/pack"
printf keep > "$CI_STORAGE_ROOT/work-01/_actions/keep"
dd if=/dev/zero of="$CI_STORAGE_ROOT/work-01/secretarIA/secretarIA/.git/objects/pack/pack-a" bs=2048 count=1 status=none

cleanup_idle_workspaces "$CI_STORAGE_ROOT/work-01" 1024 24 false
[[ ! -e "$CI_STORAGE_ROOT/work-01/secretarIA" ]] || fail "oversized workspace was retained"
[[ -f "$CI_STORAGE_ROOT/work-01/_actions/keep" ]] || fail "runner internal directory was removed"
pass "oversized workspace is removed without touching runner internals"

mkdir -p "$CI_STORAGE_ROOT/work-01/small/small"
printf x > "$CI_STORAGE_ROOT/work-01/small/small/file"
cleanup_idle_workspaces "$CI_STORAGE_ROOT/work-01" 10485760 24 false
[[ -d "$CI_STORAGE_ROOT/work-01/small" ]] || fail "recent small workspace was removed"
pass "recent workspace under budget is retained"

mkdir -p "$CI_STORAGE_ROOT/work-01/old/old"
printf x > "$CI_STORAGE_ROOT/work-01/old/old/file"
touch -d "2 days ago" "$CI_STORAGE_ROOT/work-01/old"
cleanup_idle_workspaces "$CI_STORAGE_ROOT/work-01" 10485760 24 false
[[ ! -e "$CI_STORAGE_ROOT/work-01/old" ]] || fail "expired workspace was retained"
pass "expired idle workspace is removed"

mkdir -p "$CI_STORAGE_ROOT/work-01/forced/forced"
cleanup_idle_workspaces "$CI_STORAGE_ROOT/work-01" 10485760 24 true
[[ ! -e "$CI_STORAGE_ROOT/work-01/forced" ]] || fail "forced pressure cleanup retained workspace"
pass "pressure mode purges regenerable workspaces"

grep -q '^WORKSPACE_MAX_GIB_PER_RUNNER=' "$ROOT/.env.example" || fail "workspace budget setting missing"
grep -q '^WORKSPACE_IDLE_RETENTION_HOURS=' "$ROOT/.env.example" || fail "workspace retention setting missing"
grep -q 'cleanup_idle_workspaces' "$ROOT/scripts/cleanup.sh" || fail "cleanup.sh does not apply workspace policy"
pass "workspace policy is wired into host cleanup"

printf '\nworkspace retention tests passed\n'
