## 锁屏与钥匙串对夜审的影响

初稿由 MBA 上的 agent 写（没提交，21:28 SGT 它自己因登录失败停下）；2026-10-20 21:4x SGT 在 iMac 上逐条核对行号并补了证据。
依据：ops 系统的只读诊断 box `/workspace/ops/reports/mba-claude-login-1020/DIAG.md`、本分支 f3fb2bc 的代码（行号都是 f3fb2bc 的）、
仓库外已装脚本（写全路径，iMac 上核；MBA 上的经 `ssh mba` 只读 `grep`/`sed` 核）、MBA 的 orca-wake 和 notify-run 日志（只读）。
没有在 MBA 上起过 claude，没碰钥匙串和登录，没读凭据文件。

**2026-10-20 22:59 SGT 更正（PER-110）**：原稿说「MBA 屏幕锁着时 login 钥匙串是锁的，新起的 claude 读不到登录」，锁屏实测否定了这一点。
下面改成以「login 钥匙串被锁上」为前提；锁屏本身不会造成这种情况。21:28 的真实证据保留。

### 锁屏实测（ops 系统，2026-10-20 22:21–22:51 SGT，本节作者没参与）
报告：box `/workspace/ops/reports/mba-claude-login-1020/LOCKSCREEN-locked-half.md`、`/workspace/ops/reports/mba-claude-login-1020/LOCKSCREEN-unlocked-half.md`。
- 两次真锁屏（22:26:53–22:30:37、22:37:53–22:42:15，共 7 轮 `IOConsoleLocked = true`）：Orca GUI 终端（Aqua 会话）里
  `claude auth status` 都是 loggedIn true，`security show-keychain-info` 退出码 0，`claude -p` 都 exit 0。
  **锁屏本身不会让 GUI 会话里的 claude 丢登录，新起的也一样。**
- 经 ssh（Background 会话）不管锁没锁都读不到：钥匙串 exit 36（User interaction is not allowed）、loggedIn false、`claude -p` exit 1（几秒，
  报「Not logged in · Please run /login」）。所以 ssh 看到的 loggedIn false 不能说明真没登录；DIAG 里经 ssh 得到的 loggedIn false 也属于这种。
- 22:31 那次 `pmset displaysleepnow` 没生效（没锁屏也没息屏），不算。息屏、睡眠会不会让钥匙串上锁，还没测。

### 仍然成立的事实（DIAG.md 和 LOCKSCREEN-locked-half.md 结论 3）
- 21:28 前后 MBA 的 login 钥匙串本身被锁上了（securityd 约每 20 s 一次 `unlocking for makeUnlocked()`，SecurityAgent 起来又超时退出，
  `No securityagent`）。它是怎么被锁上的（睡眠、超时、21:08 那次登录尝试，还是别的），实测没查清。
- 已经在跑的 claude 用启动时读进内存的 OAuth token，没有 `ANTHROPIC_*` / `CLAUDE_CODE_OAUTH_TOKEN` 环境变量；
  token 需要刷新时才会去读钥匙串，钥匙串锁着时就失败。
- 夜审在 automation 里每次都是新起的 claude：`register.sh` 给每条 create 都加 `--fresh-session`，claude 由 Orca 直接起
  （`--provider claude`），外面没有 notify-run（`automations/migration-1020/register.sh:25-28`）。

### 真实证据：这一节的 MBA agent 本身就是这样停下的
- 会话 0d27b331（ops-system 派的 PER-79 收尾，notify-run `--tty` 起的 claude），派出时间 17:55:58 SGT（orca-wake 会话状态里的
  `dispatch_ts`），21:28 SGT 停下（当时 login 钥匙串锁着，见上），跑了 12766 s。
- 报错原文「Not logged in · Please run /login」，StopFailure，error 为 `authentication_failed`（来自 ops 系统的派活记录；
  orca-wake 日志里不记报错正文）。按时间看是上下文压缩后再调 API 时出的错。
