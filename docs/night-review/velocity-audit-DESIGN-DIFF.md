# PER-86 夜审加「交付瓶颈」复盘：设计 diff

2026-10-20，ops 系统派活（PER-86），iMac Orca 工作区 ops-PER-86-night-velocity 执行。

来源：Zack 10-20 19:14 SGT 定（dr eggbot 转述），把 Kun Chen 每日复盘（https://x.com/kunchenguid/status/2112245086725841047 ，「audit my development work in the last 24h, identify bottlenecks that slowed down my velocity, and propose improvements」）里有用的部分并进现有四个夜审。规则只能更准，不能更长：已有的不加，能并进已有步骤就并。

本文件和同目录两份文件都是设计稿，本 PR 不改任何线上 automation。

## 对照的文本

- 线上提示词：box `/workspace/ops/reports/night-review-velocity-1020/live-snapshot/<id8>.prompt.md`（2026-10-20 19:16 只读快照），下表写成 `live-snapshot/<id8>.prompt.md:行`。四份：心月 75b324a4（23:30）、官网 43c55a22（00:10）、广告 9b5c20e7（00:10）、vllm c392a743（00:30）。
- 仓库副本 `everos-ingest/night-review-{xinyue,deepvision-ads,vllm-omni}.prompt.md` 和线上**不一致**：三份都缺 10-18 起的 MBA 清单那一行，第 3/4 步末尾都缺「每写一条 EverOS，立刻按目标 app/project/user 读回……」一句。所以行号比线上少 1（例：线上 `75b324a4:33` = 仓库 `night-review-xinyue.prompt.md:32`）。官网没有仓库副本。本 PR 不改这三份（避免和 PER-79 冲突），只对线上快照出 patch。
- 迁移设计：box `/workspace/ops/briefs/box-heavy-jobs-migration-1020-BRIEF.md`（PER-79，只读参考）。

## 对照表

| 要点 | 现有覆盖 | 改动 |
|---|---|---|
| 1. 只定目标，不规定做法；加一问「过去 24 小时什么拖慢了交付」 | 没有这一问。现有「只找」一句只问返工、不该合、验证太糙：`live-snapshot/75b324a4.prompt.md:33`、`43c55a22.prompt.md:12`、`9b5c20e7.prompt.md:8`、`c392a743.prompt.md:8`（仓库 `night-review-xinyue.prompt.md:32`、`night-review-deepvision-ads.prompt.md:7`、`night-review-vllm-omni.prompt.md:7`） | 并进这一步：「只找」一句加一个类别「拖慢交付」（替换原句），紧跟着插入一段（`velocity-step.prompt.md`）。段落只写要回答什么、要什么证据，不写命令 |
| 2. 例子：E2E 太慢；多个 agent 在同一批文件上反复冲突 | 没有 | 写进段落的括号里，一句。#45 和 PER-67 在 `scripts/agent-probe` 冲突是 ops 仓库的例子，夜审审的是各业务仓库，段落里只写通用说法，不写 ops 的例子 |
| 3. 用已有数据算三段等待（等叫醒、等验收、等 Zack 拍板） | 部分：`43c55a22.prompt.md:10`、`9b5c20e7.prompt.md:6`、`c392a743.prompt.md:6`「超过 12h 无输出的会话」只列长时间不动的会话，不算等待。心月没有这一步 | 段落里给三段的起止定义和「读不到写无数据」规则，不加新采集、不加新存储。数据源和读不到时的做法见下一节 |
| 4. 每天先查昨天那条改进有没有用；每天只提一条改进并记结果 | 没有。`75b324a4.prompt.md:33,35` 的 seen_dates / 3 日升级记的是同一规则出现几天，不是改进有没有效果 | 段落第一句：读前一天本项目摘要里行首「改进：」那一行，今天写「昨日改进：… → 有用/没用/看不出 + 证据」。最后一句：只提一条，写成行首「改进：」的一行。存储就是现有摘要文件，不新增 |
| 5. 每个瓶颈挂证据（commit、diff、PR 号、时间戳）；先观察后判断 | 部分：`9b5c20e7.prompt.md:3`、`c392a743.prompt.md:3`「返工、验证太糙要引会话里的原话位置」；`9b5c20e7.prompt.md:8` lesson「含证据」；`43c55a22.prompt.md:14`、`9b5c20e7.prompt.md:10`、`c392a743.prompt.md:10` 摘要「附证据」。没有「先观察后判断」 | 段落里一句「每个瓶颈先写观察（commit、PR 号、diff 或时间戳），再写判断」。现有「附证据」句不动 |
| 6. 只看增量；跨多个 commit 找反复出现的同类问题 | 已覆盖大部分：`43c55a22.prompt.md:2`、`9b5c20e7.prompt.md:2`、`c392a743.prompt.md:2` 的 [SINCE, UNTIL) 左闭右开窗口就是上次夜审之后的增量；`43c55a22.prompt.md:12` 等「先 search 同类 lesson，已有就记 seen_dates」和 `75b324a4.prompt.md:33,35` 的 seen_dates / 3 日升级管跨天重复。心月用「当天 SGT 00:00–现在」（`75b324a4.prompt.md:23`），23:30 跑，每天 23:30–24:00 没人审 | 已覆盖，不加。段落写「只看本次审查窗口」，直接沿用各夜审已有的窗口。同一窗口内跨多个 commit 的同类问题，段落里一句「合成一条」。心月漏 23:30–24:00 的问题不在本 PR 改，交给 PER-79 模板（它把心月挪到 23:40，仍是「审当天」） |

