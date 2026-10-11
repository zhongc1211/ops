# Orca 项目与工作区（iMac，2026-10-12 02:45 SGT 核对，共 27 个工作区）

规则：项目按 repo 分，不按 bot 分；每个 Linear 任务一个工作区；显示名「<bot 简称> · <Linear编号> 中文简述」。详见 dev-bot-rules。
来源：`orca-ide --environment iMac repo list / worktree list`。

## 1. Repo → Orca 项目 ID（`--repo id:<ID>`）

| Repo | Orca 项目 | 项目 ID | 路径 |
|---|---|---|---|
| zhongc1211/xinyue-site | xinyue-site | 099c800e-c50c-4cf1-91c6-5d6196a4d298 | ~/pi/remote/xinyue-site |
| zhongc1211/deepvision-site | site | f1681260-cc5c-456d-9b97-e9cd21e07e94 | ~/claude/site |
| vllm-project/vllm-omni | vllm-omni · H3/C1 | b8e788b7-0343-44e2-862e-147ea20adf8f | ~/pi/remote/h3-c1-lab/repository.git |
| deepvision-ads（本地 git） | deepvision-ads | 4e597f43-7d06-4c29-867e-0252425bbbed | ~/orca/workspaces/deepvision-ads |
| ops（本地 git，定时任务） | ops | e9b33f9c-7218-4f6c-b03a-3b85fd8933ac | ~/orca/workspaces/ops |
| zhongc1211/adrunner | adrunner | be131cf2-4bb5-431b-b036-2ed9ac4f9ac3 | ~/claude/adrunner |
| zhongc1211/wa-multi-agent | rf | ac11c2a0-1451-4f68-8630-36dbfd7badb7 | ~/claude/rf |
| worker（无远端） | worker | 5db4802c-9540-4d12-964e-6a95533fab85 | ~/claude/worker |
| zhongc1211/mluxury-website | mingsheng | 8a93cf1a-f058-4f29-be72-52d5aec6e437 | ~/claude/clients/mingsheng |
| vllm-project/vllm | vllm | 78ea9f94-74bc-4a60-92b2-1a9b238b9e43 | ~/claude/gpu/vllm |

## 2. Bot → 当前打开的工作区（不含主目录和已归档）

| Bot | 工作区 | 项目 | Linear |
|---|---|---|---|
| 心月网站 运维 | 心月 · PER-37 涨水爬楼（per-37-flood-climb-v2，099c800e::~/orca/workspaces/xinyue-site/per-37-flood-climb-v2；in-progress，Claude Code 在 term_8e82a2b9） | xinyue-site | PER-37 |
| （建错，保留不用） | per-37-flood-climb（原在重复项目 0de4e55d 下，该项目已从 Orca 移除；磁盘 ~/orca/workspaces/xinyue-site/per-37-flood-climb 保留，无提交） | — | PER-37 |
| deepvision 运维 | dv运维 · FDV-25 本地预览和截图（fdv-16-preview，completed） | site | FDV-25 |
| deepvision 运维 | dv运维 · FDV-16 主站改版方案（fdv-16-redesign-v2，completed） | site | FDV-16 |
| deepvision 运维 | dv运维 · Orca 工作区整理（dv-ops-orca-tidy，completed，10-12 新建，无 Linear） | site | — |
| deepvision 广告产品 | deepvision-ads · 主目录 | deepvision-ads | （FDV-35 未关联） |
| vllm-omni 开发 | vllm · PER-7/8/9/10/11 C1 栈 1–5（c1-1…c1-5） | vllm-omni | PER-7 / 8 / 9 / 10 / 11（in-progress） |
| vllm-omni 开发 | vllm · PER-12 C2 sigma 窗口策略（c2-1-sigma-policy）、vllm · PER-12 C2-1 mypy 修复（c2-1-r3-mypy） | vllm-omni | PER-12（in-progress） |
| vllm-omni 开发 | vllm · PER-13 C2-2 sigma CUDA graph（c2-2-sigma-graphs，跟进见 PER-18） | vllm-omni | PER-13（in-progress） |
| vllm-omni 开发 | vllm · PER-22 C2-1 性能优化（per-22-direct-register） | vllm-omni | PER-22（in-progress） |
| vllm-omni 开发 | 已标 completed（未删）：PER-14 trim（stack-trim）、PER-1/PER-2 rebased ×2、PER-2 H3/C1 原开发目录（h3-c1-lab/worktree） | vllm-omni | PER-14 / 1 / 2 |
| 定时任务 | ops 主目录（显示名 main） | ops | — |

