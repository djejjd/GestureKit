#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/install-local.sh"
expected_id=$(node "$repo_root/extensions/chrome/scripts/extension-id.mjs")

output=$("$script" --dry-run)

rg -Fq "swift build --package-path $repo_root" <(print -r -- "$output")
rg -Fq "cd $repo_root/extensions/chrome && npm run build" <(print -r -- "$output")
rg -Fq "$repo_root/scripts/dev/install-native-host.sh --host-path $repo_root/.build/debug/GestureKitHost" <(print -r -- "$output")
rg -Fq "extension_id=$expected_id" <(print -r -- "$output")
rg -Fq "chrome://extensions" <(print -r -- "$output")

if rg -Fq -- "--extension-id" <(print -r -- "$output"); then
  echo "install-local should not require a user-supplied extension ID" >&2
  exit 1
fi

echo "install-local dry-run ok"
