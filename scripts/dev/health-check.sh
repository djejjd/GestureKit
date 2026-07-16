#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
host_path="$repo_root/.build/debug/GestureKitHost"
manifest_path="${CHROME_NATIVE_HOSTS_DIR:-$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts}/com.gesturekit.host.json"
real_probe=false
failures=0

usage() {
  cat <<'EOF' >&2
usage: health-check.sh [--host-path <path>] [--manifest-path <path>] [--real]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-path)
      host_path="${2:-}"
      shift 2
      ;;
    --manifest-path)
      manifest_path="${2:-}"
      shift 2
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

pass() { print -r -- "PASS $1：$2"; }
waiting() { print -r -- "WAITING $1：$2"; }
fail() {
  print -r -- "FAIL $1：$2"
  failures=$((failures + 1))
}

extension_id=$(node "$repo_root/extensions/chrome/scripts/extension-id.mjs")

if command -v swift >/dev/null 2>&1 && command -v node >/dev/null 2>&1 && [[ -d "$repo_root/extensions/chrome/node_modules" ]]; then
  pass "开发环境" "Swift、Node 与扩展依赖可用"
else
  fail "开发环境" "请运行 ./scripts/dev/install-local.sh 准备 Swift、Node 与扩展依赖"
fi

if [[ -f "$host_path" ]]; then
  pass "构建产物" "GestureKitHost 已存在"
else
  fail "构建产物" "未找到 GestureKitHost，请运行 ./scripts/dev/install-local.sh"
fi

if [[ -f "$manifest_path" ]] && /usr/bin/python3 - "$manifest_path" "$extension_id" 2>/dev/null <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = f"chrome-extension://{sys.argv[2]}/"
assert manifest["name"] == "com.gesturekit.host"
assert manifest["allowed_origins"] == [expected]
PY
then
  pass "Native Messaging" "manifest 已安装且扩展来源匹配"
else
  fail "Native Messaging" "manifest 缺失或来源不匹配，请运行 ./scripts/dev/install-local.sh"
fi

if $real_probe; then
  print -r -- "next_step=在 Chrome 加载 extensions/chrome 后打开 chrome-extension://$extension_id/smoke.html"
fi

waiting "Chrome 到 Host" "请在 smoke 页面确认 connectNative 探针结果"
waiting "Host 到 App" "请启动 GestureKitApp；smoke 页面会显示 connected 或 app_unavailable"

if (( failures > 0 )); then
  exit 1
fi
