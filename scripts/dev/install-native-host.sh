#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
renderer="$repo_root/scripts/dev/render-native-host-manifest.sh"

extension_id=""
host_path=""
manifest_dir="${CHROME_NATIVE_HOSTS_DIR:-$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts}"

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
    --manifest-dir)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --manifest-dir" >&2
        exit 1
      fi
      manifest_dir="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$manifest_dir"
target="$manifest_dir/com.gesturekit.host.json"

"$renderer" --extension-id "$extension_id" --host-path "$host_path" >"$target"

echo "installed_manifest=$target"
