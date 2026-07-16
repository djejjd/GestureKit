#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
host_path="$repo_root/.build/debug/GestureKitHost"
dry_run=false
default_developer_dir=/Applications/Xcode.app/Contents/Developer
developer_dir="${DEVELOPER_DIR:-}"

if [[ -z "$developer_dir" && -d "$default_developer_dir" ]]; then
  developer_dir="$default_developer_dir"
fi

usage() {
  cat <<'EOF' >&2
usage: install-local.sh [--host-path <path>] [--dry-run]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-path)
      host_path="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

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

run_swift_build() {
  if [[ -n "$developer_dir" ]]; then
    run_or_print env "DEVELOPER_DIR=$developer_dir" swift build --package-path "$repo_root"
  else
    run_or_print swift build --package-path "$repo_root"
  fi
}

extension_id=$(node "$repo_root/extensions/chrome/scripts/extension-id.mjs")

run_swift_build

if $dry_run; then
  print -r -- "cd ${(q)repo_root}/extensions/chrome && npm run build"
else
  (
    cd "$repo_root/extensions/chrome"
    npm run build
  )
fi

run_or_print "$repo_root/scripts/dev/install-native-host.sh" --host-path "$host_path"

print -r -- "extension_id=$extension_id"
print -r -- "load_unpacked_path=$repo_root/extensions/chrome"
print -r -- "next_step=在 chrome://extensions 开启开发者模式后，选择 Load unpacked 并加载上述目录"
