#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
printf 'Este proyecto registra dos runners. Se redirige a register-runners.sh.\n'
exec "${SCRIPT_DIR}/register-runners.sh" "$@"
