#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: $0 DIAGNOSTICS_DIRECTORY_OR_EXPORT_JSON"
  exit 64
fi

source_path="$1"
script_directory="${0:A:h}"

if [[ -d "$source_path" ]]; then
  output_path="${source_path}/summary.json"
else
  output_path="${source_path:h}/${source_path:t:r}-summary.json"
fi

xcrun swift "$script_directory/summarize-diagnostics.swift" "$source_path" "$output_path"
print "$output_path"
