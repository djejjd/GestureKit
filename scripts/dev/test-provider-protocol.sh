#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
dry_run=false
real_probe=false
default_developer_dir=/Applications/Xcode.app/Contents/Developer
developer_dir="${DEVELOPER_DIR:-}"

if [[ -z "$developer_dir" && -d "$default_developer_dir" ]]; then
  developer_dir="$default_developer_dir"
fi

usage() {
  cat <<'EOF' >&2
usage: test-provider-protocol.sh [--dry-run] [--real]

Runs the automated Provider Protocol v2 contract layer. --real is deliberately
fail-closed until a repository-owned Chrome/App automation probe is available.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --real)
      real_probe=true
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if $real_probe; then
  cat <<'EOF' >&2
real Provider Protocol v2 smoke check is not available in this repository.
It requires a running signed GestureKit App, a Chrome profile with the unpacked
extension loaded, and an external Chrome automation session that can observe
the Provider timeline. The automated contract layer does not substitute for
that environment, so --real fails closed.
EOF
  exit 1
fi

print_argv() {
  local -a args=("$@")
  print -r -- ${(q)args}
}

run_or_print() {
  if $dry_run; then
    print_argv "$@"
  else
    "$@" >&2
  fi
}

run_swift() {
  local subcommand="$1"
  shift
  local -a args=(swift "$subcommand" --package-path "$repo_root")
  if [[ -n "$developer_dir" ]]; then
    run_or_print env "DEVELOPER_DIR=$developer_dir" "${args[@]}" "$@"
  else
    run_or_print "${args[@]}" "$@"
  fi
}

# Native Messaging v2 frame plus authenticated App runtime timeline:
# hello/authentication, context request, action accepted/result and journal.
run_swift run GestureKitHost --self-test
run_swift test --filter GestureKitAppTests.RuntimeLifecycleTests/testRuntimeHandshakeActionRequestAndAuthenticatedTelemetryShareOperationTimeline

# Chrome Provider contract: capability snapshot gates telemetry synchronization,
# telemetry ACK removes events, and reconnect reconciliation requests final state.
chrome_dir="$repo_root/extensions/chrome"
if $dry_run; then
  print -r -- "cd ${(q)chrome_dir} && npm test -- --run tests/v2Dispatcher.test.ts tests/telemetryConnection.test.ts tests/reconciliation.test.ts"
else
  (
    cd "$chrome_dir"
    npm test -- --run tests/v2Dispatcher.test.ts tests/telemetryConnection.test.ts tests/reconciliation.test.ts >&2
  )
fi

if ! $dry_run; then
  print -r -- "provider_protocol_ok"
fi
