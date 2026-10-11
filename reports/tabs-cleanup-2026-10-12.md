# iMac Orca 终端 tab 清理报告（2026-10-12）

执行者：Claude Code（ops 工作区，tab「ops · 标签页清理」），按 Coding助手转来、Zack 批准的任务执行。
执行时间：2026-10-12 03:34–03:45（新加坡时间）。Orca 版本 1.4.223。

## 结果

- 关闭了 13 个终端（11 个 tab，另有 2 个不挂在任何 tab 上的终端），全部是 completed 工作区里的普通 shell。关闭后复查：13 个都已不在 `orca terminal list` 里，对应的 shell 进程都已退出。
- 「普通 shell 且进程已退出」这一类本次为 0 个。清理前的 59 个终端都有存活的 shell 进程。
- 终端总数 59 → 46，tab 总数 41 → 31（清理后的 31 个里包含本任务自己的 tab，清理前的快照里它还没有挂到 tab 上）。
- agent 会话 14 个（含本任务自己的终端），全部保留，只在下面列出。
- 有 1 个符合「completed 工作区」条件的终端没有关：「dv运维 · FDV-25 本地预览和截图」里的 tab「fdv-16 preview」，它正在跑 `next start -p 3100`（已运行约 2 天 14 小时，监听 127.0.0.1:3100）。关掉 tab 会停掉这个预览服务，我无法确认是否还有人在用，所以留给人决定。确认不用后可运行：
  `orca terminal close --terminal term_f41b6c77-2b27-41dc-b9dd-e406e101e697 --tab`
- 没有使用 `terminal stop`，没有使用 `terminal close --worktree --all`，没有改工作区状态，没有动 ops 工作区里的任何终端。

## 判断方法

- 终端和 tab：`orca terminal list --json --include-visual-layouts`。
- 工作区状态：`orca worktree list --json` 的 `workspaceStatus`。
- 进程是否存活：`orca diagnostics memory --json` 里 `sessions[].sessionId` 等于终端的 `ptyId`，取其 pid 后用 `ps` 看进程树。
- agent 会话：终端的 `agentIdentity` 非空（本次为 claude 或 pi），并核对了进程树。
- 未保存改动：关闭前读了每个候选终端的屏幕。12 个停在空提示符，前台只有 zsh；1 个（tab「deepvision-ops-2」）停在 `git log` 的分页器 `(END)`，没有可丢失的内容。没有候选终端在跑编辑器，也没有敲到一半的命令。
- 这些工作区里有未提交的 git 改动（提示符带 ✗ 的），关终端不影响工作目录里的文件。

## 已关闭（13 个）

| 工作区 | tab 标题 | 终端 | 关闭前的状态 |
|---|---|---|---|
| vllm · PER-2 H3/C1 原开发目录（已拆分，停用） | ..-lab/worktree | term_42bb2522 | 空提示符 |
| dv运维 · FDV-16 主站改版方案 | fdv-16 ops shell | term_b9412a11 | 空提示符 |
| dv运维 · FDV-25 本地预览和截图 | ..dv-16-preview | term_fbdcded9 | 空提示符 |
| dv运维 · FDV-25 本地预览和截图 | preview-3101-dummy-stripe | term_33411c7e | 空提示符 |
| dv运维 · FDV-25 本地预览和截图 | deepvision-ops-2 | term_b9f9eacb | `git log` 分页器 |
| vllm · PER-1 C1 fork 分支 rebased（已取消） | ..dules-rebased | term_908e9a94 | 空提示符 |
| vllm · PER-1 C1 fork 分支 rebased（已取消） | grok-bot · c1 trim | term_ffd2fce4 | 空提示符 |
| vllm · PER-2 C2 fork 分支 rebased（已取消） | ..dules-rebased | term_c9f5a0fd | 空提示符 |
| dv广告 · FDV-35 Ryze 调研 | ..s/fdv-35-ryze | term_e441da8f | 空提示符 |
| 心月 · PER-38 摇摇荡荡 | ..8-swing-swing | term_c1ae825f | 空提示符 |
| 心月 · PER-38 摇摇荡荡 | （无 tab） | term_a0ab2ea5 | 空提示符 |
| 心月 · PER-39 大嘴洞洞 | ..9-gobble-hole | term_4cf83fd2 | 空提示符 |
| 心月 · PER-39 大嘴洞洞 | （无 tab） | term_9024d27b | 空提示符 |

