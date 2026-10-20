# PER-134：stuck-check --dry-run 退出码 4（KeyError 'phases'）

- base：`a1d9a68f47e8f6cccd5d06b3beb3ccdc7a5162a2`（origin/main）
- 修复提交：`12680cc34678bfa717268af4a76a41e9772d6493`（只改 `scripts/stuck-check.sh`；之后的提交只加本目录的报告和对照脚本）
- 机器：iMac，macOS 26.6（Darwin 25.6.0），Python 3.13.13，Orca CLI `/Applications/Orca.app/Contents/Resources/bin/orca`
- 时间：2026-10-21 01:15–01:52 SGT

## 现象和根因

在 main 上跑 `bash scripts/stuck-check.sh --dry-run`，iMac 一类查完后退出码 4，日志：

```
脚本出错：Traceback (most recent call last):
  File "<stdin>", line 2199, in <module>
  File "<stdin>", line 1866, in main
  File "<stdin>", line 2086, in hist_phase
KeyError: 'phases'
```

（`<stdin>` 行号比文件行号小 111，因为 python 部分是从 heredoc 读进去的。原始输出见 `live/dryrun-base.out`。）

根因在 f6408d0（PER-82）：`hist_begin()` 在 dry-run 时直接返回，`HIST` 留空；`hist_phase()` 靠 `if not HIST` 判断「这次不记」。
但 `main()` 随后无条件写 `HIST["plan"] = plan`（整轮时限到了还写 `HIST["truncated"]`），`HIST` 变成没有 `phases` 的非空字典，
下一个 `hist_phase()` 执行 `HIST["phases"].append(...)` 就 KeyError。第一个 `hist_phase("闸门")` 在写 plan 之前，所以能过；
崩在 plan 之后的第一个阶段。正式扫描（`--scan`、不带参数）走 `hist_begin` 的完整分支，`HIST` 里有 `phases`，不受影响。
这不是旧格式的历史文件不兼容：dry-run 根本不读 `scan-history.json`。

## 改法

`hist_begin()` 在 dry-run 时也按正式扫描的结构建好 `HIST`（`plan=[]`、`phases=[]`、`truncated=False` 等），只在内存里记。
`hist_save()` 开头本来就有 `if DRY: return`，所以 dry-run 仍然不写 `scan-history.json`；dry-run 也不读上次的历史（不改 dry-run 的阶段顺序）。
正式扫描那条分支只是把同一个字典提成变量 `rec`，内容和顺序不变。

## 对照一：真实运行（不套 harness）

在当前 Orca 上直接跑 base 和 head 两个版本的脚本，各用一份 `~/.orca-state/stuck-check` 的副本作状态目录。

```
STUCK_STATE_DIR=<副本> STUCK_RUNS_DIR=<副本>.runs STUCK_BOX_ENV=__no_box__ bash <base 或 head 的 stuck-check.sh> --dry-run
```

`STUCK_BOX_ENV=__no_box__` 是个不存在的环境名，orca 在本机就报「Unknown Orca server」，不连 box。MBA 照常查。

| 版本 | 退出码 | 状态目录里的 json | 输出 |
|---|---|---|---|
| base | 4（KeyError 'phases'） | 跑前跑后 sha256 相同 | `live/dryrun-base.out` |
| head | 0 | 跑前跑后 sha256 相同 | `live/dryrun-head.out` |

head 的 dry-run 走完 iMac、box（连不上，跳过）、MBA、due 四个阶段，最后打印「结束：0 条嫌疑，1 条直发，0 条发送失败」，那条直发只打印「dry-run，将 POST 给 …」，没有发。

## 对照二：同一份快照、同一盘磁带上回放，逐行比

正式路径不能在线上真发，所以用录制回放：

1. `bash reports/per134-dryrun-fix/run.sh record`：把 `~/.orca-state/stuck-check` 只读复制成冻结快照 `state0`，
   然后用 harness（`harness/sitecustomize.py`，经 `PYTHONPATH` 载入）真跑一遍各模式，把每条外部命令
   （orca、gh、agent-probe、orca-wake --list、git 查询）的输出按顺序录成磁带。录制时 `--run`、`--scan` 加
   `STUCK_NO_SEND=1`（脚本自带的只读演练开关：照常扫描和写状态，不 POST，orca-wake 只跑 --list）；
   harness 另外一律拦下 curl 和带 `--environment grok-bot` 的调用。webhook 配置换成假的（只照抄文件名），真密钥不进来。
