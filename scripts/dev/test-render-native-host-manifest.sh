#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/render-native-host-manifest.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

extension_id=abcdefghijklmnopqrstuvwxzyabcdef
host_path=/tmp/GestureKitHost

"$script" --extension-id "$extension_id" --host-path "$host_path" >"$tmpdir/out.json"

/usr/bin/python3 - <<'PY' "$tmpdir/out.json" "$extension_id" "$host_path"
import json
import pathlib
import sys

out_path = pathlib.Path(sys.argv[1])
extension_id = sys.argv[2]
host_path = sys.argv[3]

data = json.loads(out_path.read_text())

assert data["name"] == "com.gesturekit.host"
assert data["description"] == "GestureKit Native Messaging Host"
assert data["path"] == host_path
assert data["type"] == "stdio"
assert data["allowed_origins"] == [f"chrome-extension://{extension_id}/"]
PY

escaped_host_path=$'/tmp/GestureKitHost "quote" \\backslash\nnewline'

"$script" --extension-id "$extension_id" --host-path "$escaped_host_path" >"$tmpdir/escaped.json"

/usr/bin/python3 - <<'PY' "$tmpdir/escaped.json" "$extension_id" "$escaped_host_path"
import json
import pathlib
import sys

out_path = pathlib.Path(sys.argv[1])
extension_id = sys.argv[2]
host_path = sys.argv[3]

data = json.loads(out_path.read_text())

assert data["path"] == host_path
assert data["allowed_origins"] == [f"chrome-extension://{extension_id}/"]
PY

if "$script" --extension-id not-valid --host-path "$host_path" >/dev/null 2>&1; then
  echo "expected invalid extension id to fail"
  exit 1
fi

if "$script" --extension-id "$extension_id" --host-path relative/path >/dev/null 2>&1; then
  echo "expected relative host path to fail"
  exit 1
fi

if "$script" --extension-id "$extension_id" >/dev/null 2>&1; then
  echo "expected missing host path to fail"
  exit 1
fi

if "$script" --host-path "$host_path" >/dev/null 2>&1; then
  echo "expected missing extension id to fail"
  exit 1
fi

echo "render-native-host-manifest ok"
