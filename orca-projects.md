# Orca 项目与工作区（iMac，2026-10-12 02:45 SGT 核对，共 27 个工作区）

规则：项目按 repo 分，不按 bot 分；每个 Linear 任务一个工作区；显示名「<bot 简称> · <Linear编号> 中文简述」。详见 dev-bot-rules。
来源：`orca-ide --environment iMac-tailnet repo list / worktree list`。

## Orca 版本（钉）

对应 PER-131（MBA/iMac/box 版本统一）。任何再升级先给 Zack 弹卡，批了再动。

| 机器 | Orca 版本 | 日期 | 旧版本 |
|---|---|---|---|
| iMac | 1.4.244 | 2026-10-29 | 1.4.237 |
| MBA | 1.4.244 | 2026-10-29 | 1.4.240 |
| box（Linux CLI） | 1.4.237 | — | 不在这次升级范围，没升 |

升级方法（两台 Mac 一样，Orca 没有 CLI 升级命令，是手动换 `/Applications/Orca.app`）：
1. 下载 `Orca-1.4.244-arm64-mac.zip`，sha256 对上 GitHub release 的 digest。
2. `ditto -x -k` 解到暂存目录，`codesign --verify --deep --strict` 通过。
3. TERM 退出 Orca 和 headless runtime（terminal-host 守护进程保着 PTY，终端不丢）。
4. 旧 app 挪到本机 `~/ops-archive/orca-upgrade-20261029/`（iMac 是 `Orca-1.4.237.app`，MBA 是 `Orca-1.4.240.app`）。
5. `ditto` 新 app 进 `/Applications`，`open -a Orca`。

回滚：退出 Orca，把 `~/ops-archive/orca-upgrade-20261029/` 里的旧 app 挪回 `/Applications/Orca.app`，再 `open -a Orca`。

## 1. Repo → Orca 项目 ID（`--repo id:<ID>`）

