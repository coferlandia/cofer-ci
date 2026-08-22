#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
printf 'Este proyecto administra dos runners. Se redirige a unregister-runners.sh.\n'
exec "${SCRIPT_DIR}/unregister-runners.sh" "$@"
