#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d /tmp/codexremote-device-test.XXXXXX)"
FAKE_BIN="$TEMP_DIR/bin"
COMMAND_LOG="$TEMP_DIR/commands.log"
STATUS_FILE="$TEMP_DIR/status.json"
DERIVED_DATA_PATH="$TEMP_DIR/DerivedData"
RESULT_DIR="$TEMP_DIR/results"
JOB_PLIST_RECORD="$TEMP_DIR/job-plist-path"
JOB_START_LOG="$TEMP_DIR/job-starts.log"
mkdir -p "$FAKE_BIN" "$RESULT_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

write_status() {
  local ack="$1"
  local ack_status="$2"
  local connection_id="$3"
  cat >"$STATUS_FILE" <<EOF
{"app_connected":true,"agent_connected":true,"app_connection_id":$connection_id,"last_turn_acknowledged":"$ack","last_turn_acknowledged_status":"$ack_status"}
EOF
}

cat >"$FAKE_BIN/curl" <<'EOF'
#!/bin/bash
cat "$CODEX_REMOTE_TEST_STATUS_FILE"
EOF

cat >"$FAKE_BIN/route" <<'EOF'
#!/bin/bash
echo "interface: en0"
EOF

cat >"$FAKE_BIN/ipconfig" <<'EOF'
#!/bin/bash
echo "192.168.1.25"
EOF

cat >"$FAKE_BIN/ifconfig" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$FAKE_BIN/xcodebuild" <<'EOF'
#!/bin/bash
echo "xcodebuild $*" >>"$CODEX_REMOTE_TEST_COMMAND_LOG"
derived=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-derivedDataPath" ]]; then
    derived="$2"
    shift 2
  else
    shift
  fi
done
app="$derived/Build/Products/Debug-iphoneos/CodexRemote.app"
mkdir -p "$app"
/usr/bin/plutil -create xml1 "$app/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.example.CodexRemote "$app/Info.plist"
EOF

cat >"$FAKE_BIN/xcrun" <<'EOF'
#!/bin/bash
echo "xcrun $*" >>"$CODEX_REMOTE_TEST_COMMAND_LOG"
if [[ "$1 $2 $3" == "devicectl list devices" ]]; then
  output=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--json-output" ]]; then
      output="$2"
      break
    fi
    shift
  done
  cat >"$output" <<'JSON'
{"result":{"devices":[{"hardwareProperties":{"platform":"iOS","reality":"physical","udid":"device-udid"},"connectionProperties":{"pairingState":"paired"},"deviceProperties":{"name":"Test iPhone"},"identifier":"core-device-id"}]}}
JSON
  exit 0
fi
if [[ "$*" == *"device process launch"* ]]; then
  cat >"$CODEX_REMOTE_TEST_STATUS_FILE.tmp" <<'JSON'
{"app_connected":true,"agent_connected":true,"app_connection_id":2,"last_turn_acknowledged":"turn-new","last_turn_acknowledged_status":"completed"}
JSON
  mv "$CODEX_REMOTE_TEST_STATUS_FILE.tmp" "$CODEX_REMOTE_TEST_STATUS_FILE"
fi
EOF

cat >"$FAKE_BIN/launchctl" <<'EOF'
#!/bin/bash
echo "launchctl $*" >>"$CODEX_REMOTE_TEST_COMMAND_LOG"
case "$1" in
  bootstrap)
    echo "$3" >"$CODEX_REMOTE_TEST_JOB_PLIST_RECORD"
    ;;
  kickstart)
    job_plist="$(cat "$CODEX_REMOTE_TEST_JOB_PLIST_RECORD")"
    argument_count="$(/usr/bin/plutil -extract ProgramArguments raw -o - "$job_plist")"
    arguments=()
    for ((index = 0; index < argument_count; index++)); do
      arguments+=("$(/usr/bin/plutil -extract "ProgramArguments.$index" raw -o - "$job_plist")")
    done
    stdout_path="$(/usr/bin/plutil -extract StandardOutPath raw -o - "$job_plist")"
    echo started >>"$CODEX_REMOTE_TEST_JOB_START_LOG"
    "${arguments[@]}" >"$stdout_path" 2>&1 &
    ;;