- MBA `~/.local/state/orca-wake/wake.log`：21:25:12 turn 11 开始；21:28:47 发出 `status=error`、key `claude:0d27b331-…:error:11`、
  bot ops-system、http 200；21:29:44 的 `Notification/idle_prompt` 以 `error_already_reported` 跳过。
  也就是说 claude 进程没有退出，停在输入框；叫醒里 `exit_code` 是 null（orca-wake 的叫醒一律不带退出码，`wake/bin/orca-wake:615`）。
- MBA 的 notify-run 日志（`~/.orca-state/notify-run/notify-run.log`）当天 PER-79 最后一行是 21:14:28 的内层命令，
  之后没有这个 agent 的结束记录。外层 notify-run 后来怎样，没核。
- 说明：**login 钥匙串锁着时，已经在跑的 claude 也会挂**。token 刷新或压缩后重连时读不到钥匙串，这一轮就失败。
  夜审单次要跑几十分钟到一个多小时，开跑时钥匙串开着、跑到中途被锁上，也可能这样停下。
- MBA 上已装的 `~/.local/bin/orca-wake` 和本分支 `wake/bin/orca-wake` sha256 一致（前 16 位 ab75137c97142a40）；
  MBA `~/.claude/settings.json` 的 UserPromptSubmit、Stop、StopFailure、PermissionRequest、Notification 都挂了 orca-wake（只读了 hooks 的键名）。

### 四个夜审在 MBA 的 login 钥匙串被锁上时会怎样

排班取自 `defs.json`：心月 23:40（替 75b324a4）、官网 00:30（替 43c55a22）、广告 00:55（替 9b5c20e7）、vllm 01:20（替 c392a743）。
四个夜审走的是同一套预检和收尾（`scripts/night-review-gate.sh`），所以下面的过程对四个都一样，差别只在时间。
前提是当晚 MBA 的 login 钥匙串被锁上（像 21:28 那样）。只是锁屏或合盖、钥匙串开着时，按实测 claude 能正常登录，不会走到下面这条路。

1. **预检照常放行。** 主预检只看 box 是否已完成、当晚是否已开始、时间窗、用电池、合盖且会睡（`scripts/night-review-gate.sh:79-96`），
   不看钥匙串、claude 登录。合盖但 `SleepDisabled 1` 时放行（`:90-95`）。放行时拿 heavy-lock（`:99-104`）、
   起 caffeinate（`:106`），记 `state=started`（`:107`）。caffeinate 只防睡眠，不解锁屏幕或钥匙串。
2. **claude 起来以后怎样：新起的没在 GUI 里测过，在跑的已见过。** 钥匙串读不到时，`claude -p` 几秒内 exit 1，报
   「Not logged in · Please run /login」（ssh 下实测，见上）。GUI 会话里钥匙串真被锁上时没测过；Orca automation 带着提示词起的
   交互式 claude 是停在登录界面还是退出、Orca 把这次运行记成什么，也没有证据。见下面的「还没测的」。
   在跑的 claude 中途失败时，上面的真实证据显示它停在输入框、不退出。
3. **EverOS 会不会写半截：** 写 EverOS 的步骤在提示词里，由 claude 执行；claude 没起来就一行都不会写。claude 起来了、中途 token
   刷新失败（上面的真实证据就是这种）会留下半截：会话写入是一次脚本调用，可能已写完一部分；之后的接替运行
   用 `--skip-existing`（`everos-ingest/nightly_addflush.py:491-497`）跳过已写的会话。官网的 dv_addflush.py 没有这个开关
   （MBA `~/orca/projects/deepvision-site/scripts/everos/dv_addflush.py` 里没有 `--skip`，经 ssh 只读核），靠接替版提示词要求先读回
   （`automations/migration-1020/prompts/imac/night-review-deepvision-site.prompt.md:8`），没有演练过。另：iMac 接替版提示词写的
   `~/claude/site/scripts/everos/dv_addflush.py` 在 iMac 上现在不存在（`ls` 没有），原因没核。
