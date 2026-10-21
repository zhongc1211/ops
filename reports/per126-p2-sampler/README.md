# PER-126 v5 前提 2：被动采样器测试记录（2026-10-21，第二轮）

代码在 `dispatch/`，说明见 `dispatch/README.md`。本目录是第二轮的测试产物，第一轮（cbccc9d）的样例、日志、耗时文件已删掉，避免和新路径、新格式混在一起。线上没有安装任何东西：两台真实 HOME 下没写 `~/.local/bin/ops-v5-*`、`~/.config/dispatch/`、`~/.local/state/ops-v5/`、`~/Library/LaunchAgents/com.zhongc1211.ops-v5-*`，没调 launchctl，没跑 backup.sh、`install.sh --install`/`--uninstall`。

## 1. 真机 E2E：每分钟一次，各 10 分钟

- 命令（仓库根目录，两条同时跑）：
  - iMac 本地：`dispatch/tests/e2e-real-10min.sh --host imac`
  - MBA：`dispatch/tests/e2e-real-10min.sh --ssh mba`（采样器经 ssh 从 stdin 传过去：`/usr/bin/python3 -I - --once ...`）
- 环境：iMac（macOS 26.6.2，Orca 1.4.224）、MBA（macOS 26.6.2，Orca 1.4.229），都是 `/usr/bin/python3` 3.9.6。
  每台在 `mktemp -d` 里放临时 HOME、数据目录和配置，`env -i` 只带 `HOME=<临时>`、`PATH=/usr/bin:/bin`、`ORCA_USER_DATA_PATH=<真实 HOME>/Library/Application Support/orca`（orca CLI 靠这个路径找到本机 Orca，脚本不读里面的文件）。
- commit、起止时间、临时目录：`e2e-<host>/env.txt`（`uncommitted_in_dispatch 0` 表示跑的就是该 commit 的代码）。
- 结果：`e2e-<host>/summary.txt`。最后一次运行的结论写在 `.orca-task/RESULT.md`。
- 完整数据：`e2e-<host>/state/samples/<host>/2026-10-21.jsonl`（10 行）和 `2026-10-21.sessions.jsonl`（会话字典），还有采样器日志和状态文件。
- 每次的 `/usr/bin/time -l`：`e2e-<host>/time/NN.txt`；每次的退出码：`runs.txt`。
- 正文和密钥扫描：`summary.txt` 末尾的 `scan_hits`。扫的是正文字段名（prompt、preview、lastAssistantMessage、message、content、env、argv、command 等）、密钥样式（sk-、ghp_、xox*-、AKIA、Bearer、PEM 头）和 password/secret/token/cookie/api_key 等词。
  另外人工核对过字段：每分钟记录只有数值和状态；字典只有 paneKey、sessionId、worktreeId、worktreeName（任务标题）、repoName、handle、agentType、workingMode、linkedLinearIssue。
- 真实 HOME：`real-home-before.txt`、`real-home-after.txt`，5 个路径跑前跑后都不存在。
- 临时目录：`cleanup.txt`，两台都写「临时目录已删」，MBA 的也删了。

## 2. 回放（用上面的 10 分钟数据）

- 命令：`dispatch/bin/ops-v5-sample-replay --dir e2e-imac/state/samples --dir e2e-mba/state/samples --json replay-10min.json`
- 摘要：`replay-summary-10min.txt`。完整 JSON：`replay-10min.json`，含按 agent 类型的 tree_rss p90/p99（`reserve_hint_gb_by_agent`）。
- 10 分钟数据定不了阈值，只用来确认回放能读新格式。建议初值要等 24 小时数据。

## 3. 桩测

- 命令：`dispatch/tests/sampler-stub.sh`。环境：iMac，/bin/bash 3.2.57，临时目录和临时 HOME；假的 orca、ps、sysctl、df、launchctl 放在 PATH 最前，假的 backup.sh 放在临时 HOME 的归档目录。
- 输出：`stub-test-output.txt`，第一行是 commit。用例和 `dispatch/tests/FAILURE-MODES.md` 编号对应。这是桩测，不是 E2E。

## 4. lint 和 shellcheck

`lint-shellcheck.txt`：`wake/tests/lint-bash32-utf8.sh dispatch` 和 `shellcheck -S warning dispatch/install.sh dispatch/tests/*.sh dispatch/tests/stubs/*` 的输出和退出码。

## 5. 线上只读核对（iMac 真实 HOME）

- `install-check-imac-live.txt`：`dispatch/install.sh --check`，全部报缺失、未加载、无数据，退出 1。
- `install-dryrun-imac-live.txt`：`dispatch/install.sh --dry-run`，即安装会先跑的 backup.sh、会新建的路径和会执行的 `launchctl bootstrap`。
- 这两次把 launchctl 换成了 `dispatch/tests/stubs/launchctl`（`print` 一律答「未加载」），因为这轮不允许调 launchctl。所以「未加载」那一行不是真机读数，其余各行是真实 HOME 下的读数。
- MBA 没跑 `install.sh`（要仓库目录）。真实 HOME 下 5 个路径不存在，见 `e2e-mba/real-home-*.txt`。

## 6. 回退测试（第一轮代码 + 本轮桩测）

- `rollback-test-cbccc9d.txt`：用临时副本（不改分支）把 `dispatch/bin/ops-v5-sampler` 和 `dispatch/install.sh` 换回 cbccc9d 的版本，跑本轮 `dispatch/tests/sampler-stub.sh`。
- 结果：通过 66，失败 50。新用例 max_days、size_cap、log_cap、install、install_backup_fail、uninstall、install_not_macos 都挂，说明它们能抓到旧行为。normal 等几项是因为数据格式改了。文件开头有按用例的统计和原因。
