# 交接：PER-112 box Orca 无头运行（iMac → MBA，2026-10-20 23:50 SGT）

任务原文：本目录 `headless-BRIEF.md`（box 原件 `/workspace/ops/briefs/box-orca-headless-1020-BRIEF.md`，两份内容一致，已核对）。
接手前先读 brief 和 PR #60 正文。下面写已经查清的事实、定下的方案、下一步和没跑的测试。

## 做到哪

- 没写代码，没改任何文件。本分支除这份交接外，head 仍是 3fc7a5d（#60 原 head）。
- 已 rebase 到 origin/main cf2781f，干净无冲突（main 新进来的 #51/#59/#61/#53/#62 都没碰 orca-remote/）。
  因为不能 force push，交接前把本地分支退回了 3fc7a5d。**接手第一步：`git fetch && git rebase origin/main`，之后 push 要 `--force-with-lease`**
  （改写 #60 分支历史，派活方允许才做；不允许就改成 merge origin/main）。
- 调研做完了，结论见下，还没写进 `orca-remote/drill/FAILURE-MODES-headless.md`。
- EverOS recall_agent_experience 没调成：本会话没有 EverOS 工具，iMac 的 `~/.pi/agent/extensions/everos.ts` 也没给 ops 项目配挂载（只有 xinyue/deepvision/dv-ads/vllm-omni）。RESULT 里要记一句。
- Orca 工作区状态已设 in-progress，PR 关联 #60。
- box 上没留东西：调研用的临时目录和文件（/tmp/per112-orcad-probe-ud、/tmp/per112-main-index.js、/tmp/asar-read-per112.py）都删了，也没起任何进程或 Xvfb。
  box 上的 `/tmp/per112-c.md` 不是本会话建的，没动。
- 线上没碰：没动 pid 1187812、tmux orca-remote、/workspace/ops/orca-remote/、daemon 38968、watchdog 426789。

## 调研结论（box 实查，23:35–23:48 SGT，只读）

### 1. Orca 有真正的无头运行时 orcad，但 1.4.224 用官方参数开不了

- `orca serve` 默认会问 `<appRoot>/out/main/orcad/orcad-local-serve-selection-entry.js` 要不要走 orcad（纯 Node，不起 Electron，不要 X）。
  CLI 代码在 `resources/app.asar.unpacked/out/cli/runtime/launch.js`、`serve-orcad-launch.js`。
- appRoot = `resolve(__dirname,'../../..')` = `resources/app.asar.unpacked`；这个 entry 只打包在 app.asar 里，unpacked 里没有，
  所以每次 MODULE_NOT_FOUND 回落 Electron。没有任何环境变量或参数能改 appRoot（`ORCA_APP_EXECUTABLE` 只换可执行文件；
  `ORCA_SERVE_RUNTIME` 只认 `electron`/`orcad`，而且是 entry 里读的，entry 根本没跑到）。
- 实测：用 asar 里的 entry 跑一次（临时 user-data，已删）：
  `env -u DISPLAY ELECTRON_RUN_AS_NODE=1 $A/orca-ide $A/resources/app.asar/out/main/orcad/orcad-local-serve-selection-entry.js --user-data <tmp> --app-root $A/resources/app.asar`
  3 秒返回 `{"kind":"orcad","runtime":".../bin/node","entry":".../orcad-server.js","version":"0.1.0+15ec2904eb00"}`，在 user-data 下物化了 142M。
  模板在 `resources/orcad-template`（有）。线上 profile `~/.config/orca/profiles/local-default` 的 sshTargets 为 0，所以资格上能走 orcad。
- 不选它当默认的理由：只能靠「从 app.asar 路径调 CLI」这种非官方入口；切过去后 orcad 会对线上 profile 做迁移
  （profile-state 里有 orcadMigration* 各域，现在都是空），对 daemon 里正在跑的终端有什么影响没法在测试实例上验证。
  PR 和 RESULT 里写清楚：等 Orca 修好打包（entry 进 unpacked），orcad 才是首选；在那之前保持 #60 的 `ORCA_SERVE_RUNTIME=electron`，
  免得 Orca 一升级就悄悄换运行时。