有 tab 的用 `orca terminal close --terminal <handle> --tab` 关，无 tab 的两个不加 `--tab`。

## 保留（46 个）

### agent 会话（14 个，含本任务自己的终端，一律不关）

| 工作区 | 工作区状态 | tab 标题 | 终端 | agent |
|---|---|---|---|---|
| vllm · PER-2 H3/C1 原开发目录（已拆分，停用） | completed | worker-task_cbc12e25608d | term_a9b758da | pi |
| dv运维 · FDV-16 主站改版方案 | completed | Panel title guard test FDV-16 | term_8578b833 | claude |
| vllm · PER-1 C1 fork 分支 rebased（已取消） | completed | Pi · C1 拆栈 | term_89dd6df6 | pi |
| dv运维 · Orca 工作区整理 | completed | Orca 工作区 FDV-16/25 元数据更新 | term_56806268 | claude |
| folder:479149ea…（不在 worktree list 中） | 查不到 | Claude 新出了一个叫做 Claude Startups 的项目 | term_e39612d6 | pi |
| folder:479149ea…（不在 worktree list 中） | 查不到 | Cloudflare 账单刺客 | term_e60b2461 | claude |
| vllm · PER-22 C2-1 性能优化（direct register） | in-progress | PER-22 direct-register (Pi) | term_80498337 | pi |
| 心月 · PER-37 涨水爬楼 | in-progress | PER-37 涨水爬楼 agent | term_8e82a2b9 | claude |
| deepvision-ads · 主目录 | in-progress | FDV-35 Ryze调研 | term_691ce33d | claude |
| main（ops） | in-progress | Nightly regression run 1 | term_69d9ebe6 | claude |
| main（ops） | in-progress | ops · 工作树对齐核对 | term_421eabf5 | claude |
| main（ops） | in-progress | ops · 标签页清理（本任务） | term_ca0a142c | claude |
| vllm · PER-12 C2-1 mypy 修复 | in-progress | （无 tab） | term_f873bb06 | pi |
| adrunner · 主目录 | in-progress | （无 tab） | term_5b351bc5 | pi |

前 4 个在 completed 工作区里，是否结束由人决定。

### completed 工作区里保留的普通终端（1 个）

| 工作区 | tab 标题 | 终端 | 原因 |
|---|---|---|---|
| dv运维 · FDV-25 本地预览和截图 | fdv-16 preview | term_f41b6c77 | 正在跑 `next start -p 3100` |

### 其余普通 shell（31 个，进程存活且工作区不是 completed，不在清理范围）

| 工作区 | 工作区状态 | 数量 | tab 标题 |
|---|---|---|---|
| main（ops） | in-progress | 10 | ..orkspaces/ops、worktree-audit、worktree-audit-2、worktree-audit-3、worktree-audit-4、read-projects-md、prune-stale、nightly-check、update-orca-projects-md、verify-md |
| xinyue-site · 主目录 | in-progress | 3 | probe、orca-setup、心月 ops shell（在跑 `games-watch.sh`） |
| 心月 · PER-37 涨水爬楼 | in-progress | 1 | ..lood-climb-v2 |
| dv广告 · FDV-36 Ryze 复刻总装 | todo | 1 | FDV-36 Ryze 复刻总装 |
| ~/orca/workspaces/xinyue-site/per-37-flood-climb（不在 worktree list 中） | 查不到 | 2 | ..7-flood-climb、PER-37 flood agent |
| ~/claude/firstmate/projects/xinyue-site（不在 worktree list 中） | 查不到 | 1 | xinyue-ops |
| site · 主目录 | in-progress | 5 | 均无 tab |
| adrunner · 主目录 | in-progress | 1 | 无 tab |
| vllm · PER-7 / PER-8 / PER-9 / PER-10 / PER-11 / PER-12 C2 sigma / PER-13 | in-progress | 各 1，共 7 | 均无 tab |

说明：

- 有 15 个保留的终端不挂在任何 tab 上（上表「无 tab」的 13 个普通 shell 和 2 个 pi 会话），shell 已空转 2–4 天，在 Orca 界面里看不到 tab，但仍占进程。它们所在的工作区是 in-progress，不符合本次两类条件，所以没关。要不要清，需要另外决定。
- 有 3 组终端所在的目录不在 `orca worktree list` 里，查不到工作区状态，按「拿不准不动」保留。

## 每个工作区的 tab 数

「tab / 终端」中，终端数包含不挂在 tab 上的终端。

