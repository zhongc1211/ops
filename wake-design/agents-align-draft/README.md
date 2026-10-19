# AGENTS.md 对齐草稿（DRAFT — 还没进任何仓库，也没改 iMac 文件）

依据：`../AGENTS-REVIEW.md`（box + iMac 审查）和 bot 端 `dev-bot-rules`。这里只有草稿，所有仓库 AGENTS.md、iMac `~/.claude`、`~/.pi` 都没动。

## 每份文件是干什么的

| 文件 | 用途 | 放到哪 |
|---|---|---|
| 00-shared-testing-block.md | 统一的测试规矩段（中文 + 英文），02/03/04 里的测试段都从这里来；也可直接贴进派活 prompt | 各 web 仓库 AGENTS.md；旧 worktree 的派活 prompt |
| 01-global-agents.md | iMac 全局追加段：测试规矩 + 「仓库测试写法冲突时以此为准」+ 跨项目默认（派活写明才 push/PR/部署、cf CLI、notify-run） | iMac `~/.pi/agent/AGENTS.md` 末尾（若有配置文件 `@` 引用该路径也会读到） |
| 02-deepvision-site-AGENTS.md | dv官网 AGENTS.md 全文：删「补回归测试 / Vitest」冲突、删「执行 Agent 不 push/PR/部署，由主 Agent 做」、加部署与 CI、PR head E2E 报告格式；**不指定用哪种 coding agent** | deepvision-site 仓库根 |
| 03-xinyue-site-AGENTS.md | 心月 AGENTS.md 全文：产品要求原样保留，测试段补 PR head / 硬件 / commit，加部署与 CI、Orca 段 | xinyue-site 仓库根 |
| 04-deepvision-ads-AGENTS.md | dv广告 AGENTS.md 全文（英文）：删「逻辑配 Vitest」、PR 前不再只跑 npm test、改成 PR head 真实 E2E + 报告字段 | deepvision-ads **主分支**仓库根（主分支现在没有这个文件） |
| 05-vllm-dispatch-overlay.md | vllm 派活 prompt 开头贴的一段，覆盖上游「unit 优先」 | vllm 派活模板（不进仓库） |
| 06-apply-checklist.md | 谁、在哪、按什么顺序应用；P0/P1/P2 | — |

## 已定（Zack 2026-10-16，SGT）

1. **dv广告生产部署**：派活写明了才可以（草稿原文保留）。
2. **心月部署段 +「本地 Playwright 带替身不算 E2E」**：已批准。应用时再核实分支名 / Workers Builds 是否已接。
3. **push / 开 PR / 部署**：派活写明了才可以（Zack 已批准，不再标为编辑决定）。
4. **任何项目都不指定用什么 agent**：草稿全文已去掉对具体 coding agent / 工具的指名或偏好；一律写「coding agent」。notify-run 示例也不绑定具体 agent。

## 仍待定

- box 要不要建全局文件（`~/.pi/agent/AGENTS.md`、`~/.claude/CLAUDE.md`）。
- dev-bot-rules 要不要加「派活前确认工作区 AGENTS.md 是最新」。

## 应用顺序

- **P0**：04 dv广告（主分支没有文件，规则自相矛盾）→ 02 dv官网（Vitest/回归冲突）。
- **P1**：01 iMac 全局（一次覆盖所有项目和旧工作区，最省事）→ 03 心月 → 05 vllm 派活模板 →（待定）dev-bot-rules 加「派活前确认工作区 AGENTS.md 是最新」。
- **P2**：旧 checkout / firstmate 清理、`/workspace/agent.md` 改名、box 旧 checkout 更新。

细节见 06。

## 应用时注意

- 心月：合并前实查 Workers Builds / 分支名，把 03 部署段里的「应用时核实」注改成实际值（或「迁移中」）。
- 现有单元测试不删。规矩是「写完代码不补单测、单测不算验收」，不是清掉老测试。

## 和 worktree 的关系

- 主分支合并新 AGENTS.md 后，**已经开着的 worktree 不会自动更新**。审查里 41 份 box 文件有 35 份旧版或缺段；iMac 上 dv官网 3 个、心月 10 个工作区读不到完整规矩。
- 还在跑的工作区：派活时让 coding agent rebase 到最新 base；rebase 不方便就在派活 prompt 里贴 00 的测试段，写「以此为准」。
- 01（iMac 全局）不依赖 rebase，加上后 iMac 上所有工作区立刻生效，所以它是旧 worktree 的兜底。box 上没有全局文件，box 的旧 worktree 只能靠 rebase 或 prompt。
- vllm 永远靠 05（prompt），因为上游文件不改。

## 叫醒规则放哪

仓库里只写一句「超过 15 分钟的命令用 notify-run 包，做完别静默停住，最后一条写结论 + 报告路径」。叫醒 v5 的完整规则（dedup_key、needs_input、.orca-wake-mute、webhook）继续只放 bot 端 dev-bot-rules。