| Repo | Orca 项目 | 项目 ID | 路径 |
|---|---|---|---|
| zhongc1211/xinyue-site | xinyue-site | 099c800e-c50c-4cf1-91c6-5d6196a4d298 | ~/pi/remote/xinyue-site |
| zhongc1211/xinyue-site（**box** Orca，orca-ide 不带 --environment） | xinyue-site | 2ce7debc-6211-416a-b5a0-81127a67f518 | /workspace/repos/xinyue-site |
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
| 心月网站 运维 | **box** 心月 · PER-38 摇摇荡荡（2ce7debc::/home/box/orca/workspaces/xinyue-site/心月-PER-38-摇摇荡荡；in-progress，Claude Code 在 box term_ea25260e） | xinyue-site(box) | PER-38 |
| （停用，保留） | iMac 旧 per-38-swing-swing（099c800e::~/orca/workspaces/xinyue-site/per-38-swing-swing；无提交，2026-10-12 迁到 box） | xinyue-site | PER-38 |
| 心月网站 运维 | **box** 心月 · PER-39 大嘴洞洞（2ce7debc::/home/box/orca/workspaces/xinyue-site/心月-PER-39-大嘴洞洞；in-progress，Claude Code 在 box term_83a12bdf） | xinyue-site(box) | PER-39 |
| （停用，保留） | iMac 旧 per-39-gobble-hole（099c800e::~/orca/workspaces/xinyue-site/per-39-gobble-hole；无提交，2026-10-12 迁到 box） | xinyue-site | PER-39 |
| 心月网站 运维 | 心月 · PER-42 摇摇荡荡 3D（心月-PER-42-摇摇荡荡-3D，**box** 2ce7debc::/home/box/orca/workspaces/xinyue-site/心月-PER-42-摇摇荡荡-3D；Claude term_b9778321；in-progress） | xinyue-site | PER-42 |
| 心月网站 运维 | 心月 · PER-43 大嘴洞洞 3D（心月-PER-43-大嘴洞洞-3D，**box** 2ce7debc::/home/box/orca/workspaces/xinyue-site/心月-PER-43-大嘴洞洞-3D；Claude term_e66dc20c；in-progress） | xinyue-site | PER-43 |
| 心月网站 运维 | 心月 · PER-41 涨水逃生 3D（心月-PER-41-涨水逃生-3D，**box 排队** 2ce7debc::/home/box/orca/workspaces/xinyue-site/心月-PER-41-涨水逃生-3D；flood-3d-queue.sh 等 42/43 done；iMac load≈11.5 未用 iMac） | xinyue-site | PER-41 |
| deepvision 运维 | （site 项目无打开的工作区，只剩主目录 ~/claude/site；见 3c） | site | — |
| deepvision 广告产品 | deepvision-ads · 主目录 | deepvision-ads | （FDV-35 未关联） |
| vllm-omni 开发 | vllm · PER-7/8/9/10/11 C1 栈 1–5（c1-1…c1-5） | vllm-omni | PER-7 / 8 / 9 / 10 / 11（in-progress） |
| vllm-omni 开发 | vllm · PER-12 C2 sigma 窗口策略（c2-1-sigma-policy）、vllm · PER-12 C2-1 mypy 修复（c2-1-r3-mypy） | vllm-omni | PER-12（in-progress） |
| vllm-omni 开发 | vllm · PER-13 C2-2 sigma CUDA graph（c2-2-sigma-graphs，跟进见 PER-18） | vllm-omni | PER-13（in-progress） |
| vllm-omni 开发 | vllm · PER-40 调度开销分析（b8e788b7::~/orca/workspaces/repository/vllm-PER-40-调度开销分析；base #8746 head 48f7dac47；in-progress，Claude Code Opus max 在 term_a9e6a444；2026-10-12 19:4x 建） | vllm-omni | PER-40（in-progress） |
| vllm-omni 开发 | vllm · PER-22 C2-1 性能优化（per-22-direct-register） | vllm-omni | PER-22（in-progress） |
| vllm-omni 开发 | 已标 completed（未删）：PER-14 trim（stack-trim）、PER-1/PER-2 rebased ×2、PER-2 H3/C1 原开发目录（h3-c1-lab/worktree） | vllm-omni | PER-14 / 1 / 2 |
| ops-system | ops 主目录（显示名 main）和 ops 项目下所有工作区（iMac e9b33f9c / box 5aaefe84 / MBA；原写「定时任务」→ 映射到不存在的 ops.env 落到 coding-assistant，2026-10-20 改归 ops 系统） | ops | — |
| coding-assistant | ops · PER-67 F 组（box，Coding助手 派，Coding助手 续做；按 Linear 编号仍报给它） | ops | PER-67 |

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

## 5. Box（Grok Bot 电脑）Orca 项目与工作区（2026-10-12 03:20 SGT 核对）

Box 与 iMac 是两套独立 Orca runtime；同名仓库在 box 上另有项目 ID。

### 5.1 Box Repo → Orca 项目

| Repo | Orca 项目 | 项目 ID | 路径 |
|---|---|---|---|
| zhongc1211/deepvision-ads | deepvision-ads | d0561e2b-422a-43f1-8a0b-7c117ac910b2 | /workspace/repos/deepvision-ads |
| zhongc1211/xinyue-site | xinyue-site | 2ce7debc-6211-416a-b5a0-81127a67f518 | /workspace/repos/xinyue-site |
| zhongc1211/deepvision-site | deepvision-site | 6e7df308-3fb4-40a1-be00-cbe5675ea4eb | /workspace/repos/deepvision-site |
| vllm-project/vllm-omni | vllm-omni | b0a44d4f-7c5d-49e5-9848-9e6010beeaeb | /workspace/repos/vllm-omni |

### 5.2 Box 当前工作区

| 工作区 | 项目 ID | 路径 | 分支 | 备注 |
|---|---|---|---|---|
| deepvision-ads · 主目录 | d0561e2b… | /workspace/repos/deepvision-ads | main | 主 checkout |
| dv广告 · FDV-36 Ryze 复刻总装 | d0561e2b… | /home/box/orca/workspaces/deepvision-ads/fdv-36-build | zhongc1211/fdv-36-build | Claude Code 在此总装（iMac 卡顿迁移）；term_0f2abdaa |
| xinyue-site · 主目录 | 2ce7debc… | /workspace/repos/xinyue-site | feat/xinyue-site | 仅主目录，无任务工作区 |
| deepvision-site · 主目录 | 6e7df308… | /workspace/repos/deepvision-site | main | 仅主目录 |
| vllm-omni · 主目录 | b0a44d4f… | /workspace/repos/vllm-omni | main | 仅主目录 |