4. **会不会白跑：** 收尾 `finish` 没人调用，状态一直停在 `started`，box 上没有完成摘要。MBA 的 heavy-lock 一直被这一晚占着，
   到 40 分钟才算作废、被下一个 acquire 收走（`scripts/heavy-lock.sh:14`、`:29-35`）。锁被占时主预检记 `missed reason=lock_busy`
   （`scripts/night-review-gate.sh:99-103`）；补跑只在 MBA 时间到 +25 分钟之间动作（`:84`，`defs.json` 里补跑是 23、0、1 点的 :05 :15 …），
   当晚已经 `started` 的 3 小时内补跑直接跳过（`:81-83`），所以补跑救不回一个起来就失败的夜审。
5. **谁来补，什么时候：** iMac 看守在 MBA 时间 +30 读到 `started` 不到 60 分钟，判「在跑」，不接手（`:74`、`:111`）；
   iMac 备用每 10 分钟查一次（MBA 时间 +30 到 +240，`:115`），`started` 超过 60 分钟判 `stalled`（`:74`），写接替标记并在 iMac 上跑（`:117-125`）；
   看守读到 lock_busy 时当场写接替标记（`:112`）。按上面的代码推一晚（没有实测）：
   - 心月 23:40：拿到锁，记 started，claude 起不来。iMac 约 00:40–00:50 按 stalled 接手。
   - 官网 00:30：心月的锁 00:20 已作废，被收走，记 started，起不来。iMac 约 01:30–01:40 接手。
   - 广告 00:55：官网的锁才 25 分钟，lock_busy；01:05 补跑仍 busy；01:15 补跑时锁已 45 分钟，收走，记 started，起不来。
     iMac 约 02:20 按 stalled 接手（01:25 看守时它是「在跑」）。
   - vllm 01:20：广告 01:15 的锁要到 01:55 才作废，01:20–01:45 的主跑和补跑都是 lock_busy；01:50 iMac 看守按 lock_busy 交给 iMac，
     iMac 备用 01:50 起接手。
   前提是 iMac 上的 claude 那时能登录：DIAG 在 21:1x 看到 iMac 是 loggedIn true，iMac 的 login 钥匙串夜里会不会被锁上，没有验证。
6. iMac 也没完成时，box 看守在 MBA 时间 +150 给 ops-system 发一条 stuck（`:131-138`；`defs.json` 里 box 看守是 02:10 / 03:00 / 03:25 / 03:50）。

结论：按现在的代码，MBA 的 login 钥匙串被锁上的晚上，四个夜审在 MBA 上大概率都跑不成；开跑时钥匙串开着、跑到中途被锁上的也可能停下。
只是锁屏或合盖、钥匙串开着时，claude 照常能用（实测）。
夜审本身靠 iMac 接替补上（stalled 晚约 60–80 分钟，lock_busy 在 +30 分钟），
**没有任何一条机制会对夜审报「MBA 的 claude 没登录」**，只会表现成 stalled 或 lock_busy。
orca-wake 的 StopFailure 钩子能报登录失败，但只对 notify-run `--tty` 起的 agent 生效，夜审不是这样起的。
PER-110 的钥匙串看守（`scripts/keychain-watch.sh`，在叠加在本 PR 上的 PER-110 draft PR 里）就是用来抓这种情况的：
每 10 分钟在 MBA 的 Aqua 会话里查一次 login 钥匙串和 `claude auth status`，出问题时叫醒 ops-system。

### 现有机制能不能抓到「claude 登录失败」

