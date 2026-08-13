#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_AGENT_DEV="$APP_DIR/../mac-agent/dev"
PROJECT_PATH="$APP_DIR/CodexRemote.xcodeproj"
SCHEME="CodexRemote"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="${CODEX_REMOTE_DERIVED_DATA_PATH:-$APP_DIR/.build/DeviceDerivedData}"
DEVICE_SELECTOR=""
RELAY_URL=""
RESTART_STACK=0
DEFER_REFRESH=0
SHOULD_LAUNCH=1
LOCAL_RELAY_PORT="${CODEX_REMOTE_IPHONE_RELAY_PORT:-18768}"

usage() {
  cat <<'EOF'
Build, install, configure, and launch Codex Remote on a paired physical iPhone.
The existing iPhone Relay and Mac Agent are reused by default.

Usage:
  ./scripts/run-device.sh [--device <name-or-id>] [--relay-url <url>]
                          [--restart-stack] [--defer] [--no-launch]

Options:
  --device <name-or-id>  Select a device by name, CoreDevice identifier, or UDID.
  --relay-url <url>       Use an existing ws:// or wss:// Relay /ws/app endpoint.
  --restart-stack        Explicitly restart the local iPhone Relay and Mac Agent.
                          This is rejected when called from that Agent itself.
  --defer                Build and preflight now, then install and launch only after
                          the iPhone acknowledges the current Turn's completion.
  --no-launch            Install the app without launching it.
  -h, --help             Show this help.
EOF
}

resolve_lan_ipv4() {
  local network_interface
  local address

  network_interface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  if [[ -n "$network_interface" ]]; then
    address="$(ipconfig getifaddr "$network_interface" 2>/dev/null || true)"
    if [[ -n "$address" ]]; then
      echo "$address"
      return 0
    fi
  fi

  address="$(ifconfig 2>/dev/null | awk '$1 == "inet" && $2 !~ /^127\./ && $2 !~ /^169\.254\./ {print $2; exit}')"
  if [[ -n "$address" ]]; then
    echo "$address"
    return 0
  fi
  return 1
}

status_field() {
  local status_url="$1"
  local field="$2"
  curl -fsS "$status_url" 2>/dev/null \
    | plutil -extract "$field" raw -o - - 2>/dev/null \
    || true
}

write_one_shot_job_plist() {
  local plist_path="$1"
  local job_label="$2"
  local log_path="$3"
  shift 3

  plutil -create xml1 "$plist_path"
  plutil -insert Label -string "$job_label" "$plist_path"
  plutil -insert ProgramArguments -array "$plist_path"

  local argument_index=0
  local argument
  for argument in "$@"; do
    plutil -insert "ProgramArguments.$argument_index" -string "$argument" "$plist_path"
    argument_index=$((argument_index + 1))
  done

  plutil -insert ProcessType -string Background "$plist_path"
  plutil -insert StandardOutPath -string "$log_path" "$plist_path"
  plutil -insert StandardErrorPath -string "$log_path" "$plist_path"
}

running_inside_iphone_agent() {
  case "${CODEX_REMOTE_EXECUTION_ORIGIN:-auto}" in
    iphone-agent) return 0 ;;
    external) return 1 ;;
    auto) ;;
    *)
      echo "error: CODEX_REMOTE_EXECUTION_ORIGIN must be auto, external, or iphone-agent" >&2
      exit 2
      ;;
  esac

  local candidate_pid="$PPID"
  local command
  local parent_pid
  while [[ "$candidate_pid" =~ ^[0-9]+$ && "$candidate_pid" -gt 1 ]]; do
    command="$(ps -p "$candidate_pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == *"mac-agent serve"* && "$command" == *":$LOCAL_RELAY_PORT/ws/agent"* ]]; then
      return 0
    fi
    parent_pid="$(ps -p "$candidate_pid" -o ppid= 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$parent_pid" && "$parent_pid" != "$candidate_pid" ]] || break
    candidate_pid="$parent_pid"
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || { echo "error: --device requires a value" >&2; exit 2; }
      DEVICE_SELECTOR="$2"
      shift 2
      ;;
    --relay-url)
      [[ $# -ge 2 ]] || { echo "error: --relay-url requires a value" >&2; exit 2; }
      RELAY_URL="$2"
      shift 2
      ;;
    --restart-stack)
      RESTART_STACK=1
      shift
      ;;
    --defer)
      DEFER_REFRESH=1
      shift
      ;;
    --no-launch)
      SHOULD_LAUNCH=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$RESTART_STACK" -eq 1 && -n "$RELAY_URL" ]]; then
  echo "error: --restart-stack and --relay-url are mutually exclusive" >&2
  exit 2