## 6. Claude Code ↔ Orca 工作树对齐（2026-10-12 03:20 审计）

### 6.1 活跃 Claude 会话 cwd 是否等于所属 Orca 工作区

| 机器 | 终端 | 标题 | Orca 工作区 | 进程 cwd | 结论 |
|---|---|---|---|---|---|
| box | term_0f2abdaa | FDV-36 briefs/BUILD.md 执行 | …/deepvision-ads/fdv-36-build | 同左 | ✅ 对齐 |
| iMac | term_8e82a2b9 | Flood Climb PER-37 | …/xinyue-site/per-37-flood-climb-v2 | 同左 | ✅ 对齐 |
| iMac | term_8578b833 | Panel title guard FDV-16 | …/site/fdv-16-redesign-v2 | 同左 | ✅ 对齐 |
| iMac | term_56806268 | Orca 工作区 FDV-16/25 元数据 | …/site/dv-ops-orca-tidy | 同左 | ✅ 对齐 |
| iMac | term_691ce33d | TASK.md folder task | deepvision-ads **主目录** | 同左（主目录） | ⚠ 在主目录干活，未用 FDV-35/36 任务工作区 |
| iMac | term_e60b2461 | Cloudflare 账单刺客 | folder 上下文（无 repo 工作区） | （folder） | ⚠ 不在 git 工作区里 |
| iMac | （无 Orca 终端） | claude PID 7049 | — | ~/claude | ⚠ 游离会话 |
| iMac | （无 Orca 终端） | claude PID 9785 | — | ~/claude/cf（非 git） | ⚠ 游离会话 |

### 6.2 git 有、Orca 原先未管理 / Claude 自建

