#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/install-native-host.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

extension_id=abcdefghijklmnopqrstuvwxzyabcdef
host_path=/tmp/GestureKitHost

output=$("$script" \
  --extension-id "$extension_id" \
  --host-path "$host_path" \
  --manifest-dir "$tmpdir")

target="$tmpdir/com.gesturekit.host.json"
[[ -f "$target" ]]
[[ "$output" == *"installed_manifest=$target"* ]]

/usr/bin/python3 - <<'PY' "$target" "$extension_id" "$host_path"
import json
import pathlib
import sys

target = pathlib.Path(sys.argv[1])
extension_id = sys.argv[2]
host_path = sys.argv[3]

data = json.loads(target.read_text())

assert data["name"] == "com.gesturekit.host"
assert data["description"] == "GestureKit Native Messaging Host"
assert data["path"] == host_path
assert data["type"] == "stdio"
assert data["allowed_origins"] == [f"chrome-extension://{extension_id}/"]
PY

custom_manifest_dir="$tmpdir/custom manifests"
mkdir -p "$custom_manifest_dir"

output=$("$script" \
  --extension-id "$extension_id" \
  --host-path "$host_path" \
  --manifest-dir "$custom_manifest_dir")

custom_target="$custom_manifest_dir/com.gesturekit.host.json"
[[ -f "$custom_target" ]]
[[ "$output" == *"installed_manifest=$custom_target"* ]]

default_home="$tmpdir/default-home"
mkdir -p "$default_home"

output=$(HOME="$default_home" "$script" \
  --extension-id "$extension_id" \
  --host-path "$host_path")

default_target="$default_home/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json"
[[ -f "$default_target" ]]
[[ "$output" == *"installed_manifest=$default_target"* ]]

failed_manifest_dir="$tmpdir/failed"
mkdir -p "$failed_manifest_dir"

if "$script" \
  --extension-id invalid-extension-id \
  --host-path "$host_path" \
  --manifest-dir "$failed_manifest_dir" >/dev/null 2>&1; then
  echo "expected invalid renderer input to fail"
  exit 1
fi

failed_target="$failed_manifest_dir/com.gesturekit.host.json"
[[ ! -e "$failed_target" ]]

echo "install-native-host ok"
