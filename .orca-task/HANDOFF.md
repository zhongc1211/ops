# 交接：PER-105 FORCE_BOT 强制演练加前缀（iMac → MBA）

写于 2026-10-20 23:41 SGT，iMac。原因：ops 系统 23:40 通知（Coding助手 定）iMac 内存吃紧，任务挪去 MBA。
任务书：box `/workspace/ops/briefs/per105-forcebot-prefix-BRIEF.md`（工作区 `.orca-task/BRIEF.md` 是同一份，本地没提交）。

## 做到哪
- 分支 `zhongc1211/ops-PER-105-forcebot-prefix`，从 #62 的 e5c61f1 切出。代码和测试提交到 `1db646f4bbd06bb046598222bbdc4d1a613f197b` 为止，已普通 push。本交接提交只加了这个文件，没改代码。
- draft PR：https://github.com/zhongc1211/ops/pull/64 ，base = `zhongc1211/ops-PER-105-v5-drill-migration`（#62 分支，head 仍是 e5c61f1，没动）。
- PR 评论五项已写：https://github.com/zhongc1211/ops/pull/64#issuecomment-6294711389
- RESULT 已写：box `/workspace/ops/reports/per105-forcebot-prefix/AGENT-RESULT.md`（同内容另存一份 `RESULT.md`）；产物在 `/workspace/ops/reports/per105-forcebot-prefix/head-1db646f/`。
- Orca 工作区状态已改 in-review，并关联了 PR #64。
- 测试（都在 1db646f 上跑，本地替身检查，不是 E2E）：A 全过；B（e5c61f1）挂 7 条前缀断言（S1、S2、S3、S0、H1、U1、U2）；C 新 head 7 条强制演练 payload 全部放行；E gitleaks 无发现，bash 3.2 lint、`bash -n`、py_compile 通过；F 本 PR 没有引入新的冲突块；回滚实测回到 B 的结果。

## 下一步（接手的人）
1. 这个交接提交让 PR head 从 1db646f 变了。代码和 1db646f 一样（只多了 `.orca-task/HANDOFF.md`），但按测试规矩 head 变了要重跑：在 MBA 上 `git fetch` 后切到本分支，跑 `FORCEBOT_PREFILTER=<git show origin/zhongc1211/ops-PER-88-wake-prefilter:wake/bin/wake-prefilter 拷到临时目录> /bin/bash wake/tests/forcebot-prefix.sh . <产物目录>`，把结果和新 head 全 sha 补进 PR 评论和 RESULT。
2. 这个文件在 PR 合并前要不要删，由 ops 系统 / Coding助手 定。它进了 PR diff；如果不想让它进 main，就在本分支另提交删掉（不要 force、不要 rebase）。
3. #62 已经合进 main（origin/main cf2781f，第二个父提交 = e5c61f1）。PR 描述写了 base 可以改成 main，还没改，要等 Zack / Coding助手 决定。
4. 合并、`gh pr ready`、改三台线上脚本都要 Zack 另外批。

## 没跑完 / 没跑的
- D（真实使用）没跑：iMac 刚重启，load 超 12；确认不了没有别的演练/E2E 在跑；stuck-check 强制演练时 cfg=stuck 那条照样发 stuck-webhook，做不到只叫醒 ops-system。unpushed_scan.py 用 `--only` + 临时 `--state` + `UNPUSHED_FORCE_BOT=ops-system` 理论上能只叫醒 ops-system，要跑就按任务书 D 的条件做，最多一次。
- 新 head（交接提交后的 head）上没跑 A/B/C，见「下一步」第 1 条。
- MBA 环境下还没跑过任何测试；MBA 上的 bash / python 版本没核对。
- EverOS `recall_agent_experience`：iMac 会话里没有这个工具，没调。
- 没动：三台线上脚本、test.env（含 .bak）、v5 routine、`~/.local/bin`、`~/.orca-state/bin`、`~/.config/orca-wake`、enabled-bots、Orca automations；#62、PER-88 和其他 PR 分支都没写。
