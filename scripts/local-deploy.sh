#!/usr/bin/env bash
#
# 本地生产部署：体检 → npm install → 校验 → 构建 → 重启 launchd 服务 → 健康检查
#
#   scripts/local-deploy.sh                       完整部署
#   scripts/local-deploy.sh --check               只体检，不构建不重启
#   scripts/local-deploy.sh --skip-checks         跳过 tsc / eslint
#   scripts/local-deploy.sh --with-tests          额外跑 npm test（约 2 分钟）
#   scripts/local-deploy.sh --force-build         即使 .next 已对应当前提交也重新构建
#   scripts/local-deploy.sh --stop-during-build   构建期间先停服务（不抢 CPU，代价是停机）
#
# 为什么构建不放进 launchd：见 FORK.md。简单说，launchd 的 KeepAlive 会把一次崩溃放大成
# 一次重建，构建失败还会变成崩溃循环。launchd 只负责跑已构建好的产物，这个脚本负责构建。

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${PI_WEB_LAUNCHD_LABEL:-pi-web-local}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
URL="${PI_WEB_URL:-http://127.0.0.1:30141}"
BRANCH="${PI_WEB_DEPLOY_BRANCH:-local}"
DOMAIN="gui/$(id -u)"

CHECK_ONLY=0
SKIP_CHECKS=0
WITH_TESTS=0
FORCE_BUILD=0
STOP_FIRST=0

for arg in "$@"; do
  case "$arg" in
    --check)             CHECK_ONLY=1 ;;
    --skip-checks)       SKIP_CHECKS=1 ;;
    --with-tests)        WITH_TESTS=1 ;;
    --force-build)       FORCE_BUILD=1 ;;
    --stop-during-build) STOP_FIRST=1 ;;
    -h|--help)           sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                   echo "未知参数：$arg（--help 看用法）" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

start_service() {
  if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    launchctl kickstart -k "$DOMAIN/$LABEL"
  else
    [ -f "$PLIST" ] || die "找不到 $PLIST"
    launchctl bootstrap "$DOMAIN" "$PLIST"
  fi
}

cd "$REPO"

# ---- 1. 体检 ---------------------------------------------------------------
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "$BRANCH" ] || die "当前在 $branch 分支，部署分支是 $BRANCH"
git diff --quiet || die "工作区有未提交改动，先 commit 或 stash"
git diff --cached --quiet || die "有已暂存但未提交的改动"

rev="$(git rev-parse HEAD)"
built="$(cat .next/.source-rev 2>/dev/null || true)"

log "部署 $branch @ ${rev:0:7} — $(git log -1 --format=%s)"

need_build=1
if [ "$FORCE_BUILD" = 1 ]; then
  log "指定了 --force-build，会重新构建"
elif [ -z "$built" ]; then
  warn ".next 没有源码标记（上一次构建来自旧脚本），按需要构建处理"
elif [ "$built" = "$rev" ]; then
  need_build=0
  log ".next 已经是这个提交构建的，跳过构建"
else
  # 这些路径不参与 next build（文档、本 fork 自己的部署脚本、CI 配置），别为它们
  # 白烧半小时 CPU。启发式名单：改动落在 app/ components/ lib/ hooks/ public/
  # 或根配置文件上就一定会触发重建。
  code_changes="$(git diff --name-only "$built" "$rev" 2>/dev/null \
    | grep -vE '^(docs/|scripts/|\.github/)|\.md$' | head -8 || true)"
  if [ -z "$code_changes" ]; then
    need_build=0
    log "自 ${built:0:7} 起只有文档/脚本改动，跳过构建"
  else
    log ".next 由 ${built:0:7} 构建，需要重新构建："
    printf '      %s\n' $code_changes
  fi
fi

if [ "$CHECK_ONLY" = 1 ]; then
  log "（--check）体检结束，没有做任何改动"
  exit 0
fi

# ---- 2. 依赖 ---------------------------------------------------------------
log "npm install"
npm install

# ---- 3. 校验 ---------------------------------------------------------------
if [ "$SKIP_CHECKS" = 0 ]; then
  log "tsc --noEmit"
  node_modules/.bin/tsc --noEmit
  log "eslint"
  npm run lint
fi
if [ "$WITH_TESTS" = 1 ]; then
  log "npm test"
  npm test
fi

# ---- 4. 构建 ---------------------------------------------------------------
if [ "$need_build" = 0 ]; then
  log "跳过构建"
else
  if [ "$STOP_FIRST" = 1 ]; then
    log "构建前停掉服务，避免抢 CPU（这段时间服务不可用）"
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    trap 'log "构建失败，把服务拉回来"; start_service >/dev/null 2>&1 || true' EXIT
  fi

  log "npm run build（构建期间线上旧进程的静态 chunk 会 404，属正常）"
  npm run build
  printf '%s' "$rev" > .next/.source-rev

  if [ "$STOP_FIRST" = 1 ]; then
    trap - EXIT
    log "构建完成，启动服务"
    start_service
  fi
fi

# ---- 5. 重启 ---------------------------------------------------------------
if [ "$STOP_FIRST" = 1 ] && [ "$need_build" = 1 ]; then
  : # start_service 已经在构建后拉起来了
else
  log "重启 $LABEL"
  start_service
fi

# ---- 6. 健康检查 -----------------------------------------------------------
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/" || true)"
  if [ "$code" = "200" ]; then
    log "✓ 已就绪：$URL"
    exit 0
  fi
  sleep 2
done
die "60 秒内 $URL 没有返回 200，看日志：tail -50 $REPO/tmp/pi-web-local.log"
