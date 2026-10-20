# 交接给 ops 系统（--bot ops-system）：叫醒系统、卡住检查告警路由、EverOS 补写

起草：2026-10-20 17:00 SGT，Coding助手 派（brief `/workspace/ops/briefs/per67-wake-fixes-FINISH-1020.md`），PER-67 工作区 `ops-PER-67-wake-fixes`（box）。
草稿，没写 Linear。以下 PR 状态是 10-20 16:50 SGT 用 gh 核对的结果。

## 最新状态（Coding助手 2026-10-20 19:50 SGT 更新，以这一节为准，下面 17:00 的正文作背景）
- #37–#43 已合 main（1883faf，Zack 17:56 卡片批，[Zack答-PER67-10]），box、MBA、iMac 都已装好（`/workspace/ops/reports/per67-real-e2e/install/RESULT.md`）。第 4 节第 1 条已结。
- 真 E2E：缺口 3、4、7、8、9 正在 PER-80 补跑（iMac 工作区 ops-PER-80-gaps，ETA 22:30）。缺口 9 必须用不在自动批准名单里的命令，预期状态 needs_input。补跑通过、我验收后，第 1 节才算全部交完。
- EverOS 10-19 漏写的会话已补写完（新写 23 条，`/workspace/ops/reports/everos-backfill-1019/RESULT.md`），漏的 31279f05、b714e004 已按 PER67-9 补写。心月 skill 导入 10-21 00:20 跑，ops 系统 早上查。
- 在跑或待批：PER-78 #45 正在 rebase（ETA 20:30），之后重新验收、重新弹卡；PER-84 #47 合 main 卡在 Zack；PER-87 README 断链在 Backlog；PER-79 重活迁出 box 的 draft（10-21 18:00）；PER-81、PER-82 在下一批。
- 一并交给 ops 系统的旧活：ops·23 生产版本哨兵、ops·24 未推送扫描、PER-66 第二批、Linear sync 修复、CE+pstack 调研结论、卡住检查「in-progress 没终端」的修复、清 /private/tmp 下的 gi-wt 临时 worktree、MBA 采集器 A+E 对齐（第 3 节）、orca-projects.md 重写（见文末附）。
- v5 routine（Coding助手 的「Orca 叫醒测试（v5）」）：Zack 19:29 定删、19:33 定等 PER-80 补跑完再删（[Zack答-PER67-11]）。删之前请确认 bot=test 和新 bot 放行测试不依赖它，有依赖就先换地方接。

## 一句话现状（17:00，已过时）
- 叫醒系统 F1–F8 和「agent 没起来」都修好了，开成 6 个叠加 draft PR（#37→#38→#39→#41→#42→#43）。TLC 和演练都过了，但**一个都没合、一个都没装**。三台机器上在用的还是修之前的代码，F1–F8 这些漏洞线上都还在。
- 6 组都没做真 E2E（真叫醒、真 webhook），缺口和各要谁批见 RESULT 末尾。
- EverOS 10-18 夜审漏写的 13 个会话 10-19 已补写完、读回过（term_b7d460c5 那次）。剩 MBA 采集器版本一项没对齐。

## 1. 叫醒系统（PER-67 F1–F8 + 第 6 组）

代码在 ops 仓库 `wake/`（orca-wake、notify-run、orca-agent-launch、hooks、Pi 扩展）和 `scripts/stuck-check.sh`、`scripts/heartbeat-watch.sh`、`scripts/agent-probe`。
模型在 `wake/tla/`（Wake.tla、Heartbeat 部分、第 6 组新加的 Launch.tla），跑法 `wake/tla/check.sh`，也可以用 skill `wake-tla-verify`。

| PR | 分支（base） | head | 修什么 |
|---|---|---|---|
| #36 | ops-PER-67-wake-tla（main） | 73da56a | TLA+ 模型，发现 F1–F8，不修。保持 draft，修复 PR 都从它长出来 |
| #37 | ops-PER-67-fix-f7f8（main） | ed890446e9a6a39d333741bf0c5e13e10cc9d915 | F7+F8：卡住检查超时 / 出错时心跳照样新鲜，不告警 |
| #38 | ops-PER-67-fix-f3（fix-f7f8） | 82c431c2c04c64ef60ca6b1b9d326a842181b0de | F3：completed 干净工作区最后一次停下没送达，照报 |
| #39 | ops-PER-67-fix-f1（fix-f3） | e20ce245938d74d3a4872fabf243e11ef4a0984d | F1：补叫醒交给 orca-wake 后，送达了才算叫醒过 |
| #41 | ops-PER-67-fix-f5f4（fix-f1） | 69ef32d0d1aeff77d6b54505dc8a01be1f260f98 | F5：一个 bot 坏了只挡发给它的；F4：发不出去 45 分钟改报 Coding助手 |
| #42 | ops-PER-67-fix-f2f6（fix-f5f4） | 4ac5c05b048495fd27d50c4a8438848a7d07d7a2 | F2：主目录 agent 退出没送达照报；F6：没送达的停下 45 分钟内到 Coding助手 |
| #43 | ops-PER-67-fix-launch-watch（fix-f2f6） | e34f2ab72c71336f517a1a41ff617927e69e5a74 | 第 6 组：agent 没起来（orca-agent-launch 被拒 / 5 分钟没有第 1 个回合）叫醒派活 bot |