不采纳：自动合并（与「agent 不自合」冲突）；新增定时任务；夜审自己改东西。段落最后一句「只提建议，不动手改」。

## 每处改动和理由

四份提示词每份三处，全部在 `live-prompts.patch`：

1. 「只找」一句加类别（替换原句）
   - 心月 `75b324a4.prompt.md:33`：「只找：修完又返工的、不该合的、验证太糙的；」→「只找：修完又返工的、不该合的、验证太糙的、拖慢交付的；」
   - 其他三份第 4 步：「4. 只找：返工、不该合、验证太糙；」→「4. 只找：返工、不该合、验证太糙、拖慢交付；」
   - 理由：瓶颈和返工、验证太糙是同一次对照里找的同一类东西，用的是同一批 commit/PR/Linear，并进去不多读数据，也不多一个步骤号。
2. 紧跟该步插入 `velocity-step.prompt.md` 那一段（缩进 3 格，和现有「MBA（2026-10-18 起）」续行同格式）。
   - 理由：要点 1、3、4、5 都是新内容，现有句子里没有可以替换的。写成一段、只写目标和证据要求。三段等待给了起止定义，这是为了让四个夜审算出来的数能互相比，不是规定做法。
3. 摘要一步的清单加一项（替换原句）
   - 心月第 7 步：「、Zack 决定、失败项。全部写完后」→「、Zack 决定、第 3 步的昨日改进/瓶颈/三段等待/改进、失败项。全部写完后」
   - 其他三份第 6 步：「、Zack 决定、失败项，附证据。」→「、Zack 决定、第 4 步的昨日改进/瓶颈/三段等待/改进、失败项，附证据。」
   - 理由：第二天要读前一天摘要的「改进：」行，摘要里必须有。心月摘要的 00:30 兜底只看「状态：」「当前步骤：」两行（`75b324a4.prompt.md:3`），加内容不影响它。

没写新脚本：干跑里三段等待用几条只读命令加一次性的 python 就算出来了，写成脚本省不了明显的 token，反而要和 PER-79 的 macOS 可移植改动一起维护。

## 三段等待的数据源（2026-10-20 核实）

