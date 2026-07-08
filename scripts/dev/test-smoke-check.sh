#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/smoke-check.sh"
extension_id=abcdefghijklmnopqrstuvwxzyabcdef
developer_dir=/Applications/Xcode.app/Contents/Developer

output=$("$script" --extension-id "$extension_id" --dry-run)

rg -q "^DEVELOPER_DIR=$developer_dir swift build$" <(print -r -- "$output")
rg -q "^DEVELOPER_DIR=$developer_dir swift run GestureKitHost --self-test$" <(print -r -- "$output")
rg -q '^cd extensions/chrome && npm run build$' <(print -r -- "$output")
rg -q "^\\./scripts/dev/install-native-host.sh --extension-id $extension_id --host-path " <(print -r -- "$output")
rg -q "^open chrome-extension://$extension_id/smoke.html$" <(print -r -- "$output")

echo "smoke-check dry-run ok"
