# 叫醒链路（notify-run）

派活的 bot 用 `notify-run --bot <bot> --task "<描述>" -- <命令>` 起一个命令；命令结束（成功、失败、被 kill）后，notify-run 向 `<bot>` 的 webhook POST 一条结果，并把命令的退出码原样传出。webhook 回非 2xx 时按 `NOTIFY_RUN_TRIES` 重试，不记成已发送。

## Sub-features

- `WC1` 成功：`true` → 退出码 0，恰好 1 条 `status=done exit_code=0`，notify-run.log 记 `http=200 try=1`。
- `WC2` 失败：`sh -c 'echo …; exit 7'` → 退出码 7，恰好 1 条 `status=failed exit_code=7`，`log_tail` 带命令输出；`false` → 退出码 1。
- `WC3` 被杀：`sleep 30` 期间给 notify-run 发 TERM → 退出码 143，恰好 1 条 `status=killed exit_code=143`。
- `WC4` 非 2xx：端点回 503，`NOTIFY_RUN_TRIES=2` → 端点收到 2 次，log 两行 `http=503`，没有任何一行记成 2xx；两次之间约 20 秒；发送失败不改变命令退出码。

## How to get to it (user POV)

- agent 的 Bash 工具里包长命令：`notify-run --bot <bot> --task "<编号> <简述>" -- <命令>`（stdout 不是终端 → 管道模式）。
- 包整个 agent：`notify-run --bot <bot> --task "..." --tty -- claude ...`（由 orca-agent-launch 走，见 [agent-launch-gate.md](agent-launch-gate.md)）。

## Driving it with verify.sh

Preconditions: 沙箱里 `verify-bot.env` 指向假端点 A（回 200），`verify-down.env` 指向假端点 B，且 `$SB/mock/b.jsonl.fail-verify-down` 存在（B 对这个路径回 503）。

- 跑：`bash .claude/skills/verify-ops/verify.sh run wake-chain`（约 25 秒，大半是 WC4 的 20 秒重试间隔）。
- 每个子用例都用 `--no-tty` 调被测目录的 `wake/bin/notify-run`，`task` 用 `wc-done` / `wc-failed` / `wc-false` / `wc-killed` / `wc-503` 区分。
- 结果：`vo.py count "$SB/mock/a.jsonl" task=wc-done bot=verify-bot status=done exit_code=0 source=notify-run auth_ok=true` 为 1，且同 task 的总数也是 1（恰好 1 条）。
- WC4：`vo.py count "$SB/mock/b.jsonl" task=wc-503 answered=503` 为 2；`$HOME/.orca-state/notify-run/notify-run.log`（沙箱）里 `bot=verify-down` 的行都是 `http=503`。
- 改坏验证：副本里把 `send_webhook` 的 `case "$http" in 2??) exit 0 ;; esac` 改成 `*)`，`VERIFY_OPS_SUT=<副本> … run wake-chain` 必须 FAIL（「假端点回 503 时不应记成已发送」那条断言：只收到 1 次）。

## Gotchas

- brief 写的是假端点回 500；复用的现成替身里，`automations/migration-1020/e2e/mock_webhook.py` 只会回 200，`wake/tests/mock_webhook.py` 的失败码是 503，所以非 2xx 用例测的是 503。notify-run 对任何非 2xx 一视同仁（`case "$http" in 2??)`），结论相同。
- 「不记成已发送」在 notify-run 里的可观察结果是：继续重试到 `NOTIFY_RUN_TRIES` 次。notify-run.log 每次都记真实的 http 码，所以光看 log 的 http 字段抓不到「把 503 当成功」的改坏，必须同时数端点收到的次数。
- 默认 `NOTIFY_RUN_TRIES=3` 时重试要睡 20 + 45 秒；verify 用 2 次把时长压到 20 秒。
- payload 里的 `machine` 是本机主机名，原文进了运行目录的 `webhook/requests-*.jsonl`；对外只贴计数和 sha。
- 被 TERM 的用例里，notify-run 只把信号转给直接子进程；包 `sh -c 'sleep …'` 时孙进程会留下，所以这里直接包 `sleep`。
