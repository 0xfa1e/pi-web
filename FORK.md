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
4. **`feat(chat): run the selected text as a prompt in a new session`** — 选中文字后的浮动按钮多一个
   「新建会话执行」：选中内容**原样当 prompt**，`POST /api/agent/new {cwd, type:"prompt", message}`
   一次请求建好新会话并跑起来，然后本窗口像点会话列表一样切到它（`openCreatedSession()`，和
   `handleSessionForked` 同一条路），侧边栏刷新出这一行。**不新开浏览器标签页**：它本质是「新建
   会话 + 自动提交」的快捷方式，界面表现和新建一致。
   和另外两个按钮的区别：不包引用块、不 fork（不需要 `sourceEntryId`）、不需要当前对话正在跑。
   同一个动作还有第二个入口：聊天里每个代码块的头部（`复制` 左边）。入口由
   `components/selection-actions.tsx` 的 context 提供，Provider 只挂在 AppShell 的 `<ChatWindow>` 外面，
   所以文件查看器里同样的 `CodeBlock` 不会长出这两个按钮。
5. **`feat(chat): start a scheduled task from the selected text`** — 选中文字后的浮动按钮再多一个
   「新建定时任务」：打开 设置 › 定时任务 并直接展开新建表单，提示词就是选中的文字，工作目录取当前
   会话的项目。数据流：`ChatWindow` → `AppShell.handleNewScheduledTask`（设 `schedulePrompt` 并切到
   `schedules` 章节）→ `SettingsPanel` → `SchedulesConfig.initialPrompt`（填进草稿后立刻消费掉）。
   它建立在补丁 1 上，上游既已婉拒定时任务，这个也不提。代码块头部的入口同上（同一个 context）。

### 为什么上游不收（PR #1105，2026-10-09，agegr 亲答）

> Pi Web aims to stay a light web wrapper around pi, and a server-side scheduler (cron parser, tick
> loop, `schedules.json`, retention rules, a new Settings section) is a new subsystem with its own
> lifecycle that we'd have to own. Scheduling fits better outside Pi Web, for example a system cron
> job or a pi extension that runs `pi` on a timer. Closing as not planned.

这是**设计取向上的婉拒，不是代码质量问题** —— 不要反复重提。补丁 2、3 是纯 UI 修正，同理按本地
补丁维护。补丁 4 是上游没有的能力（它的「在新对话询问」只能 fork 出一条引用链），自用即可。

### 改动面

以 `v0.12.2` 为基准，只**修改**了 12 个文件，其余都是新增：

```
AGENTS.md                           app/settings.css
components/AppShell.tsx             components/ChatWindow.tsx
components/MermaidBlock.tsx         components/MessageView.tsx
components/SettingsPanel.tsx
instrumentation-node.ts             lib/settings-navigation.ts
lib/i18n/messages/{en,zh-CN,zh-TW}.ts
```

新增：`app/api/schedules/`、`components/SchedulesConfig.tsx`、`lib/schedule-{cron,runner,store}.ts`、
`components/selection-actions.tsx`、`components/ChatWindow.selection-actions.test.mjs`，外加本 fork
自己的 `scripts/local-deploy.sh` / `local-launchd-start.sh`。**冲突只会落在那 12 个文件里**，其中 `lib/settings-navigation.ts`、
`instrumentation-node.ts`、`AGENTS.md`、`components/selection-actions.tsx` 上游几乎不动。

### 同步上游时已知的坑（每次 rebase 都看一遍）

1. **`components/AppShell.tsx` → `handleOpenSession` 会被上游删掉**（实测于 v0.12.1）。上游
   `311a901 feat(agents): view sub-agent work in a right-panel tab` 把 `onOpenSession` 换成了
   `onOpenSubagent(sessionId, label)`，顺手删掉了「按 id 打开会话」的 `handleOpenSession`。
   我们的 `SchedulesConfig` 仍然要「打开这次运行产生的会话」，所以 rebase 后必须在 AppShell 里
   把这个 helper 重新加回来，并接到 SettingsPanel 的 `onOpenSession` 上。**这个断链不会产生冲突**
   —— 补丁能干净应用，然后 `tsc` 报 `Cannot find name 'handleOpenSession'`。所以 rebase 之后
   **必须跑一次 `tsc`**，不能只看「没有 conflict」。
