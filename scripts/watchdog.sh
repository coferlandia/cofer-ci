#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

load_env
load_monitor_env

STATE_DIR="/var/lib/coferlandia-ci-watchdog"
STATE_FILE="${STATE_DIR}/state.env"
mkdir -p "$STATE_DIR"
chmod 0700 "$STATE_DIR"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
ALERT_REPEAT_SECONDS="${ALERT_REPEAT_SECONDS:-3600}"
RUNNER_OFFLINE_CHECKS_BEFORE_RESTART="${RUNNER_OFFLINE_CHECKS_BEFORE_RESTART:-2}"
RUNNER_RESTART_COOLDOWN_SECONDS="${RUNNER_RESTART_COOLDOWN_SECONDS:-1800}"

if ! [[ "$RUNNER_OFFLINE_CHECKS_BEFORE_RESTART" =~ ^[1-9][0-9]*$ ]]; then
  fatal "RUNNER_OFFLINE_CHECKS_BEFORE_RESTART debe ser un entero mayor o igual a 1"
fi
if ! [[ "$RUNNER_RESTART_COOLDOWN_SECONDS" =~ ^[0-9]+$ ]]; then
  fatal "RUNNER_RESTART_COOLDOWN_SECONDS debe ser un entero mayor o igual a 0"
fi

send_telegram() {
  local message="$1"
  if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
    warn "Telegram no configurado. Mensaje: ${message//$'\n'/ | }"
    return 0
  fi

  curl -fsS --max-time 15 \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${message}" \
    >/dev/null
}

runner_state_file() {
  printf '%s/%s.env' "$STATE_DIR" "$1"
}

load_runner_state() {
  local service="$1" file
  file="$(runner_state_file "$service")"
  runner_offline_checks=0
  runner_last_restart_at=0
  runner_recovery_pending=0
  if [[ -f "$file" ]]; then
    # Archivo generado exclusivamente por este watchdog dentro de un directorio 0700.
    # shellcheck disable=SC1090
    source "$file"
  fi
}

save_runner_state() {
  local service="$1" file
  file="$(runner_state_file "$service")"
  cat > "$file" <<EOF_RUNNER_STATE
runner_offline_checks=${runner_offline_checks}
runner_last_restart_at=${runner_last_restart_at}
runner_recovery_pending=${runner_recovery_pending}
EOF_RUNNER_STATE
  chmod 0600 "$file"
}

issues=()

if ! docker info >/dev/null 2>&1; then
  issues+=("Docker host no responde")
else
  for service in "${ALL_CI_SERVICES[@]}"; do
    cid="$(compose ps -q "$service" 2>/dev/null || true)"
    if [[ -z "$cid" ]]; then
      issues+=("Servicio ${service}: ausente")
      continue
    fi

    state="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
    health="$(
      docker inspect \
        -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' \
        "$cid" 2>/dev/null || echo unknown
    )"
    restarts="$(docker inspect -f '{{.RestartCount}}' "$cid" 2>/dev/null || echo 0)"

    [[ "$state" == "running" ]] || issues+=("Servicio ${service}: ${state}")
    [[ "$health" == "healthy" ]] || issues+=("Health ${service}: ${health}")
    (( restarts < 5 )) || issues+=("Servicio ${service}: ${restarts} reinicios")
  done

  for dind in "${DIND_SERVICES[@]}"; do
    compose exec -T "$dind" docker info >/dev/null 2>&1 || \
      issues+=("Daemon ${dind} no responde")
  done
fi

host_usage="$(df --output=pcent / | tail -n1 | tr -dc '0-9')"
if (( host_usage >= ${HOST_DISK_EMERGENCY_PERCENT:-92} )); then
  issues+=("Filesystem host / crítico: ${host_usage}%")
elif (( host_usage >= ${HOST_DISK_WARN_PERCENT:-85} )); then
  issues+=("Filesystem host / alto: ${host_usage}%")
fi

if ! mountpoint -q "${CI_STORAGE_ROOT}"; then
  issues+=("Filesystem CI no montado: ${CI_STORAGE_ROOT}")
else
  usage="$(storage_usage_percent)"
  if (( usage >= ${DISK_EMERGENCY_PERCENT:-90} )); then
    issues+=("Almacenamiento CI crítico: ${usage}%")
  elif (( usage >= ${DISK_WARN_PERCENT:-75} )); then
    issues+=("Almacenamiento CI alto: ${usage}%")
  fi
fi

now="$(date +%s)"

