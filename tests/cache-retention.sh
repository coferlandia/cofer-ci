#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

# shellcheck source=../scripts/cleanup-guards.sh
source "$ROOT/scripts/cleanup-guards.sh"
# shellcheck source=../scripts/storage-policy.sh
source "$ROOT/scripts/storage-policy.sh"

declare -F cleanup_idle_cache_budget >/dev/null || fail "cleanup_idle_cache_budget missing"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
CI_STORAGE_ROOT="$TMP_ROOT/ci"
# Fixture paths are intentionally not real mounts; destructive helpers are tested separately.
ci_storage_verified() { return 0; }
cache="$CI_STORAGE_ROOT/cache-01"
mkdir -p "$cache/npm" "$cache/pip" "$cache/nuget" "$cache/toolcache"
dd if=/dev/zero of="$cache/npm/a" bs=1024 count=1 status=none
dd if=/dev/zero of="$cache/pip/b" bs=1024 count=1 status=none
dd if=/dev/zero of="$cache/toolcache/t" bs=2048 count=1 status=none

cleanup_idle_cache_budget "$cache" 1024 1024
[[ -z "$(find "$cache/npm" "$cache/pip" "$cache/nuget" -type f -print -quit)" ]] ||
  fail "package caches over budget were retained"
[[ -z "$(find "$cache/toolcache" -type f -print -quit)" ]] ||
  fail "toolcache over budget was retained"
pass "cache budgets reclaim regenerable package/tool data"

printf x > "$cache/npm/small"
printf x > "$cache/toolcache/small"
cleanup_idle_cache_budget "$cache" 1048576 1048576
[[ -f "$cache/npm/small" && -f "$cache/toolcache/small" ]] ||
  fail "cache below budget was removed"
pass "cache below budget is retained"

mkdir -p "$cache/npm" "$cache/toolcache"
printf old-package > "$cache/npm/old"
printf old-tool > "$cache/toolcache/keep"
touch -d "10 days ago" "$cache/npm/old" "$cache/toolcache/keep"
declare -F delete_expired_package_cache >/dev/null || fail "delete_expired_package_cache missing"
delete_expired_package_cache "$cache" 7
[[ ! -e "$cache/npm/old" ]] || fail "expired package cache was retained"
[[ -e "$cache/toolcache/keep" ]] || fail "age retention incorrectly deleted toolcache"
pass "age retention is scoped to npm/pip/nuget only"

for setting in PACKAGE_CACHE_MAX_GIB_PER_RUNNER TOOLCACHE_MAX_GIB_PER_RUNNER DIND_MAX_GIB_PER_RUNNER; do
  grep -q "^${setting}=" "$ROOT/.env.example" || fail "${setting} missing"
done
grep -q 'apply_dind_budget "$runner" "$index" "$dind"' "$ROOT/scripts/cleanup.sh" ||
  fail "DinD budget helper is defined but not applied"
grep -q 'apply_cache_budget "$runner" "$cache"' "$ROOT/scripts/cleanup.sh" ||
  fail "cache budget helper is defined but not applied"
grep -q 'delete_expired_package_cache "$cache"' "$ROOT/scripts/cleanup.sh" ||
  fail "package age retention is not wired through scoped helper"
pass "per-runner cache and DinD budgets are wired"

printf '\ncache retention tests passed\n'
