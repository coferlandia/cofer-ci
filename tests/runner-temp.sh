#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

for variable in TMPDIR TMP TEMP; do
  count="$(grep -c "^[[:space:]]*${variable}: /cache/tmp$" "$ROOT/compose.yml" || true)"
  [[ "$count" -eq 5 ]] ||
    fail "${variable} must be declared in shared runner env plus four concrete runner envs (got $count)"
done
pass "all runner services route temporary files to /cache/tmp"

grep -Fq '$CI_STORAGE_ROOT/cache-${index}/tmp' "$ROOT/scripts/install-host.sh" ||
  fail "heavy runner temp directory is not created by install-host.sh"
grep -Fq '$CI_STORAGE_ROOT/cache-04/tmp' "$ROOT/scripts/install-host.sh" ||
  fail "Gate temp directory is not created by install-host.sh"
pass "host installer creates per-runner temp directories"

# shellcheck source=../hooks/cache-pressure.sh
source "$ROOT/hooks/cache-pressure.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
RUNNER_CACHE_ROOT="$TMP_ROOT/cache"
mkdir -p "$RUNNER_CACHE_ROOT/tmp/pip-unpack-a" "$RUNNER_CACHE_ROOT/tmp/pytest-old"
printf x > "$RUNNER_CACHE_ROOT/tmp/pip-unpack-a/file"
printf x > "$RUNNER_CACHE_ROOT/tmp/pytest-old/file"

declare -F clear_runner_tmp >/dev/null || fail "clear_runner_tmp function missing"
clear_runner_tmp "test"
[[ -z "$(find "$RUNNER_CACHE_ROOT/tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
  fail "runner temp was not cleared"
pass "runner temp cleanup removes abandoned job temporaries"

grep -q 'clear_runner_tmp "pre-job"' "$ROOT/hooks/pre-job.sh" ||
  fail "pre-job does not clear stale runner temp"
grep -q 'clear_runner_tmp "post-job"' "$ROOT/hooks/post-job.sh" ||
  fail "post-job does not clear completed job temp"
pass "pre/post hooks own runner temp lifecycle"

printf '\nrunner temp tests passed\n'