### 2. own 模式（#60 默认）的 Xvfb 行为，从 app.asar `out/main/index.js` 读出

- 只在 serve 模式、Linux 下生效。DISPLAY 有值：只检查它是否活着，不活就打 `not verifiably live` 并 `app.exit(1)`。
- DISPLAY 没值：固定用 **:99**。`/tmp/.X11-unix/X99` 存在且 `/tmp/.X99-lock` 的 pid 活着 → **直接复用**，不管是谁起的；
  锁或 socket 失效 → 删掉再起 `Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp -terminate`（detached）。5 秒内没接管 → exit 1。
  app ready 之后就不再在退出时杀 Xvfb，靠 `-terminate`（最后一个客户端断开才退）。
- 推论：两个 own 模式的 serve（比如线上加测试实例）会共用同一个 :99，任何一个停掉都不会拆掉另一个的显示。
  要是将来有别的东西占了 :99，serve 会悄悄复用它，等于又借了别人的显示，所以失败清单要列这一条。
  打算在 serve-loop 起 serve 前做个只记日志的检查：:99 活着但不是 `-terminate` 那条命令行，就往 serve.log 写一行警告。
- box 现在的显示：:1 :2 :3 :4 :6 :8 :10 :11，全是平台的 `Xvfb :N -screen 0 1920x1200x24 -ac +extension GLX +render -noreset`，属主都是 box；没有 :99。

### 3. daemon 38968（DISPLAY=:3）

- 是 `orca-ide daemon-entry.js`，`ELECTRON_RUN_AS_NODE=1`，父进程是 tini（pid 1），不归 orca-remote 管；没有 daemon 时由 Electron serve 或 app 拉起，环境继承自拉起它的那个进程。
- 它本身不要显示：没有任何 X11 socket 连接（ss -xp 计数 0）；:3 在 10-20 22:31 被平台重建过，它没受影响。环境里的 DBUS 地址 `/tmp/dbus-ulLo2BSEtt` 已经不存在。
- 但它拉起的终端继承它的环境：bash 2117607（夜审 claude 会话）带 `DISPLAY=:3`。:3 现在是别的 Grok agent 的桌面，所以终端里要是有程序开 X 窗口，会开到别人的桌面上。
- 新方案下：daemon 下次被拉起（box 重启、Orca 升级、daemon 崩）会由 own 模式的 serve 拉起，继承 DISPLAY=:99 和私有 XDG_RUNTIME_DIR，不再借平台桌面。
  要现在就清掉 :3 只能重启 daemon，会杀掉所有在跑的终端。切换方案里写成**单独、可选、要 Zack 批**的一步，本活不做。

### 4. 线上现状要点

- box 线上 `/workspace/ops/orca-remote/orca-remote` 还是旧版（`DISPLAY=${DISPLAY:-:4}`，`SERVE_MATCH` 写死 6768），不是 #60 版。
- `orca-remote` 里的 `serve_loop` / `tunnel_loop` 已经用 `env -i` 起子进程，own 模式下 serve 拿不到调用方的 DISPLAY；
  但 tmux 会话环境、serve-loop/tunnel-loop 这两个 bash 自己、watchdog 都还带着 DISPLAY=:4。原因是 tmux 默认的 update-environment 会把客户端的 DISPLAY 复制进会话。
- watchdog 的锁已经可配：`WATCHDOG_LOCK`（默认 /tmp/orca-remote-watchdog.lock）。测试 watchdog 一定要设它，否则会被线上 watchdog 的锁挡掉。

## 定下的方案（还没实现）

默认继续用 own 模式，不另起专用 Xvfb :90。理由：Orca 自己管 :99 的起停和失效清理，#60 已经测过；
:90 要 orca-remote 自己记 pid、清理、在 serve-loop 里重启，还得改 watchdog 判断非 own 模式的逻辑，多出一整套失败方式，换来的只是号码不同。

