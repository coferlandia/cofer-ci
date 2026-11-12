#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$ROOT/.coferlandia/ci/profile.json"
WORKFLOW="$ROOT/.github/workflows/validate.yml"

fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

[[ -s "$PROFILE" ]] || fail "missing CI profile"
[[ -s "$WORKFLOW" ]] || fail "missing qualification workflow"

python - "$PROFILE" <<'PY'
import hashlib
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    profile = json.load(f)

required = {
    "schema_version", "profile_version", "repository", "documentation",
    "local", "github", "identity", "exceptions", "fingerprint"
}
assert set(profile) == required, f"profile fields mismatch: {set(profile) ^ required}"
assert profile["schema_version"] == 1
assert profile["repository"] == "coferlandia/cofer-ci"
assert profile["local"]["qualification_commands"] == [{
    "id": "package-validation",
    "command": "./scripts/validate-package.sh",
    "purpose": "validate Bash syntax, Docker Compose contract, storage hygiene regressions, documentation and package invariants"
}]
assert profile["local"]["required_services"] == ["Docker Engine"]
assert profile["local"]["environment"] == []
submission = profile["github"]["submission"]
assert submission["mode"] == "existing-pr-events"
assert submission["workflow"] == ".github/workflows/validate.yml"
assert submission["activation"] == {"kind": "ready-for-review"}
assert profile["github"]["gates"] == [{
    "id": "package-validation",
    "kind": "workflow",
    "workflow": ".github/workflows/validate.yml",
    "allowed_conclusions": ["success"]
}]
assert profile["github"]["merge_group"] == {
    "supported": False,
    "authoritative_when_present": False,
}
assert profile["identity"] == {"base_sensitive": True, "profile_sensitive": True}
assert profile["exceptions"] == []

fingerprint = profile.pop("fingerprint")
canonical = json.dumps(profile, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
actual = hashlib.sha256(canonical.encode()).hexdigest()
assert actual == fingerprint, f"fingerprint mismatch: {actual} != {fingerprint}"
PY
pass "CI profile contract and fingerprint are coherent"

grep -Fq 'types: [opened, synchronize, reopened, ready_for_review]' "$WORKFLOW" ||
  fail "qualification workflow is not activated by ready_for_review"
pass "Draft -> Ready activation has a matching pull_request event"

printf '\nCI profile tests passed\n'
