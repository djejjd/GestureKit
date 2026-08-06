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

  grep -Fq "env DEVELOPER_DIR=$quoted_developer_dir swift build --package-path $quoted_repo_root" <(print -r -- "$output") || return 1
  grep -Fq "env DEVELOPER_DIR=$quoted_developer_dir swift run --package-path $quoted_repo_root GestureKitHost --self-test" <(print -r -- "$output") || return 1
  grep -Fq "cd $quoted_chrome_dir && npm run build" <(print -r -- "$output") || return 1
  grep -Fq "$quoted_repo_root/scripts/dev/install-native-host.sh --host-path $quoted_host_path" <(print -r -- "$output") || return 1
  grep -Fq "$quoted_repo_root/scripts/dev/test-provider-protocol.sh" <(print -r -- "$output") || {
    echo "expected smoke check to invoke the Provider protocol contract check" >&2
    return 1
  }
  grep -Fq "open -a Google\\ Chrome chrome-extension://$extension_id/smoke.html" <(print -r -- "$output") || return 1
}

output=$("$script" --extension-id "$extension_id" --dry-run)
assert_output "$output" "$default_developer_dir" "$repo_root/.build/debug/GestureKitHost" || exit 1

output=$(DEVELOPER_DIR="$custom_developer_dir" "$script" --extension-id "$extension_id" --dry-run)
assert_output "$output" "$custom_developer_dir" "$repo_root/.build/debug/GestureKitHost" || exit 1

output=$("$script" \
  --extension-id "$extension_id" \
  --host-path "$custom_host_path" \
  --dry-run)
assert_output "$output" "$default_developer_dir" "$custom_host_path" || exit 1

echo "smoke-check dry-run ok"
