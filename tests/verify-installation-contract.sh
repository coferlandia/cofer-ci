#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/scripts/verify-installation.sh"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

test -f "$TARGET" || fail "missing verify-installation.sh"
bash -n "$TARGET"

grep -Fq 'sh -lc' "$TARGET" ||
  fail "runner flock checks must execute through a shell"

if grep -Fq 'compose exec -T "$runner" command -v flock' "$TARGET"; then
  fail "heavy runner flock check still execs shell builtin directly"
fi

if grep -Fq 'compose exec -T "$gate_runner" command -v flock' "$TARGET"; then
  fail "gate runner flock check still execs shell builtin directly"
fi

grep -Fq 'compose exec -T "$runner" test -x /opt/runner-hooks/pre-job.sh' "$TARGET" ||
  fail "heavy runner live verification must prove pre-job hook exists and is executable"
grep -Fq 'compose exec -T "$runner" test -x /opt/runner-hooks/post-job.sh' "$TARGET" ||
  fail "heavy runner live verification must prove post-job hook exists and is executable"
grep -Fq 'compose exec -T "$gate_runner" test -x /opt/runner-hooks/pre-job.sh' "$TARGET" ||
  fail "Gate live verification must prove pre-job hook exists and is executable"
grep -Fq 'compose exec -T "$gate_runner" test -x /opt/runner-hooks/post-job.sh' "$TARGET" ||
  fail "Gate live verification must prove post-job hook exists and is executable"

echo "result=VERIFY_INSTALLATION_HOOK_CONTRACT_READY"
