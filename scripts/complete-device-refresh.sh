#!/bin/bash

set -euo pipefail

DEVICE_ID=""
DEVICE_NAME=""
APP_PATH=""
BUNDLE_ID=""
RELAY_URL=""
STATUS_URL=""
PREVIOUS_TURN_ACK=""
PREVIOUS_APP_CONNECTION_ID=""
RESULT_FILE=""
JOB_LABEL=""
JOB_PLIST=""
ACK_TIMEOUT_SECONDS="${CODEX_REMOTE_ACK_TIMEOUT_SECONDS:-180}"
TERMINAL_RESULT_WRITTEN=0

status_field() {
  local field="$1"
  curl -fsS "$STATUS_URL" 2>/dev/null \
    | plutil -extract "$field" raw -o - - 2>/dev/null \
    || true
}

write_result() {
  local status="$1"
  local message="$2"
  local temporary="$RESULT_FILE.tmp.$$"
  {
    echo "status=$status"
    echo "message=$message"
    echo "updated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } >"$temporary"
  mv "$temporary" "$RESULT_FILE"
  case "$status" in
    completed|cancelled|failed) TERMINAL_RESULT_WRITTEN=1 ;;
  esac
}

cleanup() {
  local exit_code=$?
  trap - EXIT

  if [[ "$exit_code" -ne 0 && "$TERMINAL_RESULT_WRITTEN" -eq 0 && -n "$RESULT_FILE" ]]; then
    write_result "failed" "Deferred refresh failed; inspect the matching log for details."
  fi
  if [[ -n "$JOB_PLIST" ]]; then
    rm -f "$JOB_PLIST"
  fi
  if [[ "$JOB_LABEL" == com.ai-coding-remote.device-refresh.* ]]; then
    launchctl bootout "gui/$(id -u)/$JOB_LABEL" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_ID="$2"; shift 2 ;;
    --device-name) DEVICE_NAME="$2"; shift 2 ;;
    --app-path) APP_PATH="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --relay-url) RELAY_URL="$2"; shift 2 ;;
    --status-url) STATUS_URL="$2"; shift 2 ;;
    --previous-turn-ack) PREVIOUS_TURN_ACK="$2"; shift 2 ;;
    --previous-app-connection-id) PREVIOUS_APP_CONNECTION_ID="$2"; shift 2 ;;
    --result-file) RESULT_FILE="$2"; shift 2 ;;
    --job-label) JOB_LABEL="$2"; shift 2 ;;
    --job-plist) JOB_PLIST="$2"; shift 2 ;;
    *) echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$DEVICE_ID" || -z "$APP_PATH" || -z "$BUNDLE_ID" || -z "$RELAY_URL" || -z "$STATUS_URL" || -z "$RESULT_FILE" ]]; then
  echo "error: incomplete deferred refresh request" >&2
  exit 2
fi

trap cleanup EXIT

mkdir -p "$(dirname "$RESULT_FILE")"
write_result "waiting" "Waiting for the iPhone to acknowledge Turn completion."

acknowledged_turn=""
acknowledged_status=""
for ((attempt = 0; attempt < ACK_TIMEOUT_SECONDS * 10; attempt++)); do
  acknowledged_turn="$(status_field last_turn_acknowledged)"
  acknowledged_status="$(status_field last_turn_acknowledged_status)"
  if [[ -n "$acknowledged_turn" && "$acknowledged_turn" != "$PREVIOUS_TURN_ACK" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -z "$acknowledged_turn" || "$acknowledged_turn" == "$PREVIOUS_TURN_ACK" ]]; then
  write_result "failed" "Timed out waiting for Turn completion acknowledgement."
  echo "error: timed out waiting for Turn completion acknowledgement" >&2
  exit 1
fi
if [[ "$acknowledged_status" != "completed" ]]; then
  write_result "cancelled" "Turn ended with status $acknowledged_status; the iPhone was not refreshed."
  echo "==> Turn ended with $acknowledged_status; cancelling deferred refresh"
  exit 0
fi

write_result "running" "Installing and launching Codex Remote on $DEVICE_NAME."
echo "==> Installing $BUNDLE_ID on $DEVICE_NAME after Turn $acknowledged_turn completed"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "==> Launching $BUNDLE_ID on $DEVICE_NAME"
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  "$BUNDLE_ID" \
  --relay-url "$RELAY_URL"

app_connected="false"
app_connection_id=""
for ((attempt = 0; attempt < 100; attempt++)); do
  app_connected="$(status_field app_connected)"
  app_connection_id="$(status_field app_connection_id)"
  if [[ "$app_connected" == "true" && ( -z "$PREVIOUS_APP_CONNECTION_ID" || "$app_connection_id" != "$PREVIOUS_APP_CONNECTION_ID" ) ]]; then
    write_result "completed" "Codex Remote refreshed and reconnected to the Relay."
    echo "==> iPhone app connected to Relay"
    exit 0
  fi
  sleep 0.1
done

write_result "failed" "The refreshed app did not establish a new Relay connection within 10 seconds."
echo "error: refreshed app did not establish a new Relay connection" >&2
exit 1