2. **`components/ChatWindow.tsx` → 时间戳补丁必然冲突，而且是两块**（v0.12.2 实测）。原因：
   上游把渲染 key 从 `entryIds[idx] ?? idx` 换成了 `messageKeys[idx]`（新增 `lib/message-keys.ts`），
   又给 `renderMessage` 的 options 加了 `withNotices`，两处都跟我们的补丁重叠。解决方式：
   - 第一块：`const messageKey = messageKeys[idx];` **取上游的**（别退回 `entryIds`），`showTimestamp`
     取我们的一行 `let showTimestamp = msg.role === "assistant";`（不再引用 `isStreaming`）。
   - 第二块（process-details 分组）：保留上游的 `withNotices,`，继续删掉我们删掉的 `showTimestamp: false`。
   校验：`git grep -n showTimestamp components/ChatWindow.tsx` 只剩「options 声明 / 我们的赋值 /
   options 覆盖 / 传给 MessageView」四处，且文件里不再有冲突标记。已开 rerere，第二次会自动重放——
   但**只用 rerere 自动结果不够，必须再跑 `tsc`**（2026-10 这次 rerere 记录的旧解只覆盖了第一块）。
3. **`instrumentation-node.ts` → 两边都要保留**。上游往这里加 `readHttpIdleTimeoutMs()` 和
   预热 pi SDK 的 `import("@earendil-works/pi-coding-agent")`，我们加 `startScheduleRunner()` /
   `stopScheduleRunner()`。合并后必须是：`configureHttpDispatcher(readHttpIdleTimeoutMs())`、紧跟
   `startScheduleRunner()`、`shutdownStreams` 里先 `stopScheduleRunner()` 再关流、末尾保留 SDK 预热。
4. **`app/settings.css` / i18n / `SettingsPanel.tsx` 一般不冲突**，因为两边改的是同文件的不同行区
   （上游改 `GeneralSettings`、skill/mcp 样式；我们改 dialog 宽度、tab 布局、schedules 文案）。
   真冲突时按「两边都留」处理：schedules 那个 tab 是我们加的，不能为了省事丢掉。

## 同步上游新版本（runbook）

```bash
cd /Users/mac/dev-project/pi-web

# 1) 拉上游
git fetch upstream --tags

# 2) 镜像 main（只会 fast-forward，不会有冲突）
#    main 跟的是 upstream/main，通常已经跑到最新 release tag 前面几个未发版提交：
#    镜像的是「上游现状」，而 local 只给自己发过版的 tag 打补丁。
git checkout main && git merge --ff-only upstream/main && git push origin main

# 3) 把补丁搬到新版本上（换成你要跑的上游 release tag）
#    动手前先确保 local 工作区是干净的：有未提交的 fork 改动就先 commit，不然会跟着 rebase 跑
git status --short
git checkout local
git rebase v0.12.2
#   冲突：改完 → git add <file> → git rebase --continue
#   已开启 rerere，以前解决过的冲突会自动重放
#   想放弃：git rebase --abort
#   解决完先按上面「已知的坑」自查一遍，尤其要跑 tsc：没有 conflict 不等于能编译
node_modules/.bin/tsc --noEmit

# 4) 校验 + 构建 + 重启，一条命令
#    它自己会跑 tsc / eslint，--with-tests 再加 npm test；
#    健康检查 60 秒拿不到 200 会报错退出。
scripts/local-deploy.sh --with-tests

# 5) 更新基准标签并推送
git tag -f local-base v0.12.2
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

`.next/.source-rev` 记录构建来源的 commit，脚本和启动入口都靠它判断产物是否过期。`docs/`、
`scripts/`、`.github/` 和 `*.md` 不参与 `next build`，改动到这些路径不算过期（别为 `FORK.md`
白烧半小时 CPU）。

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
