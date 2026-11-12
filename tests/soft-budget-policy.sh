#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

# shellcheck source=../scripts/storage-policy.sh
source "$ROOT/scripts/storage-policy.sh"

declare -F soft_budget_reclaim_enabled >/dev/null ||
  fail "soft_budget_reclaim_enabled missing"

DISK_WARN_PERCENT=75
soft_budget_reclaim_enabled 74 && fail "soft budgets enabled below warning threshold"
soft_budget_reclaim_enabled 75 || fail "soft budgets disabled at warning threshold"
soft_budget_reclaim_enabled 81 || fail "soft budgets disabled between warning and aggressive threshold"
pass "soft budgets activate only at shared-filesystem pressure"

for pair in   "PACKAGE_CACHE_MAX_GIB_PER_RUNNER=4"   "TOOLCACHE_MAX_GIB_PER_RUNNER=8"   "DIND_MAX_GIB_PER_RUNNER=12"   "WORKSPACE_MAX_GIB_PER_RUNNER=12"   "WORKSPACE_IDLE_RETENTION_HOURS=48"   "BUILDKIT_CACHE_KEEP=6GB"   "BUILDKIT_CACHE_EMERGENCY_KEEP=1GB"; do
  grep -q "^${pair}$" "$ROOT/.env.example" || fail "missing relaxed default: $pair"
done
pass "heavy-workflow soft-budget defaults are relaxed"

grep -q 'soft_budget_reclaim_enabled "$usage"' "$ROOT/scripts/cleanup.sh" ||
  fail "cleanup does not gate soft budgets on disk pressure"

grep -q 'apply_workspace_age_retention' "$ROOT/scripts/cleanup.sh" ||
  fail "cleanup does not preserve age-only workspace retention below pressure"

pass "cleanup wiring separates conservative retention from pressure budgets"
printf '\nsoft budget policy tests passed\n'
