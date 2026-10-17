# Orca automation「心月夜审兜底」（由心月网站运维 bot 用 Orca CLI 在 box 上建）

只读检查前一晚 23:30 的心月夜审（`75b324a4`）有没有正常收尾。检查逻辑都在 precheck 脚本里，脚本总是 exit 1，不启动模型。不用 cron。

## 参数

| 字段 | 值 |
|---|---|
| 名字 | 心月夜审兜底 |
| 主机 | box（与 `75b324a4` 相同：`executionTargetType=local`，`schedulerOwner=local_host_service`） |
| 项目 / 工作区 | ops，`workspaceMode=existing`，`/workspace/repos/ops`（与 `75b324a4` 相同） |
| agent | claude（不会启动；precheck 总是 exit 1） |
| 时区 | Asia/Singapore |
| 计划 | 每天 00:30 SGT，`rrule` = `30 0 * * *` |
| missedRunPolicy | `run_once_within_grace`，grace 600 分钟（脚本默认检查「12 小时前」那天，11:59 前补跑仍查前一晚） |
| precheck | `bash /workspace/ops/everos-ingest/night-review-guard-xinyue.sh` |
| prompt | `precheck 已处理，无需操作。` |
| extraAgentArgs | 留空 |
| reuseSession | false |

## 脚本行为（`everos-ingest/night-review-guard-xinyue.sh`）

- `D` 默认是 SGT「现在减 12 小时」的日期，00:30 运行时就是前一天。可用环境变量 `D=YYYY-MM-DD` 覆盖。
- 检查：
  1. `~/xinyue-deploy/nightly-review/$D-xinyue.md` 存在，且有一行 `状态：完成`（全角或半角冒号都认）。
  2. `~/xinyue-deploy/nightly-review/$D-xinyue-ledger.jsonl` 里同一次写入运行（同一个 `run`）有 `count_before` 和 `count_after`，http 都是 200，且不是 dry-run。
- 都满足：打印一行，exit 1，不发任何东西。
- 任一不满足：向 `~/.config/grokbot/webhooks/coding-assistant.env` 的 URL POST 一次
  `{"bot":"coding-assistant","task":"心月夜审兜底 $D","worktree":"/workspace/repos/ops","status":"stuck","note":"<一句话>"}`，然后 exit 1。
  note 示例：`心月夜审 2026-10-16 没有正常收尾：摘要状态=进行中（当前步骤：第 3 步 对照 PR/Linear）；台账缺写后计数`。
- 不写任何文件。webhook env 文件不存在或发送失败时只打印到 stderr，仍然 exit 1。
- 试运行：`DRY_RUN=1 D=2026-10-16 bash /workspace/ops/everos-ingest/night-review-guard-xinyue.sh`，只打印将要发送的内容，不 POST。

## 注意

- 手动 `orca automations run` 不会执行 precheck（见 `everos-ingest/README.md`），要验证只能等定时运行，或在 box 上直接跑脚本。
- 夜审 23:30 如果晚开（run 4 晚了 12 分钟）而且到 00:30 还在跑，兜底会按「进行中」报 stuck，note 里带当前步骤。
