#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
extension_id=""
host_path="$repo_root/.build/debug/GestureKitHost"
dry_run=false

usage() {
  cat <<'EOF' >&2
usage: smoke-check.sh --extension-id <id> [--host-path <path>] [--dry-run]
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
  echo "missing required argument: --extension-id" >&2
  usage
  exit 1
fi

print_command() {
  printf '%s\n' "$1"
}

run_or_print() {
  local command="$1"
  shift

  if $dry_run; then
    print_command "$command"
  else
    "$@"
  fi
}

run_or_print "swift build" swift build
run_or_print "swift run GestureKitHost --self-test" swift run GestureKitHost --self-test

if $dry_run; then
  print_command "cd extensions/chrome && npm run build"
else
  (
    cd "$repo_root/extensions/chrome"
    npm run build
  )
fi

run_or_print "./scripts/dev/install-native-host.sh --extension-id $extension_id --host-path $host_path" \
  "$repo_root/scripts/dev/install-native-host.sh" \
  --extension-id "$extension_id" \
  --host-path "$host_path"

run_or_print "open chrome-extension://$extension_id/smoke.html" \
  open "chrome-extension://$extension_id/smoke.html"