fi
if [[ "$DEFER_REFRESH" -eq 1 && "$SHOULD_LAUNCH" -eq 0 ]]; then
  echo "error: --defer cannot be combined with --no-launch" >&2
  exit 2
fi

INSIDE_IPHONE_AGENT=0
if running_inside_iphone_agent; then
  INSIDE_IPHONE_AGENT=1
  DEFER_REFRESH=1
fi
if [[ "$INSIDE_IPHONE_AGENT" -eq 1 && "$RESTART_STACK" -eq 1 ]]; then
  echo "error: refusing to restart the iPhone Mac Agent from a Turn hosted by that Agent" >&2
  echo "Run this command from Codex Desktop or Terminal when a full stack restart is required." >&2
  exit 1
fi

for command_name in curl plutil xcodebuild xcrun; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command not found: $command_name" >&2
    exit 1
  fi
done
if [[ "$DEFER_REFRESH" -eq 1 ]] && ! command -v launchctl >/dev/null 2>&1; then
  echo "error: launchctl is required for a deferred device refresh" >&2
  exit 1
fi

DEVICES_JSON="$(mktemp /tmp/codexremote-devices.XXXXXX.json)"
STACK_OUTPUT="$(mktemp /tmp/codexremote-stack.XXXXXX.log)"
trap 'rm -f "$DEVICES_JSON" "$STACK_OUTPUT"' EXIT

if [[ "$RESTART_STACK" -eq 1 ]]; then
  if [[ ! -x "$MAC_AGENT_DEV" ]]; then
    echo "error: Mac Agent development script is missing or not executable: $MAC_AGENT_DEV" >&2
    exit 1
  fi
  echo "==> Restarting the iPhone Relay and Mac Agent stack"
  "$MAC_AGENT_DEV" iphone | tee "$STACK_OUTPUT"
  RELAY_URL="$(awk '/^LAN App WS:[[:space:]]*/ { print $NF; exit }' "$STACK_OUTPUT")"
elif [[ -z "$RELAY_URL" ]]; then
  LOCAL_STATUS_URL="http://127.0.0.1:$LOCAL_RELAY_PORT/status"
  if [[ "$(status_field "$LOCAL_STATUS_URL" agent_connected)" != "true" ]]; then
    echo "error: the local iPhone Mac Agent is not connected at $LOCAL_STATUS_URL" >&2
    echo "Start it externally with: ./scripts/run-device.sh --restart-stack" >&2
    exit 1
  fi
  LAN_IPV4="$(resolve_lan_ipv4 || true)"
  if [[ -z "$LAN_IPV4" ]]; then
    echo "error: no active LAN IPv4 address is available" >&2
    exit 1
  fi
  RELAY_URL="ws://$LAN_IPV4:$LOCAL_RELAY_PORT/ws/app"
  echo "==> Reusing the running iPhone Relay and Mac Agent"
else
  echo "==> Using the provided Relay without restarting local services"
fi

