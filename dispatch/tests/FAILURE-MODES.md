# ops-v5-sampler 失败方式清单（先写清单，再写代码）

每条后面是桩测里对应的用例名（`dispatch/tests/sampler-stub.sh`）。

## 采样器 ops-v5-sampler

| # | 失败方式 | 期望行为 | 用例 |
|---|---|---|---|
| F1 | 配置文件不存在 | 退出码 3，日志写「配置缺失」，不写 samples | config_missing |
| F2 | 配置里 `SAMPLER_CONFIG_VERSION` 缺失或不是 1 | 退出码 3，日志写版本错误，不写 samples | config_bad_version |
| F3 | 配置里数值项不是数字 | 退出码 3，日志写哪一项 | config_bad_value |
| F4 | 另一个实例正在跑（锁被占） | 立即退出码 0，日志写「锁被占，跳过」，不写 samples | lock_held |
| F5 | 同一分钟已经有记录 | 退出码 0，不追加第二行 | same_minute |
| F6 | `orca` 不在 PATH | `orca_ok=false`，`errors` 含 `orca_diag`，仍写机器级后备读数 | orca_missing |
| F7 | `orca` 挂住超过 10 秒 | 10 秒内被杀（连同子进程组），`orca_ok=false`，不留子进程 | orca_timeout |
| F8 | `orca` 输出不是 JSON / JSON 截断 | `orca_ok=false`，错误写 `bad_json` | orca_bad_json |
| F9 | `orca` 返回 `ok:false` 或缺 `result.host` | `orca_ok=false` | orca_not_ok |
| F10 | `orca worktree ps` / `terminal list` 失败 | 会话照记，`terminal=null`，`errors` 记下，`orca_ok` 仍为 true | orca_enrich_fail |
| F11 | 会话 pid 在 ps 里找不到 | 该会话 `proc.found=false`，其他会话照常 | session_no_proc |
| F12 | `ps`/`sysctl`/`df` 失败或输出怪 | 对应字段为 null，`errors` 记下，不崩 | fallback_tools_fail |
| F13 | 整轮超过 30 秒 | 写已采到的部分并标 `round_timeout`，进程退出 | （由 F7 的单步限时间接保证，另有 ROUND_TIMEOUT 覆盖用例 round_timeout） |
| F14 | 当天文件之外的旧文件超过保留天数 | 删掉超期的 `YYYY-MM-DD.jsonl`，不碰别的文件名 | rotate_old |
| F15 | 自己目录 `*.jsonl` 总大小超上限 | 从最旧开始删，不删当天文件；当天文件单独超上限就停止追加并记日志 | size_cap |
| F16 | 别的主机目录、非 `*.jsonl` 文件 | 永远不删 | rotate_old / size_cap 里一并断言 |
| F17 | 自身日志无限增长 | 超过 `LOG_MAX_KB` 时轮转为 `.log.1`，最多两份 | log_cap |
| F18 | 会话正文（prompt、preview、lastAssistantMessage）被写进 samples | 只存白名单字段；断言输出里没有桩里埋的正文标记 | normal（断言） |
| F19 | launchd 的极简 PATH 找不到 orca | 脚本自己补 PATH（含 Orca.app 的 bin） | normal（用 `env -i` 跑） |
| F20 | 写盘失败（目录不可写） | 退出码非 0，日志写原因，不影响别的进程 | （手工：不单测） |

## 回放 ops-v5-sample-replay

| # | 失败方式 | 期望行为 | 用例 |
|---|---|---|---|
| R1 | 坏行 / 空行 / schema 不认识 | 跳过并计数 `bad_lines` | replay_gate1 |
| R2 | 缺数据的分钟 | 单列 `unknown_minutes`，不算「起不了」，并打断连续段 | replay_gate1 |
| R3 | 连续 61 分钟不可起 | 门槛 1 报出该窗口，`max_blocked_min=61` | replay_gate1 |
| R4 | 放行后 30 分钟内 free% 跌破 X | 门槛 2 报违规次数和最低 free% | replay_gate2 |
| R5 | ssh 拉取失败 | 报错退出码非 0，说明是哪台 | （手工） |