要改的地方：
1. `orca-remote`：脚本开头 `unset DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY`，对所有子命令生效，
   tmux 客户端不带 DISPLAY，会话里就标成已删除。`start` 之后再 `tmux set-environment -t $SESSION -r DISPLAY`（`-r`，不要用 `-u`：`-u` 会回落到全局的 :4），
   同样处理另外三个变量；pane 命令前面加 `env -u DISPLAY ...` 兜底。回滚模式 `:N` 不受影响，serve_loop 会自己 export。
2. 新增只给测试用的变量，默认值保持生产：`ORCA_REMOTE_SESSION`（默认 orca-remote）、`ORCA_REMOTE_PAIRING_ADDRESS`（默认 wss://orca-bot.deepvision.sg）、
   `ORCA_REMOTE_TUNNEL`（默认 on；测试设 off，**绝不能**在测试里起 cloudflared orca-bot，那会给线上隧道多注册一个连接器）。
3. `watchdog.sh` 开头同样 unset 这四个变量；`ensure-watchdog.sh` 用 `env -u DISPLAY -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS -u WAYLAND_DISPLAY setsid nohup $W` 起。
4. serve-loop 在 own 模式下检查 :99：活着但命令行不是 Orca 的 `-terminate` 那条 → serve.log 记警告（只记日志）。
5. 文档：仓库里没有 SYSTEM_MAP（`git ls-files` 没有，box 上也只找到一个叫 PER-67-SYSTEM_MAP 的工作区目录，没有文件）。
   新建 `orca-remote/README.md`，写清楚 serve、隧道、watchdog、显示模式、回滚、测试变量、三个环境：
   box（wss://orca-bot.deepvision.sg）；MBA（`orca environment add` 名 MBA，id 483b187c-a214-4f3c-81b1-c656ffb15677，ws://100.64.0.7:6768，
   Coding助手 22:49 配好，配对码文件已删）；iMac（id 3ab3b821…，wss://orca.deepvision.sg/client-ws）。
   要是找到真正的 SYSTEM_MAP，也在那边加一样的内容。
6. `orca-remote/drill/FAILURE-MODES-headless.md`：**先写这个，再写代码**。至少列：显示没了（平台拆 :N）；
   :99 被别人占了而被悄悄复用；:99 锁失效；Xvfb 残留或多个；6768/6778 端口被占；tmux 全局环境泄漏 DISPLAY；
   watchdog 或 ensure-watchdog 从带 DISPLAY 的 shell 起；daemon 丢显示或继承了借来的显示；watchdog 误判（own 模式自愈期间）；
   配对失效（新 user-data 换了密钥）；测试实例误碰线上（端口、tmux 会话、cloudflared、stop 的 pkill 匹配）。

## 下一步：box 测试实例 E2E（都没跑）

设计（写成 `orca-remote/drill/e2e-headless-box.sh`，在 box 上跑，每段都加 timeout）：
- 隔离：`TMUX_TMPDIR=/tmp/per112-tmux`（单独的 tmux server，碰不到线上会话）。这个 server 用 `DISPLAY=:47`（不存在的号）起，
  模拟「:4 不可用、而且 tmux 全局环境带着坏 DISPLAY」。另设 `ORCA_REMOTE_SESSION=orca-remote-test`、`ORCA_REMOTE_PORT=6778`、
  `ORCA_REMOTE_HOME=/tmp/per112-home`、`ORCA_REMOTE_STATE=/tmp/per112-home/state`、`ORCA_REMOTE_TUNNEL=off`、
  `ORCA_REMOTE_PAIRING_ADDRESS=ws://127.0.0.1:6778`。`start` 会给 6778 加 iptables 只放本地的规则，所以远端用 ssh -L 转发。
  起之前看 `free -m`，同一时间只跑一个实例。