| 路径 | 状态 | 处理 |
|---|---|---|
| ~/.treehouse/xinyue-site-eb8bcb/2–6（挂在 firstmate 克隆上） | detached、干净、旧 Claude/treehouse | **留给 Zack**：确认不用后再删；有未推送 bundle 已存档 |
| /private/tmp/nightly-deepvision-site、/private/tmp/nightly-xinyue-site | detached、干净；开启 external 可见后已出现在 Orca | 定时/夜间残留；无未提交改动。是否删留给运维判断 |
| ~/pi/remote/vllm-omni 下 c4-lab/* | 非 Orca 管理；有历史 review worktree | 有真实路径，未删 |
| /tmp/vllm-omni-review-… | prunable 失效条目 | **已 git worktree prune** |
| ~/claude/rf/.claude/worktrees | 空目录 | 无内容 |
| site fdv-16-redesign-v3 | 进程曾指向此路径，目录已不存在 | 无需注册 |

### 6.3 Orca 自带能力（查过 agent-context / help）

| 能力 | 怎么开 | 本次是否改 |
|---|---|---|
| `orca repo set --external-worktree-visibility show` | 让非 Orca 的 git worktree 显示在侧栏 | **已开**：box 的 xinyue/ads；iMac 的 xinyue/ads/rf |
| `orca worktree create --agent claude` | 在新 Orca 工作区首个终端启动 Claude，cwd=该工作区 | 未改配置；这是正确用法 |
| `orca terminal create --worktree <sel> --command claude` | 在已有 Orca 工作区开 Claude | 正确用法 |
| `orca claude-teams …` | 仅在 Orca 终端内；队友开成 native splits，仍在当前工作区 | 未改 |
| `project setup-update --worktree-base-path` | 新工作区落盘根目录 | 未改（当前已多在 ~/orca/workspaces/…） |
| 收养/同步 Claude 自建 worktree（.claude/worktrees、~/.treehouse） | **无** CLI「adopt」命令；`worktree create` 只会新建 checkout | — |
| 把 Claude 钉死在工作区、禁止它自建 | Orca **无**硬开关。Claude 的 `claude --worktree`、feature `tengu_worktree_mode`、部分 `remoteControlSpawnMode: worktree` 会自建 | **未改** Claude 全局配置（不安全乱改 GrowthBook/spawn） |

### 6.4 以后怎么避免错位

1. 动手只走 `orca worktree create --agent claude`（或先 create 工作区再 `terminal create --command claude`），**不要**在 shell 里 `claude --worktree`。
2. 每个 Linear 任务一个 Orca 工作区；禁止在「主目录」开长任务（本次 TASK.md 会话是反例）。
3. 需要看野 worktree 时，对该 repo 开 `external-worktree-visibility show`。
4. treehouse / `.claude/worktrees` 视为 Claude 私货，有未提交内容才考虑迁入 Orca；干净的可删（要 Zack 点头）。


## 3c. 2026-10-12 14:5x deepvision 运维 收尾（Coding助手 派，Zack 已定）
- 删除 iMac ~/cutover-20261008/build-fdv54（生产构建目录，git worktree remove）。~/cutover-20261008/build-testing 已不存在（3b 已删）。fdv-16-preview（FDV-25）此前已不在列表。
| 心月网站 运维 | 心月 · EverOS 启动器 v2.1（iMac 099c800e::~/orca/workspaces/xinyue-site/心月-EverOS-启动器-v2.1；Claude term_4be9a6d2；in-review，2026-10-17） | xinyue-site | — |
| 心月 | PER-71 | MBA ~/orca/workspaces/xinyue-site/per-71-colorfigures-a | 心月 · PER-71 Colorfigures 框架与总入口 | 2026-10-19 |
| 心月 | PER-75 | iMac ~/orca/workspaces/xinyue-site/per-75-oss-games | 心月 · PER-75 开源游戏候选调研 | 2026-10-19 |

## 7. MBA（MacBook Air）Orca 项目（2026-10-18 16:00 SGT 建，box 上的 Claude Code 经 iMac `ssh mba` 做）

MBA：Apple M2 / 8 核 / 8 GB，macOS 26.6.2，Orca 1.4.244（2026-10-29 升，旧 1.4.240），用户 jiawenwang，tailnet 100.64.0.7。iMac 上 `orca --environment mba …`（环境名小写 mba）。
MBA 是第三套独立 Orca runtime，同名仓库在 MBA 上另有项目 ID。主 checkout 放 `~/orca/projects/<repo>`（ops 和 iMac 一样放 `~/orca/workspaces/ops`），工作区按 Orca 默认建在 `~/orca/workspaces/<repo>/…`。

| Repo | Orca 项目 | 项目 ID | 路径 | 分支 |
|---|---|---|---|---|
| zhongc1211/ops | ops | 659a8841-0b19-4204-859d-85fdaf05f7b3 | ~/orca/workspaces/ops | main |
| zhongc1211/xinyue-site | xinyue-site | 1c963975-d649-4453-8e06-b755dfafa113 | ~/orca/projects/xinyue-site | feat/xinyue-site |
| zhongc1211/deepvision-site（现 futuredeepvision/deepvision-site） | deepvision-site | d1fae3d4-64a2-4d93-96fe-a5a454e63cfc | ~/orca/projects/deepvision-site | main |
| zhongc1211/deepvision-ads | deepvision-ads | 4e5bd73a-a952-4b4a-bfe5-d455ffa26454 | ~/orca/projects/deepvision-ads | main |
| vllm-omni：origin = fork zhongc1211/vllm-omni（blob:none），upstream = vllm-project/vllm-omni | vllm-omni | c1ee517c-7679-44df-b3dd-2a5e761700d4 | ~/orca/projects/vllm-omni | main |

另有 Zack 自己建的 `local`（25037673-35e6-4129-a963-7016a63d6101，~/orca/projects/local），不动。
EverOS：上面 4 个业务仓库的主 checkout 都用 `claude mcp add -s local everos` 接好；pi 扩展 `everos.ts` 的根目录表加了 `~/orca/projects/<repo>`。
