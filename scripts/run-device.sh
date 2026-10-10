#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$APP_DIR/CodexRemote.xcodeproj"
SCHEME="CodexRemote"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="${CODEX_REMOTE_DERIVED_DATA_PATH:-$APP_DIR/.build/DeviceDerivedData}"
DEVICE_SELECTOR=""
RUNTIME_URL=""
RESTART_STACK=0
SHOULD_LAUNCH=1
LOCAL_GATEWAY_PORT="${CODEX_REMOTE_RUNTIME_GATEWAY_PORT:-18874}"
LOCAL_RUN_SERVER_PORT="${CODEX_REMOTE_RUN_SERVER_PORT:-18875}"

usage() {
  cat <<'EOF'
Build, install, configure, and launch Codex Remote on a paired physical iPhone.
The existing Runtime Gateway, Run Server, and Mac Agent are reused by default.

Usage:
  ./scripts/run-device.sh [--device <name-or-id>] [--runtime-url <url>]
                          [--restart-stack] [--no-launch]

Options:
  --device <name-or-id>  Select a device by name, CoreDevice identifier, or UDID.
  --runtime-url <url>     Use an existing http:// or https:// Runtime Gateway.
  --restart-stack        Rebuild and restart the source Runtime through devrun crweb.
                          This is rejected when called from the matching Agent itself.
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
    if [[ "$command" == *"mac-agent serve"* && "$command" == *":$LOCAL_RUN_SERVER_PORT/ws/agent"* ]]; then
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
    --runtime-url)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 2; }
      RUNTIME_URL="$2"
      shift 2
      ;;
    --restart-stack)
      RESTART_STACK=1
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

if [[ "$RESTART_STACK" -eq 1 && -n "$RUNTIME_URL" ]]; then
  echo "error: --restart-stack and --runtime-url are mutually exclusive" >&2
  exit 2
fi

INSIDE_IPHONE_AGENT=0
if running_inside_iphone_agent; then
  INSIDE_IPHONE_AGENT=1
fi
if [[ "$INSIDE_IPHONE_AGENT" -eq 1 ]]; then
  echo "error: refusing to replace the iPhone client or Runtime from a Turn hosted by the matching Agent" >&2
  echo "Finish this Turn, then run the command from Codex Desktop or Terminal." >&2
  exit 1
fi

for command_name in curl plutil xcodebuild xcrun; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command not found: $command_name" >&2
    exit 1
  fi
done
DEVICES_JSON="$(mktemp /tmp/codexremote-devices.XXXXXX.json)"
trap 'rm -f "$DEVICES_JSON"' EXIT

if [[ "$RESTART_STACK" -eq 1 ]]; then
  if ! command -v devrun >/dev/null 2>&1; then
    echo "error: devrun is required for --restart-stack" >&2
    exit 1
  fi
  echo "==> Rebuilding and restarting the source Runtime stack"
  devrun crweb
fi

if [[ -z "$RUNTIME_URL" ]]; then
  LAN_IPV4="$(resolve_lan_ipv4 || true)"
  if [[ -z "$LAN_IPV4" ]]; then
    echo "error: no active LAN IPv4 address is available" >&2
    exit 1
  fi
  RUNTIME_URL="http://$LAN_IPV4:$LOCAL_GATEWAY_PORT"
  echo "==> Using the source Runtime Gateway"
else
  echo "==> Using the provided Runtime Gateway"
fi

if [[ ! "$RUNTIME_URL" =~ ^https?://[^/@]+/?$ ]]; then
  echo "error: Runtime URL must be an http:// or https:// Gateway origin without credentials or a path" >&2
  exit 2
fi

RUNTIME_URL="${RUNTIME_URL%/}"
GATEWAY_STATUS_URL="$RUNTIME_URL/gateway/healthz"
echo "==> Using Runtime URL: $RUNTIME_URL"
if [[ "$(status_field "$GATEWAY_STATUS_URL" status)" != "ok" ]]; then
  echo "error: Runtime Gateway is not healthy: $GATEWAY_STATUS_URL" >&2
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

echo "==> Installing $BUNDLE_ID on $DEVICE_NAME"
xcrun devicectl device install app --device "$CORE_DEVICE_ID" "$APP_PATH"

if [[ "$SHOULD_LAUNCH" -eq 1 ]]; then
  echo "==> Launching $BUNDLE_ID on $DEVICE_NAME"
  xcrun devicectl device process launch \
    --device "$CORE_DEVICE_ID" \
    --terminate-existing \
    "$BUNDLE_ID" \
    --runtime-url "$RUNTIME_URL"
fi

echo "==> Done"
