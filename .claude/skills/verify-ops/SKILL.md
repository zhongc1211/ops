---
name: verify-ops
description: ops 仓库叫醒链路和运维脚本的可复跑验证：在沙箱 HOME 里驱动真的 notify-run、orca-agent-launch、stuck-check.sh、heartbeat-watch.sh、各种 --check（wake/install.sh、sync-bot-rules、make-prompts.py、pin-claude-plugins.sh）和 night-review-gate.sh finish，只把 webhook 接收端、Orca CLI、Linear、agent-probe 进程表、夜审存储机换成本机替身。改了 wake/、scripts/、bootstrap/claude-plugins/、automations/migration-1020/ 里这些脚本，或者要给 ops 的 PR 出 E2E 证据时，agent 在 macOS 或 Linux 本机上跑一条命令，拿 summary.json 和 report.md。
---

# verify-ops

一条命令起沙箱、体检、驱动、留证据、清理：

```bash
bash .claude/skills/verify-ops/verify.sh doctor              # 只体检（起沙箱 → 只读检查 → 清掉沙箱）
bash .claude/skills/verify-ops/verify.sh run                 # 全部 feature
bash .claude/skills/verify-ops/verify.sh run wake-chain drift-checks   # 子集
bash .claude/skills/verify-ops/verify.sh list                # feature 名
```

退出码：0 全部通过，最后一行 `VERIFY-OPS PASS`；1 有失败（`VERIFY-OPS FAIL`）；2 体检不过或用法错；3 一个用例都没跑（`VERIFY-OPS EMPTY`：feature 名有一个写错就直接退出、不起沙箱；或选到的全是 skipped）。skipped 不算通过，汇报时逐条列出来。

功能地图在 `features/README.md`，每个 feature 一个文件。先读地图再改断言；地图写着的入口都要覆盖，只驱动一个方便的入口不算验证完。

## Launch

`verify.sh run` 和 `doctor` 自己调 `launch`，手动驱动时也可以单独起：

```bash
SB=$(bash .claude/skills/verify-ops/verify.sh launch | tail -1)   # 打印沙箱目录
. "$SB/env.sh"                                                      # 换成沙箱 HOME 和 PATH（只在子 shell 里做）
```

`launch` 做的事（全在 `mktemp -d "$TMPDIR/verify-ops.XXXXXX"` 里）：

- `$SB/home` 当 `HOME`；`$SB/home/.config/grokbot/webhooks/` 写 4 个假 env：`verify-bot`、`coding-assistant`、`ops-system` 指向假端点 A，`verify-down` 指向假端点 B。KEY 都是 `e2e-fake`（假端点 A 只认它，记 `auth_ok`），不是任何真实凭据。
- 假端点 A：`automations/migration-1020/e2e/mock_webhook.py`，自己挑空闲端口写进 `$SB/mock/a.port`，每个 POST 回 200，记一行到 `$SB/mock/a.jsonl`；`$SB/mock/a.stop` 出现就自己退出。
- 假端点 B：`wake/tests/mock_webhook.py`，端口由 `helpers/vo.py freeport` 挑；`$SB/mock/b.jsonl.fail-verify-down` 存在时对 `/hook/verify-down` 回 503。
- 两个假端点的 pid 写进 `$SB/pids`（每行 `pid 标签`），清理只认这个文件。
- `$SB/bin`（PATH 最前面）：假 agent `pi`、假 `orca` / `orca-ide`（`vo.py orca`）、成功路径的假 Linear `fake-linear-ok`、假 agent-probe `agent-probe.py`。PATH 第二位是被测目录的 `wake/bin`，第三位是 `wake/tests/fake-orca`，不含 `~/.local/bin`。
- `$SB/env.sh`：`HOME`、`PATH`、`NOTIFY_RUN_LOG`、`ORCA_WAKE_STATE_DIR`、`ORCA_WAKE_CONFIG_DIR` 都指进沙箱。

就绪的判据：`a.port` 非空、假端点 B 对一次 POST 有响应，然后 Doctor 全是 `ok`。两个沙箱可以并排跑（端口随机、目录各自独立）。

拆除：`bash .claude/skills/verify-ops/verify.sh cleanup "$SB"`（见 Cleanup）。

## Doctor

