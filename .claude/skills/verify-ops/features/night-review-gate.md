# 夜审收尾门（night-review-gate.sh finish）

夜审的最后一步（由 `notify-run --bot ops-system` 包着）调 `night-review-gate.sh finish <项目> <日期> <机器> <原因>`：摘要里有「状态：完成」才把摘要、ledger 等文件拷到存储机，再从存储机读回确认，记 `state=done`，释放 heavy-lock；没有「状态：完成」就退出码 3、不拷、记 `state=failed detail=no_done_line`。

## Sub-features

- `NR1` 摘要有「状态：完成」→ 退出码 0；摘要和 ledger 出现在存储目录里，并且读回到「状态：完成」；状态文件最后一行 `state=done machine=mba reason=ok files=2`。
- `NR2` 摘要是「状态：进行中」→ 退出码 3；存储目录里没有这一晚的摘要；状态文件最后一行 `state=failed … detail=no_done_line`。
- `NR3` 两种情况下，finish 之前先用 `scripts/heavy-lock.sh acquire night-review-xinyue` 拿锁（像夜审 precheck 那样），断言锁被占着；finish 之后锁目录不在了。

## How to get to it (user POV)

- 夜审 prompt 的最后一步（`automations/migration-1020/prompts/*/night-review-*.prompt.md`）：`notify-run --bot ops-system --task "<项目> 夜审 $D" -- bash ~/orca/workspaces/ops/scripts/night-review-gate.sh finish <项目> "$D" <机器> "$(… reason …)"`。

## Driving it with verify.sh

Preconditions: 沙箱目录 `$SB/nr-dir` 放摘要（`<D>-xinyue.md`）和 ledger；`NR_STORE_HOST=local NR_STORE_DIR=$SB/nr-store` 让「存储机」是本地目录；`NR_STATE=$SB/nr-state`、`HEAVY_LOCK_DIR=$SB/heavy.lock`。

- 跑：`bash .claude/skills/verify-ops/verify.sh run night-review-gate`（1 秒）。
- NR1：`night-review-gate.sh finish xinyue 2026-10-28 mba ok`，摘要含 `状态：完成`。
- NR2：`night-review-gate.sh finish xinyue 2026-10-27 mba ok`，摘要含 `状态：进行中`。
- 改坏验证：副本里把 `finish)` 分支第一行的 `grep -Eq "$done_line" "$NRD/$summary"` 改成恒真，`VERIFY_OPS_SUT=<副本> … run night-review-gate` 必须 FAIL：NR2 应退出码 3，实际得到 4（不检查就去拷，拷进存储后读回找不到「状态：完成」，走「拷贝失败」分支），摘要也被拷进了存储。

## Gotchas

- brief 写的是「夜审写 EverOS 后读回，用本机假 EverOS 读回端点」。代码里 `night-review-gate.sh` 不碰 EverOS：`finish` 读回的是**存储机上的摘要**（`store_done`：本地 grep 或 ssh 到 box grep「状态：完成」）。EverOS 写入和 `everos_readback.py` 在夜审 prompt 里由模型执行，不在这个脚本里。所以这里的替身是存储机（`NR_STORE_HOST=local` + 沙箱目录，代替 ssh 到 box），没有假 EverOS 端点。
- `NR_STORE_HOST` 不设时默认 `box`，会真的 ssh；一定要设成 `local`。
- 「状态：完成」也接受半角冒号（`^状态(：|:)[[:space:]]*完成`），必须在行首。
- 没测：退出码 4（拷到存储机失败）这条路径 verify-ops 没驱动。造法：`NR_STORE_DIR` 指到一个普通文件下面（例如先 `touch $SB/somefile`，再设 `NR_STORE_DIR=$SB/somefile/x`），摘要含「状态：完成」时 finish 应退出码 4，状态文件最后一行 `state=failed … detail=rsync_failed`，heavy-lock 已释放。
- 脚本开头会 `export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH`；沙箱 HOME 下的 `.local/bin` 是 drift-checks 装进去的被测脚本副本，不影响这里（finish 只用 `scripts/heavy-lock.sh`）。