| 等待 | 定义（段落原文） | 数据源 | 干跑结果（官网 10-19） |
|---|---|---|---|
| 等叫醒 | agent 停下发出叫醒 → 同一会话下一轮开始 | 各机器 `~/.local/state/orca-wake/wake.log`：`event=send, ok=true` 行 → 同 `session_id` 下一条 `event=state` 且 note 含 `turn N started` 的行。会话范围用当晚会话清单的 session_id | 能算 |
| 等验收 | 交出待验收结果 → 验收方给出结论或合并；合并前才转 ready 的不算 | 验收写在 Linear 评论里（如「运维验收（2026-10-19 12:2x SGT）」）；GitHub PR 时间线（ReadyForReviewEvent、PullRequestReview、mergedAt）只作参考 | 无数据：Linear 里「交验收」和「验收结论」没有统一标记，配不成对；GitHub 上 19 个 PR 都是合并前几分钟才转 ready（中位 0.2 分钟），review 0 条，不代表等待 |
| 等 Zack 拍板 | Linear「[待Zack-…]」→ 对应「[Zack答-…]」 | 夜审第 1 步已经在读的 Linear 评论，按标签配对 | 能算，但标签写法不统一（`logo/email/banner` 合并答复、`home1..3` 范围写法）会让配对漏掉 |

其他候选数据源：iMac `~/.orca-state/stuck-check/`（卡住检查扫描日志，只有「新嫌疑 N 个」这类汇总）、`heartbeat-watch/`（心跳）、`notify-run/notify-run.log`（每个 agent 结束一行，有 status 和时间，没有「下一轮开始」）、`agent-stops/`（主动停掉的 agent，10-19 只有 3 个 PER-66 演练文件）。这些都不比 wake.log 更直接，段落里不点名，夜审可以自己用。Orca worktree 状态变化：`orca worktree ps --json` 只给当前状态，没有历史，算不了等待。

读不到别的机器时怎么办：

- 夜审现在在 box 跑。box 自己的 wake.log 只有 box 上的会话；10-19 官网 11 个会话里 box 只有 1 个。只读 box 得到 3 次等待（中位 0.6 分钟），加上 iMac、MBA 得到 18 次（中位 3.0 分钟，最长 126.4 分钟）。所以必须读别的机器。
- 2026-10-20 实测：box → `ssh imac`、box → `ssh mba`、MBA → `ssh imac`、MBA → `ssh box` 都能用 BatchMode 只读 wake.log。迁到 MBA 后同样可行。
- ssh 失败时，段落要求写「无数据：缺什么」（例「无数据：iMac 不可达，iMac 上 6 个会话的叫醒没算」），不估算、不报警、不算失败项、不新建同步任务。

## 费用 / 额度

计费方式：

- 四个夜审 `orca automations list` 显示 `agentId: claude`，跑在 box 上。box 的 `claude auth status`：`authMethod: claude.ai`、`subscriptionType: max`；box 登录 shell 里没有 `ANTHROPIC_API_KEY`。所以现在用的是 Max 订阅额度，不按 API 计费，**不多花钱**，只多占额度。
- 迁到 MBA 后：MBA 登录 shell 里 `claude auth status` 是 `authMethod: none`，Orca 起 agent 时用什么账号还不知道。PER-79 上线前要确认；如果改成 API 计费，**上线前要 Zack 批费用卡**。

每晚每个夜审多出的 token（**估算**，依据下面的干跑实测）：

