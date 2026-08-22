#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecute con sudo." >&2
  exit 1
fi

systemctl disable --now coferlandia-ci-watchdog.timer 2>/dev/null || true
systemctl disable --now coferlandia-ci-cleanup.timer 2>/dev/null || true
rm -f \
  /etc/systemd/system/coferlandia-ci-watchdog.service \
  /etc/systemd/system/coferlandia-ci-watchdog.timer \
  /etc/systemd/system/coferlandia-ci-cleanup.service \
  /etc/systemd/system/coferlandia-ci-cleanup.timer
systemctl daemon-reload
