# PER-117 交接：挪去 MBA（iMac 2026-10-20 ~23:45 SGT，ops 系统 23:40 指示）

brief：`ssh box 'cat /workspace/ops/briefs/per117-linear-sync-move-BRIEF.md'`（以文末「补充」「续做」两节为准）。
执行者：iMac Orca 工作区 ops-PER-117-linear-sync-move 里的 Claude Code。

## 现在的状态
- 分支 `zhongc1211/ops-PER-117-linear-sync-move`，全部已普通 push（没 force）。
- base = #49 head `a8a0a2156eadacd0d84d821335da3b4c8f3eefb0`（开工和 23:4x 再 fetch 都是它）。
- 提交：
  - `d152c43d8b342880f63ab598cbb6a3de1ecd227a` 主改动（defs.json、make-prompts.py、删 prompts/imac/vllm-upstream.prompt.md、README、run-e2e.sh 的 pre 拷贝和 L1/W3 锁名、新增 e2e/per117-dryrun.sh、orca-projects.md 第 7 节一行）
  - `99e6cfe746d4e7386686b420fa9b426baefb7de0` run-e2e.sh R1b/R1c 写死的条数改成 22 / iMac 9 / grace 7（d152c43 上的演练查出来的，我第一次 grep 漏了）
  - 本交接提交
- draft PR：https://github.com/zhongc1211/ops/pull/65（base = #49 的分支）。描述按 d152c43 写的，C 写的是「待补」，**要更新**。PR 评论（五项）**还没写**。
- 新增行数：d152c43 共 +69；99e6cfe +3/−3（替换）。
- 没注册、没改任何线上 automation，没跑 --apply，没往 #49/#50/#45/main 写。
- 工作区状态还没改 in-review；box 上的 AGENT-RESULT.md 还是上一轮「第一次停下」的旧内容，**没覆盖**。
- 没有 EverOS `recall_agent_experience` 工具（iMac 这个会话），记一句接着做的。

## 在 d152c43 上跑过的（产物在 box `/workspace/ops/reports/per117-linear-sync-move/head-d152c43/`）
- A/B `per117-dryrun.sh`：新 head 11/11 PASS，exit 0；在 base 树（a8a0a21 worktree）上 exit 1，FAIL 原文：
  `FAIL I1 imac 没有 vllm 上游那条 create` / `FAIL I3 imac 只少了 vllm 那一条：9 条命令，其余行和 base 一样` /
  `FAIL X1 box 没有 edit 349967f6` / `FAIL X2 box 末尾 later 清单没有 349967f6，bc9ee42b 还在` /
  `FAIL X3 box 只少了 349967f6：12 条命令（4 create + 8 edit），其余行和 base 一样` / `FAIL C2 三台合计 22 条 create（MBA 9、iMac 9、box 4）`。
  假 orca 日志 0 字节。diff：imac 只少 vllm 那 3 行，box 只少 edit 349967f6 两行和 later 清单一行，mba 无差异。
- 回滚 ④：临时分支 `git revert --no-commit d152c43`，树与 a8a0a21 0 行差异；重跑三台 dry-run 与 base 输出 0 行差异；临时分支已删。
- D：make-prompts --check 0、json.tool 通过、bash -n 通过、lint-bash32-utf8（本分支没有这个文件，用 `git show origin/main:wake/tests/lint-bash32-utf8.sh`）ok。99e6cfe 上 run-e2e.sh 又跑过 bash -n 和 lint，ok。
- E：gitleaks 8.30.1 `--log-opts "a8a0a21..HEAD"`：1 commit，no leaks found。
- F：merge-tree 对 origin/main 3f1971d、#50 220cc3a、#45 7d12370 都 rc=0，无冲突文件。
- C `run-e2e.sh both`（**在 iMac 上跑的**，脚本按「本机是 MBA、经 ssh imac」写；iMac 上 `ssh imac` 报 Host key verification failed，所以 iMac 侧检查都挂）：
  - head d152c43：post 46 PASS / 16 FAIL；base 树 a8a0a21：post 48 PASS / 14 FAIL；两边 pre 都 62 FAIL。
  - 两边都挂的 14 项（ssh imac / 环境）：D3b M1i W1a W1b W1c W2b W2d W3b W4 W6 W7a W7c W8b W8d。
  - 只有 head 挂的 R1b、R1c：写死的条数，99e6cfe 已修。
  - 参考：#49 在 MBA 上 f3fb2bc 的已知结果是 post 62 PASS、pre 62 FAIL。

## 下一步（在 MBA 上）
1. `git fetch && git checkout zhongc1211/ops-PER-117-linear-sync-move`（到本交接提交）；先 fetch 看 #49 是否还在 a8a0a21，动了且碰到本任务文件才停。
2. 在最终 head 上重跑：A/B（`/bin/bash automations/migration-1020/e2e/per117-dryrun.sh`，以及对 a8a0a21 的 worktree 跑一次要挂）、D、E（范围仍用 a8a0a21..HEAD）、F。
3. C：在 MBA 上跑 `run-e2e.sh both`（这是它设计的机器），先看 `sysctl -n vm.loadavg`，>16 等，最多 30 分钟。预期 post 62 PASS；和 #49 已知结果比，只该有 vllm 相关变化（R1b/R1c 条数、L1/W3 锁名）。
4. 更新 PR #65 描述（C 结果、最终 head sha、行数含 99e6cfe），写五项 PR 评论（回退测试附上面 FAIL 原文、真实使用证据、head 全 sha、回滚、没跑的）和「为什么安全」，gitleaks 原文贴评论。
5. 覆盖写 box AGENT-RESULT.md（旧内容挪成文末「第一次停下」），产物放 `head-<短sha>/`；工作区状态改 in-review。

## 没跑完 / 没跑的测试
- C 在 99e6cfe 上没跑；C 在 MBA 上没跑。
- A/B、D、E、F、回滚在 99e6cfe 和本交接提交上没重跑（99e6cfe 只改了 run-e2e.sh 里 R1b/R1c 两行，不影响 register.sh 输出）。