```bash
bash .claude/skills/verify-ops/verify.sh doctor          # 新起一个沙箱来查，查完清掉
bash .claude/skills/verify-ops/verify.sh doctor "$SB"    # 查一个已经 launch 的沙箱
```

只读，逐行打印 `ok` / `BAD` / `info`，有 `BAD` 退出 2，`run` 也就不驱动：

- `HOME` 是沙箱的 `home`，不是真 HOME。
- 两个假端点的端口由 `$SB/pids` 里对应的 pid 监听（`lsof -iTCP:<端口> -sTCP:LISTEN`）。
- `notify-run`、`orca-agent-launch`、`orca-wake` 在沙箱 PATH 里解析到被测目录的 `wake/bin/`，不是装在 `~/.local/bin` 的那份；`pi` 是假 agent。
- 被测代码是本次 checkout（打印短 sha 和 dirty），或 `VERIFY_OPS_SUT` 指的副本（这时会注明「不能当 PR 的证据」）。
- `info`：当前 bash 和 `/bin/bash` 的版本；有没有 Java + `tla2tools.jar`（没有时 wake-tla 记 skipped）。

## Drive

`verify.sh run [feature...]` 按顺序跑，每个 feature 在子 shell 里 `. "$SB/env.sh"` 后执行 `f_<feature>`（verify.sh 里同名函数），断言用 `expect <名字> <实际> <期望>`，结果写进运行目录的 `cases.tsv`。

| feature | 驱动的真实脚本 | 替身 | 文件 |
|---|---|---|---|
| `wake-chain` | `wake/bin/notify-run` 包 `true`、`exit 7`、`false`、被 TERM 的 `sleep`，以及对 503 端点的重试 | 假端点 A、B | `features/wake-chain.md` |
| `agent-launch-gate` | `wake/bin/orca-agent-launch` 的拒绝规则和合法路径（`exec notify-run --tty -- pi`） | 假 `pi`、假 Linear、`wake/tests/fake-orca/orca` | `features/agent-launch-gate.md` |
| `stuck-check` | `scripts/stuck-check.sh`（不带参数，直接发）两次，`scripts/heartbeat-watch.sh` 三次 | `wake/tests/fake_orca.py` + 生成的夹具、假 agent-probe、`wake/tests/hb-replay/orca`；`orca-wake` 用被测目录的真脚本 | `features/stuck-check.md` |
| `drift-checks` | `wake/install.sh --check`、`scripts/sync-bot-rules --check`、`make-prompts.py --check`、`pin-claude-plugins.sh --check`，各自先干净再造一处漂移 | 沙箱 HOME、沙箱里的仓库克隆、预写的 `installed_plugins.json` | `features/drift-checks.md` |
| `night-review-gate` | `scripts/night-review-gate.sh finish`（有 / 没有「状态：完成」） | `NR_STORE_HOST=local` + 沙箱目录代替存储机 | `features/night-review-gate.md` |
| `wake-tla` | 调现成的 `wake/tla/check.sh w0 h0`（`wake-tla-verify` skill 的命令，不复制） | 无 | `features/README.md` |

测一份故意改坏的副本（证明断言会挂）：

```bash
M=$(mktemp -d "$TMPDIR/ops-mutant.XXXXXX") && git archive HEAD | tar -x -C "$M"     # HEAD 的干净副本，在仓库外
sed -i.orig 's/case "$http" in 2??) exit 0/case "$http" in *) exit 0/' "$M/wake/bin/notify-run"   # 例：把任何 http 当成功
VERIFY_OPS_SUT="$M" bash .claude/skills/verify-ops/verify.sh run wake-chain   # 应 FAIL，退出码 1
rm -rf "$M"
```

`VERIFY_OPS_SUT` 只换被测脚本和替身脚本的来源；verify.sh、helpers 和运行目录仍用 checkout 里的。summary.json 的 `sut_kind` 会写「VERIFY_OPS_SUT 副本」。改坏永远在副本里做，不在 checkout 里做。

## Evidence

运行目录：`${VERIFY_OPS_ARCHIVE:-$HOME/ops-archive/verify-ops}/<UTC 时间，如 20261030T010154Z>/`，在仓库外，清理时不删：