- a. serve ready（serve.log 有 orca_server_ready）；`curl 127.0.0.1:6778` 返回 200；本地 WS 握手返回 101。
  serve-loop 进程、serve 进程、tmux 会话（`show-environment` 应为 `-DISPLAY`）里都没有 :47 或 :4；Xvfb :99 只有一个。
- b. iMac 和 MBA 各开一个 `ssh -L 6778:127.0.0.1:6778 box`，`orca environment add --name box-headless-test --pairing-code "$(cat <600 临时文件>)"`。
  配对 URL 从 box 的 `/tmp/per112-home/.config/orca/remote-pairing/latest.json` 用 ssh 读进 600 临时文件，不打印。
  然后跑 `orca --environment box-headless-test repo list --json` 和 `terminal list --json`。可能的话再建一个终端，读它的 DISPLAY（应为 :99 或空）。
  用完跑 `environment rm`，删掉临时文件，关掉转发。
- c. 测试 watchdog：`WATCHDOG_LOCK/LOG/STATE/SERVE_LOG/TUNNEL_LOG/SESSION`、`ORCA_REMOTE_BIN`，`WATCHDOG_LOCAL_URL` 和 `WATCHDOG_PUBLIC_URL` 都指向
  http://127.0.0.1:6778/，`WATCHDOG_INT=15`。启动时带 `DISPLAY=:47`。
  c1：杀掉测试 tmux 会话，watchdog 应该 start 回来；c2：SIGSTOP 掉 serve-loop、SIGKILL 掉 serve，watchdog 两次 strike 后 restart，
  再给旧 bash 发 SIGCONT 让它退出。每次都检查：ready、Xvfb ≤1、state 文件、日志、新会话里没有 DISPLAY。
- d. 回退测试：origin/main 和 3fc7a5d 的脚本各跑一次，要用 shim 把 6768、会话名、/home/box、隧道换成测试值
  （参考 `drill/prefix-shim.sh` 的写法：替换没生效就失败；跑之前 grep 确认不含 6768 和生产路径，否则旧脚本的 stop 会 pkill 掉线上 serve）。
  预期：main 在 a 挂（serve 用 :47，not verifiably live）；3fc7a5d 的 a 能 ready，但「tmux 会话、serve-loop 不带 DISPLAY」这条挂。
- e. 回滚实测：起一个测试自己的 `Xvfb :48`，`echo :48 > $STATE/serve-display`，restart 后应该 `display=:48` 且 ready；
  删掉文件再 restart，回到 own/:99。最后停掉 :48。
- 收尾：停测试实例，kill 测试 daemon（匹配 `/tmp/per112-home/.config/orca/daemon`），确认没有残留 Xvfb :99 :47 :48，删除 /tmp/per112-*（box 上那个不是本会话建的 /tmp/per112-c.md 除外）。
- 超过 15 分钟的命令用 `notify-run --bot ops-system --task "PER-112 headless e2e" -- …` 包。

## 没跑的测试

上面 a–e 全都没跑，iMac Docker 里也没跑任何东西。现有 E2E 结果只有 #60 在 3fc7a5d 上的那些，换 head 以后不算数。

## 还要做

切换方案写进 PR 和 RESULT：备份到 `/workspace/ops/backups/orca-remote-<日期>-headless/`；换脚本；停旧的、起新的；验证 6768、
wss://orca-bot.deepvision.sg、iMac/MBA `--environment`；watchdog 也要按新的 ensure-watchdog 重启，否则旧 watchdog 进程还带着 :4；
写明中断时长（serve 约 60–75 秒 ready）、对 daemon 终端的影响（daemon 不重启，终端不受影响）、一条命令的回滚。
另外要更新 #60 标题和正文，评论里写全五项，RESULT 写到 box `/workspace/ops/briefs/box-orca-headless-1020-RESULT.md`，
产物放 `/workspace/ops/reports/box-orca-headless-1020/`，跑 gitleaks，用 `orca worktree set` 更新状态。
