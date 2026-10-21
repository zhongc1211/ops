# PER-126 v5 前提 2：被动采样器测试记录（2026-10-21）

代码在 `dispatch/`，说明见 `dispatch/README.md`。本目录是这次的测试产物。线上没有安装任何东西（见下面「线上核对」）。

## 1. 桩测

- 命令：`dispatch/tests/sampler-stub.sh`
- 环境：iMac（macOS 26.6.2，/bin/bash 3.2.57，/usr/bin/python3 3.9.6），全部在 `mktemp -d` 临时目录，`HOME` 指向临时目录，假的 orca/ps/sysctl/df/launchctl 放在 PATH 最前。
- 结果：通过 78，失败 0。完整输出：`stub-test-output.txt`。
- 覆盖：正常采样（含 `env -i` 空环境、正文不落盘断言）、Orca 不在/超时（含子进程被杀）/坏 JSON/`ok:false`/退出码非 0、补充查询失败、整轮超时、配置缺失/版本错/数值坏、锁被占、同一分钟重复、按天轮转、总大小上限（含当天文件超上限停写）、日志上限、会话找不到进程、后备工具失败、回放门槛 1（连续 61 分钟不可起 + 缺数据分钟）、回放门槛 2（放行后跌破 X）、install.sh 的 `--check`/`--dry-run`/`--install`（临时 HOME，不调 launchctl）。用例和 `dispatch/tests/FAILURE-MODES.md` 编号对应。
- 这是桩测，不是 E2E。

## 2. 真机只读运行（临时目录）

- iMac：`dispatch/bin/ops-v5-sampler --once --state-dir <scratchpad>/state --config <scratchpad>/sampler.env`，2026-10-21 11:50–12:00 每分钟一次，共 10 次。Orca 1.4.224。
- MBA：同一脚本经 `ssh mba '/usr/bin/python3 -I - --once ...' < dispatch/bin/ops-v5-sampler` 从 stdin 跑，数据写 MBA 的 `mktemp -d /tmp/ops-v5-sampler-test.XXXXXX`，跑完 scp 回来后删掉该临时目录（已确认 `/tmp/ops-v5-sampler-test.*` 不存在）。Orca 1.4.229。
- 两台 10/10 次 `orca_ok=true`、`errors=[]`。iMac 22 个会话、MBA 23 个会话，全部对上终端 handle 和进程。
- 样例（截短，只留 2 个会话）：`sample-imac-truncated.json`、`sample-mba-truncated.json`。日志：`sampler-log-imac.txt`、`sampler-log-mba.txt`。

开销（`/usr/bin/time -l`，`time-imac.txt`、`time-mba.txt`）：

| | 每次耗时 | 采样器自身 rss | 最大子进程 rss（orca CLI） | CPU（自身+子进程） |
|---|---|---|---|---|
| iMac | 0.75–1.02 秒 | 约 20MB | 约 93MB | 约 0.65 秒 |
| MBA | 0.97–2.13 秒 | 约 20MB | 约 91MB | 0.65–1.2 秒 |

每分钟一次，平均约占一个核的 1–2%。子进程 rss 主要是 orca CLI，一轮调 3 次（diagnostics memory、terminal list、worktree ps），依次跑，同一时刻最多一个。

数据量：一行约 15KB（22–23 个会话），每台每天约 22MB。24 小时采样用不到上限；按默认 200MB 上限，14 天保留实际约 9 天就会触发按大小删旧。

## 3. 回放样例（10 分钟数据，只为演示输出格式）

- 命令：`dispatch/bin/ops-v5-sample-replay --dir <imac samples> --dir <mba samples> --json replay-10min.json`
- 摘要：`replay-summary-10min.txt`；完整 JSON：`replay-10min.json`。
- 每台「缺数据 1 分钟」是测试循环造成的：每轮 `sleep 60` 加采样耗时约 62 秒，11 分钟跨度里漏了一个分钟号。LaunchAgent 按 `StartInterval 60` 拉起不会这样累积漂移。
- 10 分钟数据定不了阈值，建议初值要等 24 小时数据再算。

## 4. 线上核对（只读）

- `install-check-imac-live.txt`：iMac 真实 HOME 下 `dispatch/install.sh --check`，全部报「缺失 / 未加载 / 无数据」，退出 1。
- `install-dryrun-imac-live.txt`：同一台 `--dry-run` 的输出，即安装会新建的路径和会执行的 `launchctl bootstrap`。
- MBA：`launchctl print gui/501/com.zhongc1211.ops-v5-sampler` 返回 113（未加载）；`~/.config/dispatch`、`~/.local/state/dispatch` 不存在。

## 5. lint

`wake/tests/lint-bash32-utf8.sh dispatch` → `lint-bash32-utf8: ok`（`lint-bash32.txt`）。`shellcheck -S warning dispatch/install.sh` 无输出。测试脚本里 shellcheck 报的 SC2034/SC2120 是 `eval` 断言引用变量造成的误报。