if [[ ! "$RELAY_URL" =~ ^wss?://[^/@]+/ws/app$ ]]; then
  echo "error: Relay URL must be an unauthenticated ws:// or wss:// URL ending in /ws/app" >&2
  exit 2
fi

echo "==> Using Relay URL: $RELAY_URL"
case "$RELAY_URL" in
  ws://*) RELAY_STATUS_URL="http://${RELAY_URL#ws://}" ;;
  wss://*) RELAY_STATUS_URL="https://${RELAY_URL#wss://}" ;;
esac
RELAY_STATUS_URL="${RELAY_STATUS_URL%/ws/app}/status"

if [[ "$(status_field "$RELAY_STATUS_URL" agent_connected)" != "true" ]]; then
  echo "error: the selected Relay has no connected Mac Agent: $RELAY_STATUS_URL" >&2
  exit 1
fi
if [[ "$DEFER_REFRESH" -eq 1 && "$(status_field "$RELAY_STATUS_URL" app_connected)" != "true" ]]; then
  echo "error: deferred refresh requires the current iPhone App to be connected" >&2
  exit 1
fi

xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null
DEVICE_COUNT="$(plutil -extract result.devices raw -o - "$DEVICES_JSON")"
MATCH_COUNT=0
DEVICE_NAME=""
DEVICE_UDID=""
CORE_DEVICE_ID=""

for ((index = 0; index < DEVICE_COUNT; index++)); do
  prefix="result.devices.$index"
  platform="$(plutil -extract "$prefix.hardwareProperties.platform" raw -o - "$DEVICES_JSON" 2>/dev/null || true)"
  reality="$(plutil -extract "$prefix.hardwareProperties.reality" raw -o - "$DEVICES_JSON" 2>/dev/null || true)"
  pairing_state="$(plutil -extract "$prefix.connectionProperties.pairingState" raw -o - "$DEVICES_JSON" 2>/dev/null || true)"
  if [[ "$platform" != "iOS" || "$reality" != "physical" || "$pairing_state" != "paired" ]]; then
    continue
  fi

  candidate_name="$(plutil -extract "$prefix.deviceProperties.name" raw -o - "$DEVICES_JSON")"
  candidate_udid="$(plutil -extract "$prefix.hardwareProperties.udid" raw -o - "$DEVICES_JSON")"
  candidate_core_id="$(plutil -extract "$prefix.identifier" raw -o - "$DEVICES_JSON")"
  if [[ -n "$DEVICE_SELECTOR" && "$DEVICE_SELECTOR" != "$candidate_name" && "$DEVICE_SELECTOR" != "$candidate_udid" && "$DEVICE_SELECTOR" != "$candidate_core_id" ]]; then
    continue
  fi

  MATCH_COUNT=$((MATCH_COUNT + 1))
  DEVICE_NAME="$candidate_name"
  DEVICE_UDID="$candidate_udid"
  CORE_DEVICE_ID="$candidate_core_id"
done

if [[ "$MATCH_COUNT" -eq 0 ]]; then
  if [[ -n "$DEVICE_SELECTOR" ]]; then
    echo "error: no paired physical iPhone matched '$DEVICE_SELECTOR'" >&2
  else
    echo "error: no paired physical iPhone is available" >&2
  fi
  echo "Connect and unlock the iPhone, then run: xcrun devicectl list devices" >&2
  exit 1
fi
if [[ "$MATCH_COUNT" -gt 1 ]]; then
  echo "error: multiple paired iPhones found; select one with --device <name-or-id>" >&2
  xcrun devicectl list devices
  exit 1
fi

echo "==> Building $SCHEME for $DEVICE_NAME ($DEVICE_UDID)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/CodexRemote.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Info.plist")"

if [[ "$DEFER_REFRESH" -eq 1 ]]; then
  PREVIOUS_TURN_ACK="$(status_field "$RELAY_STATUS_URL" last_turn_acknowledged)"
  PREVIOUS_APP_CONNECTION_ID="$(status_field "$RELAY_STATUS_URL" app_connection_id)"
  JOB_ID="$(date +%s)-$$"
  JOB_LABEL="com.ai-coding-remote.device-refresh.$JOB_ID"
  RESULT_DIR="${CODEX_REMOTE_REFRESH_RESULT_DIR:-$APP_DIR/.build/device-refresh}"
  RESULT_FILE="$RESULT_DIR/$JOB_ID.status"
  LOG_FILE="$RESULT_DIR/$JOB_ID.log"
  JOB_PLIST="$RESULT_DIR/$JOB_ID.plist"
  mkdir -p "$RESULT_DIR"

  write_one_shot_job_plist \
    "$JOB_PLIST" \
    "$JOB_LABEL" \
    "$LOG_FILE" \
    "$SCRIPT_DIR/complete-device-refresh.sh" \
    --device "$CORE_DEVICE_ID" \
    --device-name "$DEVICE_NAME" \
    --app-path "$APP_PATH" \
    --bundle-id "$BUNDLE_ID" \
    --relay-url "$RELAY_URL" \
    --status-url "$RELAY_STATUS_URL" \
    --previous-turn-ack "$PREVIOUS_TURN_ACK" \
    --previous-app-connection-id "$PREVIOUS_APP_CONNECTION_ID" \
    --result-file "$RESULT_FILE" \
    --job-label "$JOB_LABEL" \
    --job-plist "$JOB_PLIST"

  LAUNCHD_DOMAIN="gui/$(id -u)"
  if ! launchctl bootstrap "$LAUNCHD_DOMAIN" "$JOB_PLIST"; then
    rm -f "$JOB_PLIST"
    echo "error: failed to load deferred refresh job $JOB_LABEL" >&2
    exit 1
  fi
  if ! launchctl kickstart "$LAUNCHD_DOMAIN/$JOB_LABEL"; then
    launchctl bootout "$LAUNCHD_DOMAIN/$JOB_LABEL" >/dev/null 2>&1 || true
    rm -f "$JOB_PLIST"
    echo "error: failed to start deferred refresh job $JOB_LABEL" >&2
    exit 1
  fi

  echo "==> Environment ready; deferred iPhone refresh scheduled"
  echo "Deferred log: $LOG_FILE"
  echo "Deferred status: $RESULT_FILE"
  echo "Complete the current Turn now. Installation starts after the iPhone acknowledges completion."
  exit 0
fi

PREVIOUS_APP_CONNECTION_ID="$(status_field "$RELAY_STATUS_URL" app_connection_id)"
echo "==> Installing $BUNDLE_ID on $DEVICE_NAME"
xcrun devicectl device install app --device "$CORE_DEVICE_ID" "$APP_PATH"

if [[ "$SHOULD_LAUNCH" -eq 1 ]]; then
  echo "==> Launching $BUNDLE_ID on $DEVICE_NAME"
  xcrun devicectl device process launch \
    --device "$CORE_DEVICE_ID" \
    --terminate-existing \
    "$BUNDLE_ID" \
    --relay-url "$RELAY_URL"

  app_connected="false"
  for ((attempt = 0; attempt < 100; attempt++)); do
    app_connected="$(status_field "$RELAY_STATUS_URL" app_connected)"
    app_connection_id="$(status_field "$RELAY_STATUS_URL" app_connection_id)"
    if [[ "$app_connected" == "true" && ( -z "$PREVIOUS_APP_CONNECTION_ID" || "$app_connection_id" != "$PREVIOUS_APP_CONNECTION_ID" ) ]]; then
      echo "==> iPhone app connected to Relay"
      break
    fi
    sleep 0.1
  done
  if [[ "$app_connected" != "true" || ( -n "$PREVIOUS_APP_CONNECTION_ID" && "$app_connection_id" == "$PREVIOUS_APP_CONNECTION_ID" ) ]]; then
    echo "error: the app launched but did not establish a new Relay connection within 10 seconds" >&2
    exit 1
  fi
fi

echo "==> Done"
