# 起 agent 的门（orca-agent-launch）

派活时用 `orca-agent-launch --bot <bot> --task "<描述>" [--issue X --eta <日期>] -- <claude|pi|codex> …` 起 agent。参数不合规矩就拒绝（什么都不起），同时把拒绝原因叫醒一次；合法时 `exec notify-run --tty`，agent 退出后叫醒派活的 bot 一次。

## Sub-features

- `AL1` 没带 `--bot` / 没带 `--task` → 退出码 2。
- `AL2` bot 没有 webhook 配置 → 退出码 2，拒绝原因改发 coding-assistant。
- `AL3` 经 `bash -c` / `env` / `nohup` 转一层 → 退出码 2。
- `AL4` 带 `--issue` 没带 `--eta` → 退出码 2（代码如此，见 Gotchas）。
- `AL5` 带 `--issue --eta`，Linear 写不进去 → 退出码 3，不起 agent。
- `AL6` 每次拒绝都叫醒 1 次（`kind=agent_not_started source=orca-agent-launch`）。
- `AL7` 合法参数（无 issue）→ 进入 `notify-run --tty`，假 agent 退出码 0 传出，叫醒恰好 1 次（`source=notify-run status=done`，`log_tail` 是终端直通说明）。
- `AL8` 合法参数带 `--issue PER-9 --eta "2026-11-02 10:00"` → 先写 Linear（due=2026-11-02，描述补「负责 bot：verify-bot」），再起 agent，叫醒 1 次且带 `issue=PER-9`。
- `AL9` 启动前检查放行：工作区是空目录，走到检查的 3 次（AL5、AL7、AL8）标记句都在沙箱 `~/.pi/agent/AGENTS.md`。
- `AL10` 启动前检查拒绝：沙箱全局 AGENTS 没有标记句、或文件不存在 → 退出码 2，叫醒 1 次，没起 agent。

## How to get to it (user POV)

- Orca 终端的命令：`orca terminal create --worktree <wt> --command "orca-agent-launch --bot coding-assistant --task 'PER-65 xxx' -- claude …"`。
- 手动在终端里敲同一行。

## Driving it with verify.sh

Preconditions: 沙箱 PATH 里的 `pi` 是假 agent（打印参数、退出 0）；沙箱 `~/.pi/agent/AGENTS.md` 是被测仓库 `AGENTS.md` 的拷贝；`ORCA_AGENT_LAUNCH_NOTIFY_RUN` 指向被测目录的 notify-run；沙箱 HOME 有 `verify-bot`、`coding-assistant` 的假 env，没有 `verify-nobody` 的。

- 跑：`bash .claude/skills/verify-ops/verify.sh run agent-launch-gate`（几秒）。
- 拒绝类：`rej <名字> <期望退出码> <参数…>`，比较前后 `kind=agent_not_started source=orca-agent-launch` 的条数，差值必须是 1。
- 所有用例都在空目录 `$SB/ws` 里起。
- AL5：`ORCA_AGENT_LAUNCH_ORCA=wake/tests/fake-orca/orca`（它对 `linear issue` 回空卡片 → 「Linear 里找不到 PER-1」），断言退出码 3 且没有 `task=gate-linear-fail source=notify-run` 的叫醒。
- AL8：`ORCA_AGENT_LAUNCH_ORCA=$SB/bin/fake-linear-ok`，调用记到 `$SB/linear.log`；断言里面有 `["linear","due-date","set","PER-9","--to","2026-11-02",…]` 和带「负责 bot：verify-bot」的 `save-issue`。

## Gotchas

- `orca-agent-launch` 的启动前检查看 `$HOME` 和 `$PWD` 两路。cwd 留在仓库里时，仓库的 `AGENTS.md` 有标记句，沙箱 HOME 没有也放行，「缺标记句 → 拒绝」测不到，从别的目录跑又全挂。所以用例在空目录里起，只靠沙箱 HOME。AL10 改完沙箱全局 AGENTS 要拷回去：后面的 feature 共用这个 HOME。
- 只有 `pi` 走了启动前检查；`claude`、`codex` 的指令链没驱动，见 `reports/93/rerun.sh` 的演练。
- brief 写「带 `--issue` 没带 `--eta` → 退出码 3」；代码（`wake/bin/orca-agent-launch` 里 `die "带 --issue 要同时带 --eta…"`）是退出码 2。只有 Linear 写不进去是 3。按代码断言。
- 不能用 `ORCA_AGENT_LAUNCH_DRY=1`：它不写 Linear、不叫醒、不 exec，测不到真实路径。
- 合法路径的假 agent 用 `pi`：notify-run 对 `claude` 会起「起没起来」检查（5 分钟后看 orca-wake 会话），verify 不想等；对 pi 不查。
- 环境里残留 `ORCA_DISPATCH_PID`（在 notify-run 里面跑 verify）会让合法路径被当成嵌套拒绝；verify.sh 开头会 unset。
- 合法路径真的会 `exec notify-run --tty`，stdout 不是终端也照样走 tty 模式，所以 `log_tail` 是「终端直通模式，未采集输出」。