仍在的已归档工作区：H3/C1·Git 数据库（vllm-omni 项目的 bare repo，不能删）、vllm·主目录（Orca 拒绝删除受保护路径）。
不属于任何 bot：adrunner「ui 校正」、rf / worker / mingsheng 主目录。
vllm-omni 工作区已于 2026-10-12 改成新格式（orca CLI）；其他仓库显示名仍不符合新格式「<bot 简称> · <Linear编号> 中文简述」。

## 3. 2026-10-12 已清理（Zack 已批准）
- 从 Orca 移除了重复的 xinyue-site repo 0de4e55d（setup-delete，磁盘 ~/claude/firstmate/projects/xinyue-site 未动）。移除前确认过：旧 per-37-flood-climb 的 HEAD = d6e9d6d，已经在 origin/feat/xinyue-site 上，没有自己的提交，只有未跟踪的 node_modules。
- 删除了 ~/orca/workspaces/xinyue-site/studio-observability（只有 .wrangler 缓存）。
- 删除了工作区 Linear sync run 1、Linear sync run 2、vllm-omni upstream watch run 1。这三个都没有独有的提交；唯一未提交的文件 status.md 已归档到 ~/orca/workspaces/ops/archive/auto-runs-20261012/。

## 3b. 2026-10-12 第二轮清理（Zack 已批准）
存档：~/orca/workspaces/ops/archive/cleanup-20261012/（共 172M）
- 删除旧的 per-37-flood-climb（git worktree remove + 在 firstmate 克隆里 prune）。它在 origin 上，没有自己的提交。
- site 项目：通过 Orca 删除 build-testing、fdv-16-cf-config（HEAD 6809897 在 origin/main 上，没有改动；存档 site-*.tgz，不含 node_modules/.git/.wrangler）。删除 ~/orca/workspaces/site/ 下 11 个散落文件、zh-rewrite/、zh-rewrite.tgz（存档 site-loose-files.tgz）。
- 删除 repository/per-22-brief（存档 vllm-omni-per-22-brief.tgz）。
- 通过 Orca 删除 H3/C1·独立任务、H3/C1·合并前备份、adrunner·UI 优化。存档：vllm-omni-unpushed-branches.bundle（54 个未推送提交，覆盖所有本地分支）；合并前备份的未提交改动存为 .diff 和 -untracked.tgz；adrunner ui 的未提交改动存为 .diff。
- 跳过：~/claude/firstmate/projects/xinyue-site（~/.treehouse 下还有 5 个 worktree 依赖它，已先存 firstmate-xinyue-site-unpushed.bundle，含 16 个未推送提交）；H3/C1·Git 数据库（是 vllm-omni 整个项目的 bare repo）；vllm·主目录（Orca 拒绝删除受保护路径）。

## 4. 需要 Zack 决定
| 项 | 问题 | 建议 |
|---|---|---|
| ~/claude/firstmate/projects/xinyue-site | ~/.treehouse/xinyue-site-eb8bcb/2–6 共 5 个 worktree 依赖它（9/30–10/4，干净，提交都已推送） | 确认 treehouse 不用后再删 |
| H3/C1 · Git 数据库 | 是 vllm-omni 项目的 bare repo，删了整个项目都会丢 | 保留 |
| vllm · 主目录 | Orca 拒绝删除（受保护路径）；干净，没有未推送提交 | 要删的话需要另外批准直接删目录，或先在 Orca 里移除 repo |
| 6 个定时任务的 projectId | 应该放在 ops（e9b33f9c） | 改到 ops 前需要确认 |
| 现有工作区显示名 | 不符合新格式 | 由各 bot 用 worktree set 改名 |