| 工作区 | 路径 | 状态 | 清理前 tab / 终端 | 清理后 tab / 终端 |
|---|---|---|---|---|
| main（ops） | ~/orca/workspaces/ops | in-progress | 12 / 13 | 13 / 13 |
| dv运维 · FDV-25 本地预览和截图 | ~/orca/workspaces/site/fdv-16-preview | completed | 4 / 4 | 1 / 1 |
| xinyue-site · 主目录 | ~/pi/remote/xinyue-site | in-progress | 3 / 3 | 3 / 3 |
| vllm · PER-1 C1 fork 分支 rebased（已取消） | ~/orca/workspaces/repository/feat-diffusion-step-attention-schedules-rebased | completed | 3 / 3 | 1 / 1 |
| vllm · PER-2 H3/C1 原开发目录（已拆分，停用） | ~/pi/remote/h3-c1-lab/worktree | completed | 2 / 2 | 1 / 1 |
| dv运维 · FDV-16 主站改版方案 | ~/orca/workspaces/site/fdv-16-redesign-v2 | completed | 2 / 2 | 1 / 1 |
| 心月 · PER-37 涨水爬楼 | ~/orca/workspaces/xinyue-site/per-37-flood-climb-v2 | in-progress | 2 / 2 | 2 / 2 |
| （不在 worktree list 中） | folder:479149ea-1146-4baa-b03e-b31fcdbd181e | 查不到 | 2 / 2 | 2 / 2 |
| （不在 worktree list 中） | ~/orca/workspaces/xinyue-site/per-37-flood-climb | 查不到 | 2 / 2 | 2 / 2 |
| （不在 worktree list 中） | ~/claude/firstmate/projects/xinyue-site | 查不到 | 1 / 1 | 1 / 1 |
| vllm · PER-22 C2-1 性能优化（direct register） | ~/orca/workspaces/repository/per-22-direct-register | in-progress | 1 / 1 | 1 / 1 |
| dv运维 · Orca 工作区整理 | ~/orca/workspaces/site/dv-ops-orca-tidy | completed | 1 / 1 | 1 / 1 |
| deepvision-ads · 主目录 | ~/orca/workspaces/deepvision-ads | in-progress | 1 / 1 | 1 / 1 |
| dv广告 · FDV-36 Ryze 复刻总装 | ~/orca/workspaces/deepvision-ads/fdv-36-build | todo | 1 / 1 | 1 / 1 |
| vllm · PER-2 C2 fork 分支 rebased（已取消） | ~/orca/workspaces/repository/feat-diffusion-sigma-attention-schedules-rebased | completed | 1 / 1 | 0 / 0 |
| dv广告 · FDV-35 Ryze 调研 | ~/orca/workspaces/deepvision-ads/fdv-35-ryze | completed | 1 / 1 | 0 / 0 |
| 心月 · PER-38 摇摇荡荡 | ~/orca/workspaces/xinyue-site/per-38-swing-swing | completed | 1 / 2 | 0 / 0 |
| 心月 · PER-39 大嘴洞洞 | ~/orca/workspaces/xinyue-site/per-39-gobble-hole | completed | 1 / 2 | 0 / 0 |
| site · 主目录 | ~/claude/site | in-progress | 0 / 5 | 0 / 5 |
| adrunner · 主目录 | ~/claude/adrunner | in-progress | 0 / 2 | 0 / 2 |
| vllm · PER-12 C2-1 mypy 修复 | ~/orca/workspaces/repository/c2-1-r3-mypy | in-progress | 0 / 1 | 0 / 1 |
| vllm · PER-7 C1 客户端错误透传 | ~/orca/workspaces/repository/c1-1-client-errors | in-progress | 0 / 1 | 0 / 1 |
| vllm · PER-8 C1 schedule 配置与校验 | ~/orca/workspaces/repository/c1-2-schedule-config | in-progress | 0 / 1 | 0 / 1 |
| vllm · PER-9 C1 注意力候选按步选择 | ~/orca/workspaces/repository/c1-3-candidate-selection | in-progress | 0 / 1 | 0 / 1 |
| vllm · PER-10 C1 模型发布去噪进度 | ~/orca/workspaces/repository/c1-4-model-publishers | in-progress | 0 / 1 | 0 / 1 |
| vllm · PER-11 C1 请求执行与 Wan2.2 接入 | ~/orca/workspaces/repository/c1-5-request-execution | in-progress | 0 / 1 | 0 / 1 |
| vllm · PER-12 C2 sigma 窗口策略 | ~/orca/workspaces/repository/c2-1-sigma-policy | in-progress | 0 / 1 | 0 / 1 |
| vllm · PER-13 C2-2 sigma CUDA graph（不推上游，跟进见 PER-18） | ~/orca/workspaces/repository/c2-2-sigma-graphs | in-progress | 0 / 1 | 0 / 1 |

