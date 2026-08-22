#!/usr/bin/env bash
set -Eeuo pipefail
ENV_FILE="/etc/coferlandia-ci-watchdog.env"
[[ -f "$ENV_FILE" ]] || { echo "No existe ${ENV_FILE}" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a
: "${TELEGRAM_BOT_TOKEN:?Falta TELEGRAM_BOT_TOKEN}"
: "${TELEGRAM_CHAT_ID:?Falta TELEGRAM_CHAT_ID}"

curl -fsS --max-time 15 \
  --request POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=✅ Prueba de monitoreo Coferlandia CI en $(hostname) - $(date --iso-8601=seconds)" \
  | jq .