- 各组的修法、TLC 前后、演练前后、备份、gitleaks：`/workspace/ops/briefs/per67-wake-fixes-RESULT.md`（每组一节，末尾是汇总表和真 E2E 缺口清单）。
- 产物：`/workspace/ops/reports/wake-fix-20261019/g1-f7f8`、`g2-f3`、`g3-f1`、`g4-f5f4`、`g5-f2f6`、`g6-launch`，每个目录的 README.md 是入口，`drill/drill.sh` 能复跑（只用假 webhook，HOME 指到输出目录）。
- 发现清单：`/workspace/ops/reports/wake-tla-20261019/findings.md`。
- 合并注意：叠加 PR 要从 #37 起依次合；每合一个，下一个的 base 要改成 main 再合（或者合进上一个分支一路叠到 #43 后整体合 main）。合 main 时用 `gh pr merge --match-head-commit <上表 head>`。PR 正文里的 E2E 一节写的是演练，不是真 E2E，转 ready 之前要先补真 E2E（测试规矩：没有 E2E 结果的 PR 不转 ready）。
- 装：合进 main 后用 `wake/install.sh` 装，`--check` 只比对不写。装之前先备份三台机器上在用的文件。iMac 的 ops 主目录 clone 是在用的代码（有没提交的改动），按 add-then-ff 更新，不要 checkout+pull。

## 2. 卡住检查告警路由（#37–#43 都合进去之后）

| 情况 | 谁先收到 | 发不出去 / 没人收时 |
|---|---|---|
| in-progress 工作区：agent_gone / agent_idle / agent_silent | 派活 bot（按 orca-projects.md 映射；没映射的给 coding-assistant） | 从这次停下算满 `STUCK_ESCALATE_MIN`（默认 45 分钟）还没送达，改发 coding-assistant（F4、F6①） |
| 交给 orca-wake 的补叫醒（recheck） | 派活 bot（经 orca-wake） | 只记 handed，送达才算；交出满 45 分钟没送达转报 coding-assistant（F1、F4） |
| 主目录里包了 notify-run 的 agent 退出，notify-run 没送达 | 派活 bot（agent_gone） | 45 分钟后改发 coding-assistant（F2+F4） |
| completed / in-review 工作区，最后一次停下没送达，停了 45 分钟 | coding-assistant（stop_not_delivered，每次停下只报一次） | ——（F6②） |
| completed 干净工作区、最后一次停下没送达 | 第二类照报 Coding助手（`~/.config/grokbot/stuck-webhook.env`） | ——（F3） |
| 一个 bot 的 webhook 坏了 | 只挡发给它的，别的照发 | ——（F5） |
| stuck-check 自己每次超时 / 出错 | heartbeat-watch 报 coding-assistant（heartbeat_stale） | ——（F7、F8：last_scan 改成上次跑完的扫描） |
| orca-agent-launch 参数被拒（退出码 2/3） | `--bot` 那个 bot（agent_not_started），当场发 | `--bot` 不对、没 webhook 或发不出去，改发 coding-assistant（第 6 组） |
| notify-run --tty 起的 claude 5 分钟没有第 1 个回合 | 派活 bot（agent_not_started） | 改发 coding-assistant（第 6 组；pi / codex 不查） |

- webhook 配置：各机 `~/.config/grokbot/webhooks/<bot>.env`；box 上现在有 coding-assistant、deepvision-ads、deepvision-marketing、deepvision-ops、ops-system、test、vllm-omni、xinyue。box 的 `~/.config/orca-wake/enabled-bots` 已有 ops-system。iMac / MBA 上 ops-system 的配置照 status.md，是「待 Coding助手 配好再测」。
- 合进去之前线上还是旧路由：一个坏 bot 能挡住后面所有叫醒（F5），派活 bot 一直坏时不升级（F4），被拒的 orca-agent-launch 谁也不知道（第 6 组，10-19 07:24 iMac term_b8179e9b 就是这样）。

