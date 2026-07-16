#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/health-check.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

extension_id=$(node "$repo_root/extensions/chrome/scripts/extension-id.mjs")
host_path="$tmpdir/GestureKitHost"
manifest_path="$tmpdir/com.gesturekit.host.json"
touch "$host_path"

"$repo_root/scripts/dev/render-native-host-manifest.sh" \
  --extension-id "$extension_id" \
  --host-path "$host_path" >"$manifest_path"

output=$("$script" --host-path "$host_path" --manifest-path "$manifest_path")
rg -Fq "PASS 开发环境" <(print -r -- "$output")
rg -Fq "PASS 构建产物" <(print -r -- "$output")
rg -Fq "PASS Native Messaging" <(print -r -- "$output")
rg -Fq "WAITING Chrome 到 Host" <(print -r -- "$output")
rg -Fq "WAITING Host 到 App" <(print -r -- "$output")

missing_output=$("$script" --host-path "$tmpdir/missing-host" --manifest-path "$tmpdir/missing-manifest" || true)
rg -Fq "FAIL 构建产物" <(print -r -- "$missing_output")
rg -Fq "FAIL Native Messaging" <(print -r -- "$missing_output")

echo "health-check ok"
