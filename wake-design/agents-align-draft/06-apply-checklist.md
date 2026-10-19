> **DRAFT — 应用清单，还没执行任何一项。** 每项打勾前要有证据（PR 链接 / commit / 文件 diff）。

## 怎么落地（两条路，缺一不可）

- **主分支 PR**：改仓库 `AGENTS.md`，走正常 PR → CI 绿 → 合并。只影响合并之后新建的工作区。
- **已有 worktree 刷新**：已经开着的工作区不会自动拿到新版。二选一：
  - 派活时让 coding agent `git fetch && git rebase origin/<base>`（有冲突就停下报告，不强推）；
  - 或在派活 prompt 里贴 00 的测试段（中文或英文）+ 一句「以此为准」。临时办法，下次派活还要贴。
- 本次文档类 PR 只改 AGENTS.md，没有行为改动；「每个 PR 跑 E2E」对它写「没跑：纯文档改动」即可。

## 已定（Zack 2026-10-16，SGT）

1. dv广告生产部署：派活写明了才可以 — **已定**（见 04）。
2. 心月部署段 +「本地 Playwright 带替身不算 E2E」— **已定**（见 03；应用时仍核实分支 / Workers Builds）。
3. push / 开 PR / 部署：派活写明了才可以 — **已定**（Zack approved 2026-10-16）。
4. 任何项目都不指定用什么 agent — **已定**（全文已改成「coding agent」中性写法）。

## 仍待定

- [ ] box 要不要建全局 `~/.pi/agent/AGENTS.md` / `~/.claude/CLAUDE.md`。
- [ ] dev-bot-rules 要不要加「派活前确认工作区 AGENTS.md 是最新」。

## P0

- [ ] **dv广告主分支加 AGENTS.md**（文件：04）
  - 谁：deepvision-ads bot 派 Orca 里的 coding agent；iMac Orca（轻活）。
  - 怎么：新 issue + 新工作区，base=main，从 iMac FDV-58-AGENTS测试规矩 的 32 行版起，替换成 04 全文；开 PR。
  - 合并后：FDV-* 进行中的工作区 rebase 或 prompt 贴英文测试段。
- [ ] **dv官网 AGENTS.md 替换**（文件：02）
  - 谁：deepvision-ops bot 派 Orca 里的 coding agent；iMac Orca。
  - 怎么：base=当前 origin 默认分支（159 行版），替换成 02 全文；开 PR。
  - 合并后：iMac 3 个 153 行旧工作区（FDV-60-套餐对比、Open-Design-重设计、dv运维-CI-自动部署）还在用的就 rebase，不用的归档；box `/workspace/repos/deepvision-site`、`/workspace/site-edit` 拉到最新（P2）。

## P1

- [ ] **iMac 全局 `~/.pi/agent/AGENTS.md` 追加**（文件：01）
  - 谁：Zack 本人或 bot 派 iMac Orca 里的 coding agent（改 home 目录文件，不走 PR）。
  - 怎么：先备份 `.bak-20261016`，追加 01 里的代码块，`diff` 贴回报告。
  - 验证：iMac 新开一个 coding agent，问「本机测试规矩是什么」，确认能复述 PR head E2E 要求；并确认未被要求使用特定工具。
- [ ] **（可选，仍待定）box 全局文件**：box 没有 `~/.pi/agent/AGENTS.md` / `~/.claude/CLAUDE.md`。要让 box Orca 里的 coding agent 也读到，照 01 建这两个文件（`~/.claude/CLAUDE.md` 一行 `@~/.pi/agent/AGENTS.md`）。需 Zack 点头。
- [ ] **心月 AGENTS.md 更新**（文件：03）
  - 谁：xinyue bot 派 Orca 里的 coding agent；iMac Orca。
  - 先做：实查心月部署方式（Workers Builds 是否已接、分支名），把 03 部署段里「应用时核实」那句改成实际值。
  - 怎么：base=主分支 aca529e 之后的最新，替换成 03 全文；开 PR。
  - 合并后：iMac 10 个 / box 6 个旧版工作区（PER-27/28/38..52 等）还在跑的 rebase 或 prompt 贴中文测试段；已完成的归档。
- [ ] **vllm 派活模板加覆盖段**（文件：05）
  - 谁：vllm-omni bot，改自己的派活模板（bot 端，不进仓库）。
  - 验证：下一次 vllm 派活 prompt 里能看到这段。
- [ ] **（仍待定）dev-bot-rules 加一句**（bot 端，不进仓库）：「派活前确认工作区 AGENTS.md 是最新版（有测试规矩段）；不是就让 coding agent rebase，或在 prompt 里贴测试段。」

## P2

- [ ] 统一「Orca」段已经随 02/03/04 进仓库（一句 notify-run + 别静默停住）；叫醒 v5 细节继续只放 dev-bot-rules，不往仓库里加。
- [ ] iMac 旧 checkout 标弃用或清理：`~/claude/site`、`~/cutover-20261008/build`、`~/pi/remote/xinyue-site*`、`~/.treehouse/xinyue-site-*`、`~/claude/firstmate/projects/xinyue-site`。先问 Zack 是否还在用。
- [ ] firstmate 合约（426 行，「叫用户 captain」）：确认是否还在用，不用就归档。
- [ ] box `/workspace/agent.md` 改名（如 `car-assistant-memory.md`），避免被当成 AGENTS.md。改名前确认车载助手没有按路径读它。
- [ ] box `/workspace/repos/*` 旧 checkout 拉到最新。

## 不做

- 不改上游 vLLM 的 AGENTS.md / CLAUDE.md，不给 vllm-omni 加 AGENTS.md。
- 不把叫醒 v5 / webhook / dedup_key 细节写进任何仓库或全局文件。
- 不在任何项目 AGENTS.md 或派活模板里指定用哪种 coding agent。
