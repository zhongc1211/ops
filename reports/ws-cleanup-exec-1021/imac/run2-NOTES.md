# run2：第二次真 --execute（iMac，2026-10-21，SGT）

- 批准：Zack 卡片 10:53 SGT（PER-139 评论 931a2760），只删 3 个，不关终端。
- 脚本：HEAD a1cac54（脚本提交 5e19598），工作区开跑前 git 干净。
- 10:55–11:00 先跑新 dry-run（`run2-dryrun/`），参数 `--no-issue-reviews reports/no-issue-review`：BACKUP_RM 3 / SKIP 92 / LIST 1，退出码 0，stderr 为空；和 R5 run2-bash5.3 的 96 行除 idle_h 外逐行一样。
- `run2-only-from/worktrees.tsv` = R5 run2-bash5.3/worktrees.tsv 的表头 + 3 行 BACKUP_RM，sha256 前缀 07aa032bc7ac。
- 11:01 起跑 `--execute --only-from run2-only-from/worktrees.tsv --no-issue-reviews reports/no-issue-review --out run2`，没带 --close-terminals，没加 --force。
  - 发命令的 ssh 会话在 11:06 左右被中断，iMac 上的进程没受影响，继续跑完：11:07:19–11:07:24 逐个备份并 `orca worktree rm`，退出码 0。
  - 起跑后才收到评审意见（备份和 rm 之间不再复查）。这时已来不及在每个工作区动手前手动复查。事后核对：run2/worktrees.tsv 里这 3 行在动手前取到的状态，和 dry-run 除 idle_h 外完全一样（终端 0、未提交 0、HEAD 3a74c1c / 9d34311 / 2f7da6d 没变）；备份到 rm 的间隔不超过 1 秒。
- 结果：3 个都是「已备份；已 rm」，没做成的 0 个。Orca 工作区 95 → 92；xinyue-site 的 git worktree 18 → 15；表里总数（含 1 个 W16 只在 git 里的）96 → 93。
- 备份：`~/ops-archive/ws-cleanup/2026-10-21/xinyue-site/<名字>/`，每个只有 NO-ISSUE-REVIEW.md + MANIFEST.sha256（校验 OK），各 8 KB。
- 别的工作区：只有 PER-8-hunyuan-imac-omni 在 execute 里从 SKIP W10 变成 SKIP W9（gh 查询失败按 PR 开着处理），照旧没动。
