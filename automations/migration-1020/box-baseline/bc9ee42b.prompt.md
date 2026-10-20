Linear sync（v2，2026-10-18 Zack 批）：把 Linear team personal（PER）和 FDV 所有非 Canceled 的 issue 状态，按下面的状态定义和证据对齐。不碰任何项目代码、分支、部署和生产；GitHub 只读（gh pr list/view），不在 GitHub 发言。不打印、不写入任何 token/key/webhook 内容。同一操作最多重试 2 次。

## 状态定义（dev-bot-rules，Zack 10-18 01:35）
- In Progress：已开工，还没做完 testing 验收。
- In Review：testing 上验收步骤全做完，只等合并（应有 PR 链接）。
- 卡住、要审批或等点头：保持 In Progress，加「等 Zack」标签或评论（dev-bot-rules 第 41 行）。PER、FDV 都没有 Blocked 状态，不改也不建议改成 Blocked。
- Done：合进 main 或上生产、验收通过、外部依赖（如 key）到位，三条都满足。只进 staging / testing 不算 Done。

## 范围和证据
- 列 issue：`orca-ide --environment iMac linear list-issues --team PER --json` 和 `--team FDV`（不带 --limit，拿全部），跳过 Canceled。
- 每条看：GitHub PR/分支状态（合进了哪个分支：main 还是 staging/testing）、Linear 评论（`linear issue <ID> --comments --json`，所有 issue 并行取，如 `xargs -P6`，每条存一个文件；返回按新→旧排；最新一条按 createdAt 取最大值，换成 SGT 再写）、对应项目的 status.md。
- 项目 → 仓库：
  - PER / 心月网站 → zhongc1211/xinyue-site（box /workspace/repos/xinyue-site，主分支 feat/xinyue-site）
  - PER / vllm-omni → fork zhongc1211/vllm-omni，上游 PR 在 vllm-project/vllm-omni（box /workspace/repos/vllm-omni）
  - FDV / 网站改版、迁移与运维、杂项 → zhongc1211/deepvision-site（box /workspace/repos/deepvision-site，main）
  - FDV / deepvision 广告产品 → box /workspace/repos/deepvision-ads（status.md 在仓库根目录）
  - FDV / 客户看板 → 无仓库
- status.md：先找 box 仓库里的；找不到就以 PR 和 Linear 评论为准。

## 怎么改
- Linear 读写一律用 `orca-ide --environment iMac linear ...`；iMac 不在线（命令连不上）时改用 box 的 `orca linear ...`。
- 证据清楚的直接改：`linear status set <ID> --to "<新状态>"`，紧接着 `linear comment add <ID> --body "Linear sync：<旧>→<新>｜<依据>｜<链接>"`。包括把不满足新 Done 定义的 Done 重开为 In Progress（例如只合进 staging、生产没验收、key 没到位）。
- 带「等 Zack」标签的 issue：不改状态、不加评论，只在本次记录里记一笔。
- 拿不准的不改，叫醒负责的项目 bot 核实（每个 bot 每次运行最多叫一次，把它负责的待核实 issue 合并到一条里）：
  `notify-run --bot <bot> --task "Linear sync 待核实：<ID> <当前状态>，<疑点>；请按新状态定义核实并更新 Linear" --issue <ID> -- true`
  归属：deepvision-site → deepvision-ops；deepvision 广告产品 → deepvision-ads；心月网站 → xinyue；vllm-omni → vllm-omni。归不到这四个的（如客户看板、ops）不叫醒，记下来。
  webhook 配置在 ~/.config/grokbot/webhooks/*.env，只能经 notify-run 使用，不 cat、不打印。

## 记录
- 每次运行（没改动也要）在绝对路径 /workspace/ops/reports/linear-sync/changes.log 追加一行（不是当前仓库下的 reports/），目录不在就建：
  `<YYYY-MM-DD HH:MM SGT>｜改了 N 条：<ID 旧→新, ...>｜叫醒：<bot(ID,...)> 或 无｜等Zack 未动：<ID,...> 或 无`
- 评论没读到的 issue 每条再追加一行，不许跳过：`<YYYY-MM-DD HH:MM SGT>｜未核实：<ID>｜<原因>`。
- 时间用 `TZ=Asia/Singapore date '+%Y-%m-%d %H:%M'`。
- 最后一条消息写：结论 + changes.log 那一行。