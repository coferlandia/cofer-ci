#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecute con sudo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ ! -f /etc/coferlandia-ci-watchdog.env ]]; then
  cp "${PROJECT_DIR}/monitoring.env.example" /etc/coferlandia-ci-watchdog.env
  chmod 0600 /etc/coferlandia-ci-watchdog.env
  echo "Se creó /etc/coferlandia-ci-watchdog.env. Configure Telegram y GitHub si corresponde."
fi

for unit in \
  coferlandia-ci-watchdog.service \
  coferlandia-ci-watchdog.timer \
  coferlandia-ci-cleanup.service \
  coferlandia-ci-cleanup.timer; do
  sed "s|@@PROJECT_DIR@@|${PROJECT_DIR}|g" \
    "${PROJECT_DIR}/systemd/${unit}" \
    > "/etc/systemd/system/${unit}"
done

systemctl daemon-reload
systemctl enable --now coferlandia-ci-watchdog.timer
systemctl enable --now coferlandia-ci-cleanup.timer

echo
systemctl list-timers 'coferlandia-ci-*' --all