## 3. EverOS 补写（term_b7d460c5）
- term_b7d460c5（box，/workspace/repos/ops）是 10-19 跑 `/workspace/ops/briefs/everos-rerun-20261018-BRIEF.md` 续跑那个 claude 会话。现在终端里只剩 shell 提示符，agent 已经退出。
- 结果：`/workspace/ops/briefs/everos-rerun-20261018-RESULT.md`（证据在同名 `-evidence/` 目录）。10-18 夜审漏写的 13 个会话（官网 9、vllm 3、广告 1）加广告 f6d10652 全部写进去了，每个都按作用域读回过，没有 500/504、没有重发，也没有重复。标 CHECK 的 4 个是读回太早，01:24 再读都有 episode，不用重发。
- 第 5 项 A+E 放宽：PR #25 已合 main（2026-10-19 07:59:38 SGT），box、iMac 已部署，sha256 一致（site f0967100…、xinyue 40f21751…、repo 0d6f334c…）。
- 没对齐：MBA。`/workspace/ops/reports/mba-collectors-sync-20261019/README.md` 写的是卡住了没同步（main 版采集器只认 `--machine box|imac`）。MBA 上装的是 2ab9812 版（site 1603f4bcddde），见 `/workspace/ops/briefs/per67-mba-collectors-install-RESULT.md`。这一版有没有 #25 的 A+E 放宽，我没核对，交给 ops 系统查。
- 按规矩教训导入和 EverOS 服务端只归 ops 系统；这次补写没改夜审任务，也没改 EverOS 服务器。

## 4. 待 Zack 定的事（都还没有他本人的原话）
1. 合 #37–#43 进 main，然后用 `wake/install.sh` 装到 iMac / MBA / box（换在用的叫醒和卡住检查）。不花钱。要 Zack 本人批。
2. 真 E2E 的范围和顺序（RESULT 末尾 9 项）。真叫醒只发 `test` bot 的、不碰在用安装的几项，Coding助手 批就够；要先装新代码或改 iMac 自动任务的几项，前提是第 1 条。都不花钱。
3. MBA 采集器：要不要把 #25 的 A+E 放宽同步到 MBA，以及 main 版只认 box|imac 的问题怎么解（上面第 3 节）。
4. 已有授权：[Zack答-PER67-6]「按建议顺序把 F1–F8 都派修复，只开 PR」，2026-10-19 12:35 SGT，dr eggbot 私聊卡片，Linear PER-67 评论 873dcfd1。这条只到开 PR，不含合并和安装。

## 5. 没做的（本次收尾）
- 没合并、没部署、没写 Linear、没发真叫醒，也没改三台机器上在用的安装；没删文件，没打印密钥或 webhook。
- 没重跑 TLC 和演练：第 5、6 组在 PR head（4ac5c05、e34f2ab）上都有全量 TLC，exit 0；演练用的脚本 sha256 和 head 上的一致。只补扫了 gitleaks 到 head（no leaks found）。
- 其他 ops 在跑的事（#40 watchdog 已合、box 线上 watchdog 安装、#44 D1–D4 演练 draft、Linear 建单草稿）见 `/workspace/ops/status.md`，不在这份交接里。

## 附：orca-projects.md 核对结果（Coding助手 2026-10-20 19:40 SGT 只读核对，dr eggbot 要求并入交接）
原件 iMac ~/orca/workspaces/ops/orca-projects.md（mtime 10-20 16:55），归 ops 系统维护。
- 第 1 节 repo→项目 ID、第 7 节 MBA：仍对。
- 第 2 节 bot→工作区：大多过时，表头仍是 10-12 快照，要重写：
  - 心月：只有 PER-37/38/39/41/42/43 旧工作区，缺 PER-62 和 MBA runner。
  - deepvision 运维：写「无打开的工作区」，实际 FDV-70、FDV-93/94 在 MBA/iMac 上。
  - vllm：仍是 PER-7~22、PER-40，缺 PER-56。
  - 广告：没标暂停（Zack 10-18 22:19）。
  - ops 系统行（10-20 改）对；coding-assistant 行「ops · PER-67 F 组」交接后改归 ops 系统。
- 第 3c 节下混进 3 行格式不对的表格行（心月 EverOS 启动器 v2.1、PER-71、PER-75），位置也放错了。
- deepvision-site 已搬到 futuredeepvision，第 1 节没写（只在第 7 节）。
