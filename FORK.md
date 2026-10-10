# 这个 Fork 带了什么补丁

本仓库是 [agegr/pi-web](https://github.com/agegr/pi-web) 的 fork，本地生产服务跑的就是本目录
checkout 的 `local` 分支。上游不收我们带的这几个补丁，所以它们不参与上游同步、由我们自己长期维护。

## 分支模型

| 分支 / 标签 | 作用 | 规则 |
| --- | --- | --- |
| `main` | 上游纯净镜像 | 只允许 fast-forward 到 `upstream/main`，**永远不要在这里提交** |
| `local` | 实际部署的分支 | `上游某个 release tag` + 我们的补丁集 |
| `local-base` | 标签，指向 `local` 当前所基于的上游提交 | 每次同步后 `git tag -f local-base <新 tag>` |

随时查看我们究竟改了什么：

```bash
git log --oneline local-base..local     # 补丁清单
git diff --stat local-base..local       # 补丁改动面
```

## 补丁清单

1. **`feat(schedules): run prompts on a cron schedule`** — 设置页新增「定时任务」：一条 prompt、
   一个工作目录、一个 5 段 cron 表达式或一次性时间。每次触发都走 `startRpcSession`，也就是
   `POST /api/agent/new` 的同一个入口，所以一次运行就是一个普通会话，会出现在会话列表里并正常
   推流。计时器挂在 `instrumentation-node.ts`，不依赖浏览器标签页。
2. **`fix(settings): make section tabs equal width below the cap`** — 设置页 7 个 tab 低于 128px
   上限时按各自内容宽度收缩导致宽度不一，改成 `flex: 1 1 0` 均分。
3. **`fix(chat): show every assistant message timestamp in 24-hour time`** — 一条 assistant 消息
   只显示最后一个时间戳、且用 `toLocaleTimeString` 输出 AM/PM；改成每条都显示、固定 24 小时制。

### 为什么上游不收（PR #1105，2026-10-09，agegr 亲答）

> Pi Web aims to stay a light web wrapper around pi, and a server-side scheduler (cron parser, tick
> loop, `schedules.json`, retention rules, a new Settings section) is a new subsystem with its own
> lifecycle that we'd have to own. Scheduling fits better outside Pi Web, for example a system cron
> job or a pi extension that runs `pi` on a timer. Closing as not planned.

这是**设计取向上的婉拒，不是代码质量问题** —— 不要反复重提。补丁 2、3 是纯 UI 修正，同理按本地
补丁维护。

### 改动面

以 `v0.11.0` 为基准，只**修改**了 10 个文件，其余都是新增：

```
app/settings.css                    components/AppShell.tsx
components/ChatWindow.tsx           components/MessageView.tsx
components/SettingsPanel.tsx        instrumentation-node.ts
lib/i18n/messages/{en,zh-CN,zh-TW}.ts
lib/settings-navigation.ts
```

新增：`app/api/schedules/`、`components/SchedulesConfig.tsx`、`lib/schedule-{cron,runner,store}.ts`
及其测试。**冲突只会落在那 10 个文件里**，其中 `lib/settings-navigation.ts` 和
`instrumentation-node.ts` 上游几乎不动。

## 同步上游新版本（runbook）

```bash
cd /Users/mac/dev-project/pi-web

# 1) 拉上游
git fetch upstream --tags

# 2) 镜像 main（只会 fast-forward，不会有冲突）
git checkout main && git merge --ff-only upstream/main && git push origin main

# 3) 把补丁搬到新版本上（换成你要跑的上游 release tag）
git checkout local
git rebase v0.12.0
#   冲突：改完 → git add <file> → git rebase --continue
#   已开启 rerere，以前解决过的冲突会自动重放
#   想放弃：git rebase --abort

# 4) 校验 + 构建 + 重启，一条命令
#    它自己会跑 tsc / eslint，--with-tests 再加 npm test；
#    健康检查 60 秒拿不到 200 会报错退出。
scripts/local-deploy.sh --with-tests

# 5) 更新基准标签并推送
git tag -f local-base v0.12.0
git push --force-with-lease origin local
```

回滚：

```bash
git reflog                        # 找回 rebase 之前的 local
git reset --hard local@{1}
git tag -f local-base <旧 tag>
scripts/local-deploy.sh --force-build
```

## 部署

仓库根的 `AGENTS.md` 开头写了一条硬规则，指向 `scripts/local-deploy.sh` —— 那是 Pi / Codex 等
agent 进这个仓库时一定会读到的位置，所以「重启一下」不会退化成只跑 `launchctl kickstart`。
（本机 `~/.pi/agent/AGENTS.md` 和 `~/.codex/AGENTS.md` 也各有一份简版，覆盖从别的目录提问的情况。）

```bash
scripts/local-deploy.sh                # 体检 → npm install → tsc/eslint → 构建 → 重启 → 健康检查
scripts/local-deploy.sh --check        # 只体检：看 .next 是否对得上当前源码，不做任何改动
scripts/local-deploy.sh --with-tests   # 额外跑 npm test
scripts/local-deploy.sh --skip-checks  # 跳过 tsc / eslint
scripts/local-deploy.sh --force-build  # 即使 .next 已对应当前提交也重新构建
scripts/local-deploy.sh --stop-during-build   # 构建期间先停服务（不抢 CPU，代价是停机）
```

`.next/.source-rev` 记录构建来源的 commit，脚本和启动入口都靠它判断产物是否过期；只有 `.md`
改动时不算过期（别为 `FORK.md` 白烧半小时 CPU）。

### 构建为什么不放进 launchd

`pi-web-local` 是 `KeepAlive: true` 的 job，语义是「进程死了就再起」。如果把构建塞进这个 job：

- 一次崩溃 → 一次 20~40 分钟的 webpack 重建，这段时间服务完全不提供
- 构建失败 → 每 `ThrottleInterval`（10 秒）重试一次构建，变成崩溃循环
- `RunAtLoad: true` → 每次开机都先等一轮构建才能用

所以职责分开：**launchd 只跑已构建好的产物**（入口是 `scripts/local-launchd-start.sh`），
**构建由 `scripts/local-deploy.sh` 负责**。启动入口只会在源码与 `.next` 不一致时往日志里写一行告警，
绝不构建 —— 这样你按习惯直接 `launchctl kickstart -k` 时不会静默跑旧版本。

## 部署注意

- `~/Library/LaunchAgents/pi-web-local.plist` 跑的是 **`next start`（生产模式）**，读的是工作目录里
  checkout 的分支 + `.next` 构建产物。**改了源码必须 `npm run build`，光重启没用。**
- `next build --webpack` 会覆盖 `.next`，正在运行的旧进程的静态 chunk 会 404，直到重启为止。
  构建和线上服务抢 CPU，几十分钟是正常量级。
- `kickstart` **不会重新读 plist**，只按 launchd 内存里的定义重启；改 plist 必须 `bootout` + `bootstrap`。
- `npm run dev`（Turbopack）和 `npm run build`（webpack）不要共用同一个 `.next`。
- 已开启 `rerere.enabled` / `rerere.autoupdate`：补丁队列反复 rebase 的冲突只解一次。