if [[ -n "${GITHUB_MONITOR_TOKEN:-}" ]]; then
  if [[ "${GITHUB_SCOPE_TYPE:-org}" == "repo" ]]; then
    api="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners?per_page=100"
  else
    api="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners?per_page=100"
  fi

  response="$(
    curl -fsS --max-time 15 \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer ${GITHUB_MONITOR_TOKEN}" \
      -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION:-2026-03-10}" \
      "$api" 2>/dev/null || true
  )"

  if ! jq -e '.runners | arrays' <<<"$response" >/dev/null 2>&1; then
    issues+=("No se pudo consultar el estado remoto de runners en GitHub")
  else
    for service in "${RUNNER_SERVICES[@]}"; do
      name="$(runner_name "$service")"
      remote_status="$(
        jq -r --arg name "$name" \
          '.runners[]? | select(.name == $name) | .status' \
          <<<"$response" |
          head -n1
      )"

      load_runner_state "$service"

      if [[ -z "$remote_status" ]]; then
        issues+=("GitHub no encuentra ${name}")
        save_runner_state "$service"
        continue
      fi

      if [[ "$remote_status" == "online" ]]; then
        if (( runner_offline_checks > 0 || runner_recovery_pending == 1 )); then
          log "${name} volvió a estar online"
        fi
        runner_offline_checks=0
        runner_recovery_pending=0
        save_runner_state "$service"
        continue
      fi

      if [[ "$remote_status" != "offline" ]]; then
        issues+=("GitHub ${name}: estado remoto inesperado ${remote_status}")
        save_runner_state "$service"
        continue
      fi

      if (( runner_recovery_pending == 1 )); then
        issues+=("GitHub ${name}: offline; auto-recuperación pendiente")
        save_runner_state "$service"
        continue
      fi

      runner_offline_checks=$((runner_offline_checks + 1))

      if (( runner_offline_checks < RUNNER_OFFLINE_CHECKS_BEFORE_RESTART )); then
        log "${name} offline (${runner_offline_checks}/${RUNNER_OFFLINE_CHECKS_BEFORE_RESTART}); esperando confirmación antes de reiniciar"
        save_runner_state "$service"
        continue
      fi

      seconds_since_restart=$((now - runner_last_restart_at))
      if (( runner_last_restart_at > 0 && seconds_since_restart < RUNNER_RESTART_COOLDOWN_SECONDS )); then
        issues+=("GitHub ${name}: offline; reinicio automático bloqueado por cooldown")
        save_runner_state "$service"
        continue
      fi

      if runner_is_busy "$service"; then
        issues+=("GitHub ${name}: offline pero ${service} tiene Runner.Worker activo; no se reinicia")
        save_runner_state "$service"
        continue
      fi

      cid="$(compose ps -q "$service" 2>/dev/null || true)"
      local_state=""
      local_health=""
      if [[ -n "$cid" ]]; then
        local_state="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || true)"
        local_health="$(
          docker inspect \
            -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' \
            "$cid" 2>/dev/null || true
        )"
      fi

      if [[ "$local_state" != "running" || "$local_health" != "healthy" ]]; then
        issues+=("GitHub ${name}: offline y ${service} no está localmente healthy; no se aplica self-healing remoto")
        save_runner_state "$service"
        continue
      fi

      runner_last_restart_at="$now"
      if compose restart "$service" >/dev/null 2>&1; then
        runner_offline_checks=0
        runner_recovery_pending=1
        issues+=("GitHub ${name}: offline; auto-recuperación pendiente")
        log "Se reinició únicamente ${service} para recuperar ${name}"
      else
        issues+=("GitHub ${name}: offline; falló el reinicio automático de ${service}")
      fi
      save_runner_state "$service"
    done
  fi
fi

previous_status="unknown"
previous_fingerprint=""
last_alert_at=0
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi

if (( ${#issues[@]} > 0 )); then
  details="$(printf '%s\n' "${issues[@]}" | sort -u)"
  fingerprint="$(printf '%s' "$details" | sha256sum | awk '{print $1}')"

  should_alert=false
  [[ "$previous_status" != "failed" ]] && should_alert=true
  [[ "$previous_fingerprint" != "$fingerprint" ]] && should_alert=true
  (( now - last_alert_at >= ALERT_REPEAT_SECONDS )) && should_alert=true

  if [[ "$should_alert" == true ]]; then
    message="🚨 Coferlandia CI presenta problemas

Servidor: $(hostname)
$(printf '• %s\n' "${issues[@]}")
Fecha: $(date --iso-8601=seconds)"
    send_telegram "$message" || warn "No se pudo enviar alerta a Telegram"
    last_alert_at="$now"
  fi

  cat > "$STATE_FILE" <<EOF_STATE
previous_status=failed
previous_fingerprint=${fingerprint}
last_alert_at=${last_alert_at}
EOF_STATE
  printf '%s\n' "$details" >&2
  exit 1
fi

if [[ "$previous_status" == "failed" ]]; then
  usage_text="n/d"
  mountpoint -q "${CI_STORAGE_ROOT}" && usage_text="$(storage_usage_percent)%"
  send_telegram "✅ Coferlandia CI se recuperó

Servidor: $(hostname)
Dos runners y dos Docker CI: healthy
Almacenamiento: ${usage_text}
Fecha: $(date --iso-8601=seconds)" || true
fi

cat > "$STATE_FILE" <<EOF_STATE
previous_status=healthy
previous_fingerprint=
last_alert_at=0
EOF_STATE

log "Watchdog OK"
