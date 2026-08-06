#!/bin/zsh
set -euo pipefail

# test-link-reliability.sh — GestureKit E2E link-reliability 入口脚本
#
# 用法:
#   zsh scripts/dev/test-link-reliability.sh             # 真实 Chrome 验收（人工关口）
#   zsh scripts/dev/test-link-reliability.sh --dry-run   # 干跑：打印命令，不启动 GUI/Chrome
#
# 退出码同 runner：0 = 四场景全过，1 = 场景失败，2 = 环境预检失败

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
runner="$repo_root/scripts/e2e/run-link-reliability.mjs"
# 允许通过环境变量覆盖默认路径（文档 remedy 真实生效）
chrome_path="${CHROME_PATH:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      echo "usage: test-link-reliability.sh [--dry-run]" >&2
      exit 2
      ;;
  esac
done

# --- 预检 ---

if ! $dry_run; then
  if [[ ! -x "$chrome_path" ]]; then
    echo "preflight_failed: Chrome 未安装在 $chrome_path" >&2
    echo "next_step: 安装 Google Chrome 或设置 CHROME_PATH 指向 Chrome 可执行文件" >&2
    exit 2
  fi

  if [[ ! -d "$developer_dir" ]]; then
    echo "preflight_failed: Developer 目录不存在: $developer_dir" >&2
    echo "next_step: 安装 Xcode，或设置 DEVELOPER_DIR 指向正确的 Developer 目录" >&2
    exit 2
  fi

  if ! node --version >/dev/null 2>&1; then
    echo "preflight_failed: Node.js 未找到" >&2
    echo "next_step: 安装 Node.js 23+" >&2
    exit 2
  fi
fi

# --- Node 单元测试 ---

echo "=== Node unit tests ===" >&2
node --test "$repo_root/scripts/e2e/test-link-reliability.mjs"
echo "" >&2

# --- E2E runner ---

if $dry_run; then
  echo "=== Dry-run (no GUI, no Chrome, no user profile writes) ==="
  CHROME_PATH="$chrome_path" DEVELOPER_DIR="$developer_dir" node "$runner" --dry-run
else
  echo "=== E2E Link Reliability (real Chrome) ===" >&2
  echo "注意：此项测试会启动 Chrome 并写入临时 profile。" >&2
  echo "" >&2
  CHROME_PATH="$chrome_path" DEVELOPER_DIR="$developer_dir" node "$runner"
fi
