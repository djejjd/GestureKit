#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
extension_id=""
host_path="$repo_root/.build/debug/GestureKitHost"
dry_run=false
default_developer_dir=/Applications/Xcode.app/Contents/Developer
developer_dir="${DEVELOPER_DIR:-}"

if [[ -z "$developer_dir" && -d "$default_developer_dir" ]]; then
  developer_dir="$default_developer_dir"
fi

usage() {
  cat <<'EOF' >&2
usage: smoke-check.sh [--host-path <path>] [--dry-run]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-id)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --extension-id" >&2
        usage
        exit 1
      fi
      extension_id="$2"
      shift 2
      ;;
    --host-path)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --host-path" >&2
        usage
        exit 1
      fi
      host_path="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift 1
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$extension_id" ]]; then
  extension_id=$(node "$repo_root/extensions/chrome/scripts/extension-id.mjs")
fi

print_argv() {
  local -a args=("$@")
  print -r -- ${(q)args}
}

run_or_print() {
  if $dry_run; then
    print_argv "$@"
  else
    "$@"
  fi
}

run_swift() {
  local subcommand="$1"
  shift

  if [[ -n "$developer_dir" ]]; then
    run_or_print env "DEVELOPER_DIR=$developer_dir" swift "$subcommand" --package-path "$repo_root" "$@"
  else
    run_or_print swift "$subcommand" --package-path "$repo_root" "$@"
  fi
}

run_swift build
run_swift run GestureKitHost --self-test

chrome_dir="$repo_root/extensions/chrome"
if $dry_run; then
  print -r -- "cd ${(q)chrome_dir} && npm run build"
else
  (
    cd "$chrome_dir"
    npm run build
  )
fi

run_or_print "$repo_root/scripts/dev/install-native-host.sh" \
  --host-path "$host_path"

run_or_print "$repo_root/scripts/dev/test-provider-protocol.sh"

run_or_print open "chrome-extension://$extension_id/smoke.html"
