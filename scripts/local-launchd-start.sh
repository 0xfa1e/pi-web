#!/usr/bin/env bash
#
# launchd 的启动入口（ProgramArguments 指向本脚本）。
#
# 只做两件事：源码与构建产物不一致时在日志里告警，然后启动服务。
# **这里绝不构建** —— 理由见 FORK.md：KeepAlive 会把一次崩溃放大成一次重建，
# 构建失败还会变成崩溃循环。要重新构建请跑 scripts/local-deploy.sh。
#
# 它存在的价值：你按习惯直接 launchctl kickstart -k 重启（或机器重启）时，
# 如果源码已经变了但 .next 还没重建，日志里会留下明确的一行，而不是静默跑旧版本。

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

rev="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
built="$(cat .next/.source-rev 2>/dev/null || echo '')"

if [ "$built" = "$rev" ]; then
  echo "[pi-web-local] .next 对应当前提交 ${rev:0:7}"
else
  # 文档和本 fork 自己的脚本不参与 next build，别为它们刷告警
  code_changes="$(git diff --name-only "$built" "$rev" 2>/dev/null \
    | grep -vE '^(docs/|scripts/|\.github/)|\.md$' | head -8 || true)"
  if [ -n "$built" ] && [ -z "$code_changes" ]; then
    echo "[pi-web-local] .next 对应当前提交（自 ${built:0:7} 起只有文档/脚本改动）"
  else
    echo "[pi-web-local] 警告：.next 不是当前源码构建的（HEAD=${rev:0:7}，.next=${built:-无标记}）"
    echo "[pi-web-local] 现在按旧构建产物启动。重新部署请运行：scripts/local-deploy.sh"
  fi
fi

NODE_BIN="${PI_WEB_NODE_BIN:-}"
if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then
  NODE_BIN="$(command -v node)"
fi
[ -x "$NODE_BIN" ] || { echo "[pi-web-local] 找不到 node，检查 plist 里的 PATH" >&2; exit 1; }

exec "$NODE_BIN" "$REPO/node_modules/next/dist/bin/next" start -H 127.0.0.1 -p 30141
