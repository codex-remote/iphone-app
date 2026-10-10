#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d /tmp/codexremote-device-test.XXXXXX)"
FAKE_BIN="$TEMP_DIR/bin"
COMMAND_LOG="$TEMP_DIR/commands.log"
DERIVED_DATA_PATH="$TEMP_DIR/DerivedData"
mkdir -p "$FAKE_BIN"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat >"$FAKE_BIN/curl" <<'EOF'
#!/bin/bash
echo '{"status":"ok","contract_version":"run-server-v1"}'
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
  if [[ "$1" == "-derivedDataPath" ]]; then derived="$2"; shift 2; else shift; fi
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
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--json-output" ]]; then output="$2"; break; fi
    shift
  done
  cat >"$output" <<'JSON'
{"result":{"devices":[{"hardwareProperties":{"platform":"iOS","reality":"physical","udid":"device-udid"},"connectionProperties":{"pairingState":"paired"},"deviceProperties":{"name":"Test iPhone"},"identifier":"core-device-id"}]}}
JSON
fi
EOF

cat >"$FAKE_BIN/devrun" <<'EOF'
#!/bin/bash
echo "devrun $*" >>"$CODEX_REMOTE_TEST_COMMAND_LOG"
EOF

chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export CODEX_REMOTE_TEST_COMMAND_LOG="$COMMAND_LOG"
export CODEX_REMOTE_DERIVED_DATA_PATH="$DERIVED_DATA_PATH"

CODEX_REMOTE_EXECUTION_ORIGIN=external "$APP_DIR/scripts/run-device.sh" >"$TEMP_DIR/default.out"
grep -q "Using Runtime URL: http://192.168.1.25:18874" "$TEMP_DIR/default.out"
grep -q "device install app" "$COMMAND_LOG"
grep -q "device process launch.*--runtime-url http://192.168.1.25:18874" "$COMMAND_LOG"
if grep -q "devrun crweb" "$COMMAND_LOG"; then
  echo "default deployment restarted the Runtime" >&2
  exit 1
fi

if CODEX_REMOTE_EXECUTION_ORIGIN=iphone-agent "$APP_DIR/scripts/run-device.sh" >"$TEMP_DIR/self.out" 2>&1; then
  echo "self replacement was not rejected" >&2
  exit 1
fi
grep -q "refusing to replace the iPhone client or Runtime" "$TEMP_DIR/self.out"

: >"$COMMAND_LOG"
CODEX_REMOTE_EXECUTION_ORIGIN=external "$APP_DIR/scripts/run-device.sh" --restart-stack --no-launch >"$TEMP_DIR/restart.out"
grep -q '^devrun crweb$' "$COMMAND_LOG"
grep -q "device install app" "$COMMAND_LOG"
if grep -q "device process launch" "$COMMAND_LOG"; then
  echo "--no-launch started the app" >&2
  exit 1
fi

echo "run-device tests passed"
