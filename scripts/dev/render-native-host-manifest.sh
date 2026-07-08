#!/bin/zsh
set -euo pipefail

extension_id=""
host_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-id)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --extension-id" >&2
        exit 1
      fi
      extension_id="$2"
      shift 2
      ;;
    --host-path)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --host-path" >&2
        exit 1
      fi
      host_path="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$extension_id" =~ ^[a-z]{32}$ ]]; then
  echo "extension id must be 32 lowercase letters" >&2
  exit 1
fi

if [[ "$host_path" != /* ]]; then
  echo "host path must be absolute" >&2
  exit 1
fi

# Keep JSON escaping centralized so installer reuse stays exact.
json_string() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

path_json=$(json_string "$host_path")
origin_json=$(json_string "chrome-extension://$extension_id/")

cat <<EOF
{
  "name": "com.gesturekit.host",
  "description": "GestureKit Native Messaging Host",
  "path": $path_json,
  "type": "stdio",
  "allowed_origins": [
    $origin_json
  ]
}
EOF
