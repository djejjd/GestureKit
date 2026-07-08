#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/smoke-check.sh"
extension_id=abcdefghijklmnopqrstuvwxzyabcdef
default_developer_dir=/Applications/Xcode.app/Contents/Developer
custom_developer_dir='/Applications/Xcode Beta.app/Contents/Developer'
custom_host_path='/tmp/GestureKit Host'

assert_output() {
  local output="$1"
  local expected_developer_dir="$2"
  local expected_host_path="$3"
  local quoted_developer_dir="${(q)expected_developer_dir}"
  local quoted_repo_root="${(q)repo_root}"
  local quoted_chrome_dir="${(q)repo_root}/extensions/chrome"
  local quoted_host_path="${(q)expected_host_path}"

  rg -Fq "env DEVELOPER_DIR=$quoted_developer_dir swift --package-path $quoted_repo_root build" <(print -r -- "$output")
  rg -Fq "env DEVELOPER_DIR=$quoted_developer_dir swift --package-path $quoted_repo_root run GestureKitHost --self-test" <(print -r -- "$output")
  rg -Fq "cd $quoted_chrome_dir && npm run build" <(print -r -- "$output")
  rg -Fq "$quoted_repo_root/scripts/dev/install-native-host.sh --extension-id $extension_id --host-path $quoted_host_path" <(print -r -- "$output")
  rg -Fq "open chrome-extension://$extension_id/smoke.html" <(print -r -- "$output")
}

output=$("$script" --extension-id "$extension_id" --dry-run)
assert_output "$output" "$default_developer_dir" "$repo_root/.build/debug/GestureKitHost"

output=$(DEVELOPER_DIR="$custom_developer_dir" "$script" --extension-id "$extension_id" --dry-run)
assert_output "$output" "$custom_developer_dir" "$repo_root/.build/debug/GestureKitHost"

output=$("$script" \
  --extension-id "$extension_id" \
  --host-path "$custom_host_path" \
  --dry-run)
assert_output "$output" "$default_developer_dir" "$custom_host_path"

echo "smoke-check dry-run ok"