| 机制 | 能不能抓到 | 多久 | 证据 |
|---|---|---|---|
| MBA 主预检 / 补跑（本 PR） | 抓不到。不查钥匙串、claude 登录 | — | `scripts/night-review-gate.sh:79-107` |
| register.sh（本 PR） | 抓不到。只生成 orca 命令，默认不调用 | — | `automations/migration-1020/register.sh:3`、`:9`、`:25-28` |
| heavy-lock（本 PR） | 抓不到。还会让失败的那一晚占锁 40 分钟，挡住后一个夜审 | 40 分钟后锁作废 | `scripts/heavy-lock.sh:14`、`:29-35` |
| caffeinate（本 PR） | 抓不到。只防睡眠 | — | `scripts/night-review-gate.sh:106`、`:152` |
| iMac 看守 → iMac 备用（本 PR） | 间接：当成 stalled 或 lock_busy 接替，不知道原因是登录 | stalled：started 后 60–70 分钟；lock_busy：MBA 时间 +30 分钟 | `scripts/night-review-gate.sh:74`、`:111-112`、`:115-125` |
| box 看守（本 PR） | 间接：iMac 也没完成时报 `imac_missed` | MBA 时间 +150 分钟 | `scripts/night-review-gate.sh:131-138` |
| orca-wake StopFailure 钩子，notify-run `--tty` 起的 agent | **能抓到**。这一轮 API 调用失败就发 `status=error`，note 带 StopFailure 的 error；不带退出码。本次 MBA 收尾 agent 21:28:47 报出 | 失败当场（本次 21:28 出错、21:28:47 发出） | `wake/bin/orca-wake:741-748`、`:615`；钩子注册 `wake/bin/orca-wake-hooks:32`；MBA `~/.local/state/orca-wake/wake.log` 21:28:47 一行 |
| orca-wake StopFailure 钩子，夜审（Orca automation 起的 claude） | 按 ops 仓库代码抓不到。MBA 用户级 settings 挂了钩子，夜审的 claude 也会触发；但 orca-wake 只处理带 `ORCA_DISPATCH_BOT` 的会话，没有就直接返回、不发 | — | `wake/bin/orca-wake:24-27`、`:198-200`、`:702-703`；`ORCA_DISPATCH_BOT` 只由 notify-run `--tty` 导出 `wake/bin/notify-run:168`；`register.sh:25-28` 不设它。Orca 起 automation 时会不会自己设这个变量：没核（Orca 代码不在本仓库） |
| notify-run 收尾 | 抓不到。夜审里的 notify-run 只包最后一步 finish（提示词第 8 行），claude 没起来或中途停下就不会执行。它按退出码报 done / failed（`/Users/jiawenwang/.local/bin/notify-run:181-187`，iMac 核，MBA 同路径同行号经 ssh 只读核；本分支 `wake/bin/notify-run:145-151`），但轮不到它 | — | `automations/migration-1020/prompts/mba/night-review-*.prompt.md:8` |
| notify-run 的「起没起来」检查 | 抓不到。只在 notify-run `--tty` 包住 claude 时才查，Orca automation 起的 claude 外面没有 notify-run；而且 claude 已经退出的话它直接不报（`kill -0` 失败就退出） | 包住时 5 分钟 | `/Users/jiawenwang/.local/bin/notify-run:165-175`（`kill -0` 在 `:167`），启用条件 `:228-230`；`register.sh:25-28` |
| stuck-check | 抓不到。ops 主目录里 Orca 自动任务起的 agent 直接跳过（`scripts/stuck-check.sh:828-829`，按命令行认出的也跳过 `:934-936`）；Orca 没有这个终端的 agent 记录时也跳过（`:822-823`）。`.due/.ok` 对账只看 cf-usage、seo-weekly、mem-cpu-cleanup（`:139`、`:1328-1334`） | — | 同左 |
| heartbeat-watch | 抓不到。它只读 stuck-check 预检打的 `@@HB` 心跳（`scripts/heartbeat-watch.sh:3-5`、`:117`），部署是 box 和 iMac 互相盯（`:12`），不看夜审 | — | 同左 |

### 还没测的
- 锁屏下空跑 `claude -p`：**已测**（ops 系统，22:21–22:51 SGT，见上面「锁屏实测」两份报告），GUI 会话里锁屏不影响登录。
- 息屏、睡眠后 login 钥匙串会不会被锁上：没测（22:31 的 `pmset displaysleepnow` 没生效）。
- GUI 会话里钥匙串真被锁上时，新起的 claude 和 Orca automation 起的 claude 怎么表现、Orca 运行记录怎么记、会不会带 `ORCA_DISPATCH_BOT`：没测。
- Orca automation 的预检是不是在 Aqua 会话里跑：没测（要注册一个 automation，得另外批）。
- iMac 夜里锁屏时的同一问题：没测。

### 前置条件
不依赖钥匙串解锁的登录方案另开 Linear 子 issue（ops 系统开），是夜审上 MBA 的前置条件，要 Zack 本人卡片。
在这之前，`README.md`「上线顺序」第 4–7 步（MBA 夜审）不该启用。