2. `bash reports/per134-dryrun-fix/run.sh replay`：base 和 head 各从同一份 `state0` 复制状态，从同一盘磁带取外部命令结果，
   不跑任何外部命令；`time.time()` 固定在录制开始的时刻，`time.sleep` 不睡。跑完后用 `normalize.py` 把 stdout 和所有状态文件
   规范化（去掉日志时间戳、pid、耗时），base 和 head 逐行 diff。

多出的两组「正式路径」用例（`runformal`、`runfullformal`）不加 `STUCK_NO_SEND`，就是线上不带参数时的路径。
这时脚本会去调 `orca-wake recheck --agent-pid 65882`（真叫醒），磁带里没有这条命令，harness 不执行、返回失败，
脚本记「调用 orca-wake recheck 失败 … 这次不报，下次再查」；base 和 head 一样。curl 也会被拦下并回 200，但这份快照里没有要发的直发消息，两组都没走到 curl。

结果（`out/SUMMARY.txt`）：

| 用例 | 参数 | base 退出码 | head 退出码 | base vs head |
|---|---|---|---|---|
| dry | `--dry-run` | 4（KeyError 'phases'） | 0 | 不一致：base 在 iMac 一类后崩，head 跑完（`out/dry.diff`） |
| dryfull | `--dry-run --full` | 4（KeyError 'phases'） | 0 | 不一致：同上，head 多跑了第二类（`out/dryfull.diff`） |
| run | 不带参数，`STUCK_NO_SEND=1` | 0 | 0 | 一致，diff 0 行 |
| runfull | `--full`，`STUCK_NO_SEND=1` | 0 | 0 | 一致，diff 0 行 |
| scan | `--scan`，`STUCK_NO_GATE=1 STUCK_NO_SEND=1` | 0 | 0 | 一致，diff 0 行 |
| runformal | 不带参数（正式路径） | 0 | 0 | 一致，diff 0 行 |
| runfullformal | `--full`（正式路径） | 0 | 0 | 一致，diff 0 行 |

逐行一致的范围：stdout 里的每条判定（嫌疑、问题、直发、「将 POST 给」的完整内容）以及跑完后的
`agents.json`、`track.json`、`notified.json`、`pending.json`、`gate.json`、`heartbeat.json`、`scan-history.json`（只去掉 pid 和时间字段）、`stuck-check.log`。

回放可信度：base 的 run、runfull、scan 的录制（真跑）和回放比，差别只有时间戳字段
（`handed`、`last_seen`、`seen`、`done`、`last_full`、`last_scan`，录制时用真实时钟，回放时冻结），判定和其余状态逐行相同（`out/*-fidelity.diff`）。

## 复跑

```
cd <本仓库>
bash reports/per134-dryrun-fix/run.sh replay                       # 用已有输入复跑对照，约 7 秒
bash reports/per134-dryrun-fix/run.sh record && bash reports/per134-dryrun-fix/run.sh replay   # 换一份新快照重录（约 7 分钟）
```

`PER134_BASE`、`PER134_HEAD` 可指定两边的 commit（默认 base 为 a1d9a68，head 为当前 HEAD）。
输入（快照、磁带、录制时的输出）在 iMac 的 `~/.cache/per134-dryrun-fix/`，没进仓库：磁带里有 Orca 终端屏幕内容。
`replay` 开头用 `SHA256SUMS` 校验输入没变，本次的校验和抄在 `out/SHA256SUMS`。

## 没跑的

- 正式路径的真实发送（curl 到 webhook）和真实 `orca-wake recheck` 补叫醒：没跑，会真发消息、真叫醒 agent。回放里这两类调用被拦下；这份快照没有直发消息，curl 那条分支 base 和 head 都没走到。
- box：没跑，box 已退出开发；所有用例里 box 都是「连不上，跳过」。
- 整轮时限截断（`HIST["truncated"]` 那条写法）：快照里没有触发，回放冻结时钟后也不会触发；修复后 dry-run 的 `HIST` 一开始就有 `truncated` 和 `phases`，这条写法不再能造出缺 `phases` 的字典。
- 已安装在 `~/.orca-state` 下的 stuck-check 没动，没做线上部署。
- 录制时 `--run`、`--scan` 每次约 73 秒，主要是 `__no_box__` 查询失败后的重试等待，和本次改动无关。