esac
EOF

chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export CODEX_REMOTE_TEST_STATUS_FILE="$STATUS_FILE"
export CODEX_REMOTE_TEST_COMMAND_LOG="$COMMAND_LOG"
export CODEX_REMOTE_DERIVED_DATA_PATH="$DERIVED_DATA_PATH"
export CODEX_REMOTE_REFRESH_RESULT_DIR="$RESULT_DIR"
export CODEX_REMOTE_TEST_JOB_PLIST_RECORD="$JOB_PLIST_RECORD"
export CODEX_REMOTE_TEST_JOB_START_LOG="$JOB_START_LOG"

write_status "turn-old" "completed" 1
CODEX_REMOTE_EXECUTION_ORIGIN=external "$APP_DIR/scripts/run-device.sh" >"$TEMP_DIR/default.out"
grep -q "Reusing the running iPhone Relay and Mac Agent" "$TEMP_DIR/default.out"
grep -q "device install app" "$COMMAND_LOG"
grep -q "device process launch" "$COMMAND_LOG"
if grep -q "mac-agent/dev" "$COMMAND_LOG"; then
  echo "default deployment restarted the Mac Agent" >&2
  exit 1
fi

: >"$COMMAND_LOG"
write_status "turn-old" "completed" 1
CODEX_REMOTE_EXECUTION_ORIGIN=iphone-agent "$APP_DIR/scripts/run-device.sh" >"$TEMP_DIR/deferred.out"
grep -q "deferred iPhone refresh scheduled" "$TEMP_DIR/deferred.out"
grep -q "launchctl bootstrap" "$COMMAND_LOG"
grep -q "launchctl kickstart" "$COMMAND_LOG"
if grep -q "launchctl submit" "$COMMAND_LOG"; then
  echo "deferred deployment used a keepalive submitted job" >&2
  exit 1
fi
job_plist="$(cat "$JOB_PLIST_RECORD")"
if /usr/bin/plutil -extract KeepAlive raw -o - "$job_plist" >/dev/null 2>&1; then
  echo "deferred deployment configured KeepAlive" >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$job_plist")" != "$APP_DIR/scripts/complete-device-refresh.sh" ]]; then
  echo "deferred deployment configured the wrong helper" >&2
  exit 1
fi
if grep -q "device install app\|device process launch" "$COMMAND_LOG"; then
  echo "deferred deployment touched the iPhone before Turn acknowledgement" >&2
  exit 1
fi

if CODEX_REMOTE_EXECUTION_ORIGIN=iphone-agent "$APP_DIR/scripts/run-device.sh" --restart-stack >"$TEMP_DIR/restart.out" 2>&1; then
  echo "self-restart was not rejected" >&2
  exit 1
fi
grep -q "refusing to restart the iPhone Mac Agent" "$TEMP_DIR/restart.out"

write_status "turn-new" "completed" 1
refresh_status="$(find "$RESULT_DIR" -name '*.status' -print -quit)"
for ((attempt = 0; attempt < 40; attempt++)); do
  if [[ -n "$refresh_status" ]] && grep -q "status=completed" "$refresh_status"; then
    break
  fi
  sleep 0.1
  refresh_status="$(find "$RESULT_DIR" -name '*.status' -print -quit)"
done
grep -q "status=completed" "$refresh_status"
[[ "$(grep -c '^xcrun device install app' "$COMMAND_LOG")" -eq 1 ]]
[[ "$(grep -c '^xcrun device process launch' "$COMMAND_LOG")" -eq 1 ]]
[[ "$(wc -l <"$JOB_START_LOG" | tr -d '[:space:]')" -eq 1 ]]
grep -q "launchctl bootout" "$COMMAND_LOG"

echo "run-device tests passed"