- `summary.json`：`status`（PASS / FAIL / EMPTY）、`sha`（checkout 的 HEAD）、`dirty`、`sut_kind`、`machine`（macOS 版本 + CPU 架构，不写主机名）、`bash`、`cases_total` / `cases_pass` / `cases_fail` / `cases_skipped`、`features`（每个的命令、退出码、用例数）、`cases`（逐条）、`guard_before` / `guard_after` / `guard_ok`、`sandbox_removed`、`processes_left`、`skipped_by_policy`、`stand_ins`。
- `report.md`：同样的内容给人看。
- `doctor.txt`、`features/<feature>.log`（每个 feature 的原始输出，掩码后）、`webhook/requests-a.jsonl` / `requests-b.jsonl`（假端点收到的请求原文，掩码后）、`webhook/notify-run.log`（沙箱里的发送日志）。
- 掩码（`vo.py mask`，verify.sh 自动设好）：真实 HOME 换成 `~`，`VO_MASK_WORDS`（冒号分隔，默认本机 `hostname`、`hostname -s` 和用户名）里的词换成 `<host>`，IPv4 地址换成 `<ip>`。notify-run 的 payload 带 `machine`（主机名），掩码后是 `<host>`；对外仍只贴 sha 和计数。

证明标准：

- 走真实入口：被测脚本都是被测目录里的那份，按用户的命令行参数调用；不调内部函数，不用测试专用开关（`ORCA_AGENT_LAUNCH_DRY=1` 这类不用）。
- 记动作和结果：每条断言同时看退出码和副作用（假端点收到几条、哪个 bot、什么 status；notify-run.log 的 http 字段；状态文件；存储目录里的文件；假 Linear 的调用记录）。
- 替身只放在外部边界（列表写在 summary.json 的 `stand_ins`）：webhook 接收端、Orca CLI、Linear、agent-probe 的进程表、heartbeat 读的运行记录、夜审存储机、`claude plugin install` 写的已装清单、agent 本身。被测脚本一行不改。
- 真实 HOME 守卫：`run` 前后各算一次真实 `~/.config/grokbot/webhooks/` 里每个文件的 sha256 前 8 位和字节数（只算哈希，不读内容），以及真实 `notify-run.log` 的行数和 `bot=verify-` 开头的行数；webhook 有变化或出现 `bot=verify-` 行就判 FAIL。真实 notify-run.log 的总行数可能因为本机别的 agent 在跑而变化，不算失败。
- 用例为 0 时退出码 3，不能当通过。报告 PR 证据时 `sha` 必须等于 PR head，`dirty` 必须是 false。

## Cleanup

`run` 和 `doctor` 结束（包括出错、Ctrl-C）都会自动清理；手动 `launch` 的要自己清：

```bash
bash .claude/skills/verify-ops/verify.sh cleanup "$SB"
```

- 先建 `$SB/mock/a.stop` 让假端点 A 自己退出，再对 `$SB/pids` 里的每个 pid 发 TERM，半秒后还活着的发 KILL。不按进程名杀。
- 只删 `$TMPDIR/verify-ops.*` 形状的目录，别的路径拒绝。
- 不删运行目录。`run` 结束时在 summary.json 里记 `sandbox_removed` 和 `processes_left`（命令行里还带沙箱路径的进程数）。

## Helpers

- `verify.sh`：入口，用法见文件头和上面各节。兼容 macOS 自带的 `/bin/bash` 3.2。
- `helpers/vo.py`：verify.sh 调用的小工具，用法见文件头：
  - `python3 -I helpers/vo.py count <jsonl> kind=agent_gone task=verify-gone`：数假端点记录
  - `python3 -I helpers/vo.py mask <源> <目标>`：掩码复制
  - `python3 -I helpers/vo.py guard <webhook 目录> <notify-run.log>`：真实 HOME 守卫的一次快照
  - `python3 -I helpers/vo.py stuck-fixture <目录> <pid1> <pid2>`：生成卡住检查的 Orca 夹具和进程表
  - `python3 -I helpers/vo.py summary <运行目录>`：重写 summary.json 和 report.md
  - `orca` / `linear` / `probe` / `freeport` 由沙箱里的替身脚本调用，一般不手动用。

维护地图（功能变了、加了入口）用 `/pstack:maintain-verification-skill`。
