#!/bin/zsh
set -euo pipefail

if (( $# < 2 )); then
  print -u2 "Usage: $0 DEVICE_ID OUTPUT_DIRECTORY"
  print -u2 "DEVICE_ID may be a booted Simulator UDID or a connected CoreDevice identifier."
  exit 64
fi

device_id="$1"
output_directory="$2"
bundle_id="com.leehooo.codexremote.dev925r8v9794"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
capture_directory="${output_directory}/codexremote-diagnostics-${timestamp}"

mkdir -p "$capture_directory"

if xcrun simctl list devices booted | rg -q "$device_id"; then
  xcrun simctl diagnose \
    --udid "$device_id" \
    --output "$capture_directory" \
    --timeout 120 \
    -b
  xcrun simctl get_app_container "$device_id" "$bundle_id" data > "$capture_directory/app-container-path.txt"
  container_path="$(<"$capture_directory/app-container-path.txt")"
  diagnostics_path="${container_path}/Library/Application Support/Diagnostics"
  if [[ -d "$diagnostics_path" ]]; then
    ditto "$diagnostics_path" "$capture_directory/app-diagnostics"
  fi
else
  xcrun devicectl device sysdiagnose \
    --device "$device_id" \
    --destination "$capture_directory/sysdiagnose"
  print -u2 "Export the in-app diagnostics JSON from Settings and place it in: $capture_directory"
fi

"${0:A:h}/summarize-diagnostics.sh" "$capture_directory"
print "$capture_directory"