超过 5 个 tab 的工作区：只有 ops（13 个 tab）。其中 10 个是之前审计留下的空闲 shell，3 个是 agent 会话。ops 是 in-progress，且任务要求不动 ops 里的终端，本次没有关。

## Orca 是否自带「空闲终端自动关闭」

没有找到，记为不存在。查过的地方：

- `orca --help` 和 `orca agent-context --json`（242 个命令）：没有按空闲时间自动关闭终端的命令或选项。`terminal close` 只能手动关单个终端、单个 tab 或整个工作区的终端。
- 设置文件 `~/Library/Application Support/orca/profiles/local-default/orca-data.json` 的 215 个设置项：没有自动关闭终端的开关。
- 应用包 `app.asar` 里搜 `autoClose`、`closeIdle`、`idleTerminal`、`closeOnExit` 等标识符：只有编辑器括号自动补全相关的 `autoClose*`。

相近但不同的功能：`experimentalAgentHibernation`（当前为 false）和 `agentHibernationIdleMs`（1800000，即 30 分钟），是让空闲 agent 会话休眠的实验功能，不关闭终端或 tab。另有工作区 Sleep，需要手动触发。

## 每日自动化的改动

改的是已有的「内存与 CPU 日常清理」（id `b0e92e5c-c746-4147-9ec5-48453f24ed35`，每天 04:37 新加坡时间，ops 工作区），没有新建自动化。改后用 `orca automations show` 核对过，尚未实际运行过一次；下次运行是 2026-10-12 04:37。

- 提示词新增第 6 步「Orca 终端 tab 清理」：规则与本次相同（只关两类；agent 会话、带未保存改动的、敲到一半的、在跑服务或测试的、运行任务的终端自身、查不到工作区状态的都不关；不用 `terminal stop` 和 `--worktree --all`）。
- 报告里增加 tab 清理结果、每个工作区的 tab 数，并单独列出超过 5 个 tab 的工作区。报告位置不变：`~/.orca-state/mem-cpu-cleanup/reports/<新加坡日期>.md`。
- 原第 5 步的「不关闭 Orca 终端」改为「进程清理这一步不关闭 Orca 终端；终端只按第 6 步的规则关」。
- 新增预检 `$HOME/.orca-state/bin/orca-due.sh mem-cpu-cleanup`，提示词最后一步改为成功后运行 `~/.orca-state/bin/orca-ok.sh mem-cpu-cleanup <agent>`。这是 `~/.orca-state/bin` 里已有的备用机制所需的两个标记。

### 备用 agent（codex）：未完成，需要决定

Orca 的自动化只有一个 `--provider`，没有备用 agent 字段（查了 `automations create/edit --help`、自动化的存储字段和应用包）。本机已有的做法在 `~/.orca-state/bin/orca-fallback.sh` 里：另建一个每小时运行、provider 为 codex 的备用自动化，用 `orca-fallback.sh <name>` 做预检，主任务到点后 25 分钟内没有成功标记才启动。这要求新建一个自动化，和「不新建自动化」的要求冲突，所以我没有建。

现状：主任务一侧的标记已接好，codex 已安装并有受管账号，但主任务失败时不会有 codex 接手。两个选项：

1. 允许新建备用自动化（推荐）。命令如下，提示词用主任务的同一份：
   `orca automations create --name "内存与 CPU 日常清理（codex 备用）" --provider codex --trigger hourly --workspace path:/Users/jiawenwang/orca/workspaces/ops --workspace-mode existing --precheck '$HOME/.orca-state/bin/orca-fallback.sh mem-cpu-cleanup' --prompt "<同主任务提示词>"`
2. 不建备用。主任务失败时当天不清理，第二天 04:37 再跑。

补充：目前自动化列表里只有 6 个主任务，没有任何 codex 备用自动化，`~/.orca-state/runs` 目录也还不存在。「CF usage watch」和「SEO weekly check」的预检同样只写了 due 标记，没有对应的备用任务。
