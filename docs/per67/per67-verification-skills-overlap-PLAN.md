# PER-67 × pstack 三个验证 skill：重叠、冲突、改进计划（dr eggbot，2026-10-19 11:2x SGT）
> **状态：已批准**。Zack 原话「就按你说的办」，2026-10-19 11:18 SGT，dr eggbot 私聊；Linear PER-67 评论 [Zack答-PER67-5]（id 3311021f-f102-41b8-a1d8-6da9b6ddd4ae）。决定 1–5 已定（见第 4 节）；合 main、动生产、花钱仍逐张卡片批。
依据：pstack 0.15.27 的 create-verification-skill、create-formal-verification-skill、maintain-verification-skill 三份 SKILL.md 全文，加 feature-map-example 和 docs/harness/claude-code.md；方案 v3 的四份文件（eggbot-VIEW、REVIEW-coding 含 13 条反复出错、poteto-REVIEW、everos-lessons）；ops main 已合 #16–#21、#23–#27、#29–#35（#22 关闭未合，#28 SYSTEM_MAP 和 ops verify 还 open）。
用 gh 只读查过各仓库（xinyue-site feat/xinyue-site、futuredeepvision/deepvision-site main、vllm-omni fork main、deepvision-ads main）：**哪个仓库都还没有 FEATURE_MAP、features/ 或驱动 CLI**。FDV-92 还没开工，搜到的只有 FDV-70 的 PR。
现有的验证材料：心月有 playwright（含 tests/testing-e2e/）、官网有 tests/e2e/*.spec.ts、两边都有 docs/solutions/；vllm fork 里是上游自带的 `.claude/skills/`（vllm-omni-test、precheck-pr 等 12 个）。

## 1. 重叠表
| 方案项 | 对应的 skill 部分 | 结论 |
|---|---|---|
| 项目驱动 CLI（三个关键脚本之一） | create-verification-skill 第 2 节 verify-<app>：Launch / Doctor / Drive / Evidence / Cleanup / Helpers | **合并**：skill 负责生成和说明，CLI 是它附带的 Helper（可执行、调用写在正文里）。CLI 的硬要求不变：0 用例或缺产物时退出码非 0、报告里的 sha 要等于 head、失败自动在 base 上重跑、产物遮蔽密钥，这几条都写进 Evidence 节 |
| Feature Map | 第 3 节 `verify-<app>/features/`：README 索引 + 每个功能一个文件，固定 4 个 H2 | **用它替换我们自己的格式**（我们还没写，没有重复）。SYSTEM_MAP 也用同一格式（Coding助手 REVIEW 第 2 节第 6 条已要求同格式） |
| E2E 唯一、产物可复跑 | Evidence 的证明标准（走真实用户路径、看副作用、dry-run 要核实它到底跳过了什么）+「执行过的才算交付」 | **合并**：它比我们的规矩更细，Evidence 节照它写；不写单测这条保留我们的 |
| 演练里的反例（F-* 用例） | formal 的「能失败」+ create 第 4 节「先跑一遍再交付」 | **保留我们的**：读回 30 个用例正是这个思路；模板里把「每个检查必须在改坏的变体上失败过」写成必做项 |
| SYSTEM_MAP / `--check` 漂移 | formal 的「跟着代码走」、maintain 的 index hygiene 和 source wave | **合并**：SYSTEM_MAP = ops 自己的 feature map；`ops verify` = ops 的 Doctor + Drive（只读）；`--check` 等于常驻的第 1 步 index hygiene |
| 园丁（以后做，花费要上卡） | maintain-verification-skill 整套（每个功能一个只读子 agent + 一次 live 全覆盖 + 最多 1 个 PR，结果分 clean / changed / blocked） | **用它替换**我们自己的园丁设计。保留 poteto-REVIEW 里三条防互踩的规则：固定命名、推完才结束、不和夜审同一晚跑 |
| 形式验证 | create-formal-verification-skill | **缺口，正在补**：叫醒系统 TLA+ 试用在跑（ops-PER-67-wake-tla）；候选目标还有卡住检查的自告警和夜审的写入→读回 |
| 五级阶梯 / `/pstack:correct` | 三个 skill 都只管验证，不管下沉 | **保留我们的**：verify skill 是 L4，它附带的 CLI 和挂在门上的检查才是 L2 |
| 合并/验收脚本 | 没有对应 | **保留我们的**；它调用 verify CLI，并核对产物 sha |
| bootstrap 装 CE+pstack | 没有对应 | **保留我们的**，锁到 0148b78（0.15.27） |

## 2. 要先定的冲突
1. **路径**：skill 写的是 `.cursor/skills/verify-<app>/`。Claude Code 的对应路径是 `.claude/skills/`（见 adapter 文档的 Paths 表）；pi 读 `.pi/skills/`、`.agents/skills/`、`~/.pi/agent/skills/`，不读 `.claude/skills/`。
   建议：放 `.claude/skills/verify-<app>/`，另建 `.agents/skills/verify-<app>` 软链指过去，两边都能用。vllm fork 的 `.claude/skills/` 是上游的，verify-vllm 不能进上游 PR，只能放 fork 的 ops 分支，或者放 ops 仓库。
2. **只能手动调用**：三个 skill 都标了 `disable-model-invocation`，模型自己调不了。派活模板必须让首句就写 `/pstack:create-verification-skill …`（wake-tla 已这样做）；pi 没有 pstack，这类活只派 Claude Code。
3. **「先修好 build」和「临时故意改坏真实代码」**：skill 要求起不来就先修，formal/create 还会在真实代码上做临时改坏再撤回。我们的规矩是不改产品代码、不动生产。
   做法：只在 Orca 工作区的分支上做；起不来时只报告，不修产品代码，修复另开 issue；改坏的变体只放在 spec 或草稿副本里，或者在工作区里改完跑完立刻 `git restore`，并附 diff 证据；绝不碰共享 testing 或生产。
4. **maintain 会开 PR**：PR 只能是 draft，合 main 照旧要 Zack 卡片。它的 live pass 不能驱动共享 testing 或生产，只驱动自己起的实例。
5. **feature map 和现有文档重复**：官网、心月的 `docs/solutions/` 是教训，不是功能地图，不算重复。但 AGENTS.md 里关于验证的句子要挪进 skill，AGENTS 只留一句指过去，否则两处会各说各的。
6. **能不能下沉到 L2**：可以。verify skill 附带的 CLI 就是 L2 的门：pre-push 跑改动涉及的功能（官网连续 3 晚都犯了推前不测），合并/验收脚本拒绝没有产物、sha 对不上或 0 用例的 PR。skill 文本本身是 L4，只说明怎么用这个门。
7. **广告产品已全停**：模板推广不包括广告，vllm 的 verify 是 E2E 入口脚本，不是浏览器 CLI。

## 3. 改过的第 4 步
| # | 做什么 | 谁做 | 验收 | 要 Zack 卡片 |
|---|---|---|---|---|
| 1 | ✅ 夜审读回 #30 已合、已部署（10-19 10:44），PER-65/66 已合 | — | 今晚 00:04 后看 readback 结果 | — |
| 2 | FDV-92 样板：在 deepvision-site 跑 `/pstack:create-verification-skill` 生成 `.claude/skills/verify-dv-site/`（含 features/、CLI Helper、pre-push）+ `.agents` 软链 | Coding助手 派官网 bot → Orca（Claude Code） | 生成后的 skill 在全新工作区按自己的步骤跑通 1 个功能；0 用例时退出码非 0；产物 sha = head；cleanup 后产物还在；故意改坏一处能看到失败 | 合 main |
| 3 | 合并/验收脚本：调 verify CLI、比对 Linear 和 gh、查产物 sha、查「待定」有没有 `[Zack答]` | Coding助手 → Orca（ops 仓库） | 用夹具证明 4 种拒绝各发生一次；真实 PR 跑通一次 | 合 ops main |
| 4 | 抽成模板 → 心月 → vllm（E2E 入口脚本，verify skill 放 fork 的 ops 分支或 ops 仓库）；**广告不做，标「产品暂停」** | 各项目 bot → Orca | 每个仓库同第 2 行的验收 | 每个仓库一张合 main 卡 |
| 5 | SYSTEM_MAP 改成 feature map 格式（#28 rebase），`ops verify` 等于它的 Doctor + Drive，只读 | dr eggbot 定格式，Coding助手 改 #28 | `ops verify` 0 条通过时判失败；不发测试 wake | 合 ops main |
| 6 | 形式验证：先看 wake-tla 的结果，再挑卡住检查自告警、夜审写入→读回 | dr eggbot 派 Orca | 每条性质要么在界限内 proven，要么给出能映射到代码行的反例；改坏变体失败过 | 要修代码时合 main |
| 7 | 园丁 = `/pstack:maintain-verification-skill`：先在 deepvision-site 试 2 周，每周 1 次，只开 draft PR | Coding助手 | 每次结果是 clean / changed / blocked 之一，并有覆盖率 | **花费卡**（Claude 额度、每次时长） |
| 8 | bootstrap 装 CE+pstack，锁 0148b78，`--check` 报版本漂移；iMac、MBA 从 0.15.26 升上来 | Coding助手（第 2 步） | 三台机器 `claude plugin list` 版本一致，`--check` 退出码 0 | 合 ops main |

检查上线后从规矩里删掉的句子（同一轮改，由 dr eggbot 改 dev-bot-rules，现在 140 行）：
- 第 3 行合并脚本上线 → 删「合并前核对 Linear/PR/验收记录」类句子（「## Linear」一节只留状态定义）。
- 第 2、4 行 verify skill 和 pre-push 上线 → 删各项目 AGENTS 里关于「推前跑哪些测试、怎么写 E2E 报告」的句子，换成一句「验证用 verify-<app> skill」。
- 第 5 行 `ops verify` 上线 → 删 dev-bot-rules 里人工核对叫醒链路、心跳的句子。
- 第 8 行 `--check` 上线 → 删「派活要带 --repo id: / --no-parent / notify-run」这类句子（`orca-agent-launch` 已经拦截）。
- 指标照 REVIEW-coding：已有检查的规则句数应为 0，每月统计下沉了几条。

## 4. 请 Zack 定（已定，见顶部状态）
1. ✅ 已定：用 pstack 的 verify-<app> skill + features/（4 个 H2）作为全部项目的 Feature Map 和驱动 CLI 标准格式（替换我们还没写的格式），路径定为 `.claude/skills/` 加 `.agents/skills` 软链。
2. ✅ 已定（花费卡另批，未批）：园丁就用 `/pstack:maintain-verification-skill`：先在官网试 2 周、每周 1 次、只开 draft PR，花费另上卡。
3. ✅ 已定：允许 Orca 分支工作区改坏再撤回附 diff；「起不来先修」改为只报告。原问题：允许 verify 或 formal skill 在 Orca 分支工作区里临时改坏代码再立即撤回（附 diff 证据），还是只允许在 spec 或草稿副本里改坏？
4. ✅ 已定：跳过广告，心月 → vllm；vllm verify skill 不进上游 PR，落点（fork ops 分支 / ops 仓库）第④步再定。原问题：模板推广确认跳过广告，顺序定为心月 → vllm；vllm 的 verify skill 放 fork 的 ops 分支还是 ops 仓库？
5. ✅ 已定：锁 0148b78。原问题：pstack 锁 0148b78（0.15.27），还是 6b78e9f（main，多了 TLA+ 默认和无验证器时的兜底）。
