#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecute este script con sudo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "${PROJECT_DIR}/.env.example" "$ENV_FILE"
  echo "Se creó ${ENV_FILE}. Revíselo antes de registrar los runners."
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${CI_STORAGE_ROOT:=/srv/coferlandia-ci}"
: "${CI_STORAGE_IMAGE:=/var/lib/coferlandia-ci.img}"
: "${CI_STORAGE_SIZE:=30G}"

for cmd in truncate mkfs.ext4 mount findmnt numfmt; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Falta ${cmd}. Instale util-linux y e2fsprogs." >&2
    exit 1
  }
done

mkdir -p "$(dirname "$CI_STORAGE_IMAGE")" "$CI_STORAGE_ROOT"

if [[ ! -f "$CI_STORAGE_IMAGE" ]]; then
  requested_bytes="$(numfmt --from=iec "$CI_STORAGE_SIZE")"
  available_bytes="$(
    df --output=avail -B1 "$(dirname "$CI_STORAGE_IMAGE")" |
      tail -n1 |
      tr -d ' '
  )"
  reserve_bytes="$(numfmt --from=iec 5G)"

  if (( requested_bytes > available_bytes - reserve_bytes )); then
    echo "El tamaño ${CI_STORAGE_SIZE} no deja al menos 5 GB libres en el filesystem host." >&2
    echo "Disponible actualmente: $(numfmt --to=iec "$available_bytes")" >&2
    exit 1
  fi

  echo "Creando filesystem limitado de ${CI_STORAGE_SIZE} en ${CI_STORAGE_IMAGE}"
  truncate -s "$CI_STORAGE_SIZE" "$CI_STORAGE_IMAGE"
  mkfs.ext4 -F -L coferlandia-ci "$CI_STORAGE_IMAGE" >/dev/null
fi

fstab_line="${CI_STORAGE_IMAGE} ${CI_STORAGE_ROOT} ext4 loop,noatime,nofail 0 2"
if ! grep -Fq "${CI_STORAGE_IMAGE} ${CI_STORAGE_ROOT}" /etc/fstab; then
  printf '%s\n' "$fstab_line" >> /etc/fstab
fi

if ! mountpoint -q "$CI_STORAGE_ROOT"; then
  mount "$CI_STORAGE_ROOT"
fi

for index in 01 02; do
  mkdir -p \
    "$CI_STORAGE_ROOT/runner-${index}" \
    "$CI_STORAGE_ROOT/work-${index}" \
    "$CI_STORAGE_ROOT/cache-${index}/toolcache" \
    "$CI_STORAGE_ROOT/cache-${index}/nuget" \
    "$CI_STORAGE_ROOT/cache-${index}/npm" \
    "$CI_STORAGE_ROOT/cache-${index}/pip" \
    "$CI_STORAGE_ROOT/docker-${index}" \
    "$CI_STORAGE_ROOT/certs-${index}"

  chown -R 1001:123 \
    "$CI_STORAGE_ROOT/runner-${index}" \
    "$CI_STORAGE_ROOT/work-${index}" \
    "$CI_STORAGE_ROOT/cache-${index}"

  chmod 0711 \
    "$CI_STORAGE_ROOT/runner-${index}" \
    "$CI_STORAGE_ROOT/work-${index}" \
    "$CI_STORAGE_ROOT/cache-${index}"
done

chmod 0755 "$CI_STORAGE_ROOT"
chmod +x \
  "$PROJECT_DIR"/runner/*.sh \
  "$PROJECT_DIR"/hooks/*.sh \
  "$PROJECT_DIR"/scripts/*.sh

cat <<EOF_MESSAGE

Almacenamiento preparado:
  Imagen:  ${CI_STORAGE_IMAGE}
  Montaje: ${CI_STORAGE_ROOT}
  Límite:  ${CI_STORAGE_SIZE}
  Runners: 2, con datos, workspaces, cachés y Docker CI independientes

Siguiente paso:
  1. Edite ${ENV_FILE}
  2. Ejecute ${PROJECT_DIR}/scripts/register-runners.sh
EOF_MESSAGE
