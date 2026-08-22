#!/usr/bin/env bash
set -Eeuo pipefail
read -r -s -p "Token del bot de Telegram: " token
printf '\n'
[[ -n "$token" ]] || { echo "Token vacío" >&2; exit 1; }

cat <<'EOF'
Antes de continuar:
1. Abra el chat con el bot.
2. Envíele /start o cualquier mensaje.
3. Para un grupo, agregue el bot y envíe un mensaje en el grupo.
EOF
read -r -p "Presione Enter para consultar getUpdates..."

curl -fsS "https://api.telegram.org/bot${token}/getUpdates" \
  | jq '.result[]? | {chat_id: (.message.chat.id // .channel_post.chat.id), chat: (.message.chat // .channel_post.chat), text: (.message.text // .channel_post.text)}'