| 项 | 估算 | 依据 |
|---|---|---|
| 提示词变长 | 输入 +约 400 token / 轮（首轮后走缓存） | 段落 1106 字节、440 字（估约 355 token）；两处替换各加十几个字 |
| 新读的数据（过滤后进上下文的部分） | 输入 +4k–6k token | 干跑过滤后的输出：叫醒等待约 2 KB、PR 时间线摘要约 2.5 KB、Zack 标签配对 0.8 KB、CI 和改动最多的文件 1.2 KB、合并冲突核对约 5 KB、前一天摘要 1 行 |
| 多出的工具调用 | 约 8–12 次，每次带上已有上下文（约 6–10 万 token，大部分是缓存读） | 干跑在 box 上是 1 次采集（9 段只读读取）+ 1 次合并冲突和失败 job 核对，本地分析另 6 次；夜审 agent 自己做时按每段一次算 |
| 缓存读 | +0.5M–1.2M token | 上一行相乘 |
| 输出 | +4k–6k token | 只读命令和过滤脚本约 2–3k，摘要新增一节约 1–1.5k，推理 1–2k |

四个夜审合计每晚：新输入 +16k–24k，输出 +16k–24k，缓存读 +2M–5M。每月（30 晚）：新输入 0.5M–0.7M，输出 0.5M–0.7M，缓存读 60M–150M。官网 10-19 是四个项目里数据最多的一天（11 个会话、107 个 commit、19 个合并），广告、vllm 当天各只有 1 个会话，所以四个都按官网算是偏高的估计。

风险：如果夜审 agent 不过滤、直接把原始数据读进上下文，干跑读到的原始数据是 PR 时间线 228 KB、Linear 四个 issue 190 KB、三台机器 wake.log（10-18 到 10-20 凌晨）434 KB，约 23 万 token，一晚就会把上下文顶满。段落按要求不写做法；PER-79 合并模板时如果发现这个问题，再决定要不要加一句「先过滤再读」。

## 干跑（E2E）结果摘要

只读干跑：D=2026-10-19，项目 deepvision-site（官网），按段落原文做。完整报告在 box `/workspace/ops/reports/night-review-velocity-1020/dryrun-deepvision-site-2026-10-19.md`。要点：

- 昨日改进：10-18 摘要没有「改进：」行，写「昨日改进：无」（第一天，正常）。
- 等叫醒：18 次，中位 3.0 分钟，最长 126.4 分钟（iMac 会话 cba55101「FDV-70 整版合 staging」08:07 发出 idle → 10:14 下一轮）。
- 等验收：无数据（Linear 里交验收和验收结论没有统一标记；GitHub 上 0 条 review，ready → 合并中位 0.2 分钟，不代表等待）。
- 等 Zack 拍板：成对 2 次（logo4 843 分钟、deslop3 34 分钟）；9 个 10-19 提出的标签截至 10-20 读取时没有同名答复。
- 瓶颈 1（多个 agent 改同一文件）：窗口内 107 个 commit 里有 47 个改 `app/ryze.css`；03:53–04:48 连续合并 14 个 PR 期间，有 3 个 merge commit（020d99f 03:57、cfdc55b 04:16、75e145d 04:25）在 ryze.css / messages 上手工解冲突。
- 瓶颈 2（E2E 慢）：Test 工作流 63 次，成功一次中位 9.7 分钟；17 次被后一次 push 取消；#102 分支 15:47–17:44 连续 6 次失败（`npm test`）。
- 改进（只一条）：同一时段只派一个 agent 改 `app/ryze.css`（或先按页面拆 css）；第二天看窗口内解 ryze.css 冲突的 merge commit 数（10-19 是 3 个）。

## 上线

- 本 PR 只加三份文档，不改任何线上 automation，不改 `everos-ingest/*.prompt.md`，不改脚本。
- 上线要另走 Zack 卡（动生产 automation）。
- 要和 PER-79 迁移的提示词模板合并：PER-79 把四个夜审从 box 复制到 MBA 并逐项替换路径和 `date -d`，`live-prompts.patch` 的三处改动应该在那份模板里一起做，不在 box 旧提示词和 MBA 新提示词两边各改一次。PER-79 还没开 PR，先合哪个由 ops 系统定；后合的一方按本文件的对照表重放三处改动。
- 回滚：关掉本 PR 或 revert 这个 commit。上线后要回滚，就把四个 automation 的提示词恢复到 live-snapshot 那一版。
