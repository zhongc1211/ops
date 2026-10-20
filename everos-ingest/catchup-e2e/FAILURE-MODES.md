# 采集推送补推（PER-67，2026-10-20）：先写会怎么失败

写在代码之前。每条后面是 E2E 怎么查（`e2e-catchup.sh`），查不了的写「没查」。

背景：10-19 17:54 → 10-20 10:22 box 整机冻结，MBA 四条推送都 `exit 2 nothing pushed`，之后没人补推。
box 还会再冻（`/workspace/ops/reports/orca-serve-1020/REPORT.md` 第 (3) 节：宿主侧停顿），补推要是每次运行都做的事。

## 要做到的
- 每次采集运行：照旧采 D、推 D；推成功后在本机 `<D>/.pushed` 写清单 sha256。
- 然后看 D-1 … D-N（`CATCHUP_DAYS`，默认 3）：本机有 `sessions-<machine>.jsonl`、box 上没有或 sha256 不同的日期，
  推本机已有的那份（不重新采集），成功后写 `.pushed`。
- `CATCHUP_ONLY=1`：不采集，只补推 D … D-N（给可选的低频 automation 用）。

## 会怎么失败
| # | 失败方式 | E2E 怎么查 |
|---|---|---|
| F1 | 第一次推失败（box 不通）时写了 `.pushed`，之后以为推过了 | 第 1 次运行后 `.pushed` 不存在，退出码 2 |
| F2 | 补推时重新采集，推上去的不是当时那份（或把旧日期采成今天的内容） | 第 2 次运行前后 D-1 本机清单和转写的 sha256 不变；日志里补推子进程没有采集输出 |
| F3 | 补推推了，但 box 上的清单和本机不一致 | 第 2 次运行后 box 上 D-1 清单 sha256 = 本机 = `.pushed` |
| F4 | 每次运行都重复推已经在 box 上的日期 | 第 3 次运行日志里 D-1 是「on box, sha ok」，box 文件 mtime 不变 |
| F5 | box 上的文件丢了或被换了，本机标记还在，就不再推 | 删掉 box 上 D-1 清单后第 4 次运行重新推上 |
| F6 | 升级后旧日期没有 `.pushed`，但 box 上已有同一份，又全推一遍 | 删掉本机 `.pushed`、box 不动，第 5 次运行不推，只补写标记 |
| F7 | 本机日期目录在、清单不在（采集中途失败），补推时报错或推半份 | 造一个只有空目录的 D-2，运行不报错、不推 |
| F8 | 超过 N 天的日期也去推 | 造一个 D-(N+1) 本机清单，运行后 box 上没有 |
| F9 | 补推子进程又去补推（递归）或又采集 | 子进程用 `PUSH_ONLY=1`；日志里每个补推日期只出现一次，没有采集输出 |
| F10 | box 列表 ssh 失败时当作「box 全没有」，把 N 天全推一遍（`collect-mba.sh:59-60`） | 2026-10-20 dr eggbot 复验后补查（见下「F10/F11 怎么造故障」）：run6 先把 box 上 D0 清单挪进隔离目录，`CATCHUP_ONLY=1`，只让含 `for d in <日期>` 的那次 ssh 失败。预期：退出 6，日志有 `cannot list box`，没有 `pushing the local copy`，box 上 D0 仍然没有清单，D1 mtime 不变，替身日志里这次失败恰好触发 1 次 |
| F11 | 补推失败时当天的成功被盖掉、或写了标记（`collect-mba.sh:73-74`） | run7：box 上 D0 仍然没有清单，删掉本机 D0 `.pushed`，`CATCHUP_ONLY=1`，只让推 D0 清单的 scp 失败（子进程 retry3 三次后退出 3）。预期：退出 6，日志有 `catch-up <D0>: push exited 3`，本机 D0 没有 `.pushed`，box 上 D0 没有清单，D1 的 `.pushed` = 本机 sha、box D1 mtime 不变，替身日志里触发 3 次 |
| F12 | 补推超出 precheck 600s 时限 | 没查；仓库三类脚本按剩余预算传给子进程（repo/官网 `PUSH_BUDGET`），心月用 `CATCHUP_BUDGET` 截止 |
| F13 | 今天推失败了还去补推，失败原因被补推输出淹没 | 第 1 次运行（box 不通）日志里没有 catch-up 行 |
| F14 | `CATCHUP_ONLY=1` 去采集，或者漏了 D 本身 | 第 6 次运行：`CATCHUP_ONLY=1`，删掉 box 上 D 的清单，运行后推上，本机清单 sha256 不变 |
| F15 | 改动碰到真目录（`~/.orca-state/everos-ingest`、box `/var/lib/everos-ingest`） | 全程用 `EVEROS_LOCAL_BASE` / `EVEROS_REMOTE_BASE` 指到 scratch 和 box `/tmp`；结束前后对比真目录列表 |
| F16 | 回退：旧脚本其实也会补推（那就不需要改） | 旧脚本（只替换路径和主机名）跑同样 3 次，D-1 一直不在 box 上 |
| F17 | 6 份脚本改得不一样 | 用 diff 对比 MBA/iMac 副本，只差机器名 |
| F21 | box 上已有同一天、内容不同的清单时，补推直接覆盖，box 原件丢了，查不回当时夜审读的是哪份。做法：推之前在 box 上把清单、excluded 清单和 `mba/` 复制成 `<名字>.replaced-<box 时间戳>`（用复制不用 mv：推到一半失败时，box 上仍是原来那份，不会变成没有清单） | run8：box 上 D0 清单换成一份内容不同的旧文件（记下 sha），`CATCHUP_ONLY=1` 无故障。预期：退出 1；box D0 下恰好 1 个 `sessions-mba.jsonl.replaced-<时间戳>`，sha = 旧文件；box D0 清单 = 本机；`.pushed` = 本机 sha。run9 再跑一次：日志是 `on box, sha ok`，`.replaced-*` 仍是 1 个，box D0 mtime 不变（sha 相同不改名、不重写） |

### F10/F11 怎么造故障（2026-10-20 补）
`catchup-e2e/shim/ssh`、`shim/scp` 放在 PATH 最前，只给被测脚本用（检查用的 ssh 不经过它）。命令行匹配 `E2E_FAIL_SSH` / `E2E_FAIL_SCP` 正则的那一次直接退出 255，并在 `E2E_SHIM_LOG` 记一行；其余调用原样交给 `/usr/bin/ssh`、`/usr/bin/scp`。被测的采集、推送、box 都是真的。
覆盖心月（`collect-mba.sh`）和广告（`collect-mba-repo.sh`）。回退：旧脚本（3d8294b）用和 run6、run7 相同的环境变量和替身再跑两次（旧脚本不认 `CATCHUP_ONLY`，会照常采集、推 D1），预期退出 1、替身一次都没触发、box 上始终没有 D0。差异就在这里：旧脚本不列 box、不补推，故障对它没有作用；新脚本碰到故障退出 6，下次再补。
F21 只在新脚本上查（旧脚本不补推，没有覆盖这一步）。

## E2E 跑出来、事先没写到的
| # | 失败方式 | 怎么发现 / 怎么查 |
|---|---|---|
| F18 | 当天没有转写时，`n_tx=$(ls "$LOCAL/<machine>/"*.jsonl … \| wc -l)` 在 `set -euo pipefail` 下让脚本在推完后直接 exit 1，补推一步没跑 | 第 2 轮 E2E（bc18b80）广告 run2：D1 推上了、`.pushed` 写了，日志停在 `box: swapped`，D0 没补推。旧脚本里同一行也是这样，只是它本来就在最后，退出码碰巧是 1。修后由广告 run2 的 F3/F9 检查覆盖（四个目标里只有广告 10-19 本机没有转写） |
| F19 | 心月当天转写大时，推送本身就用掉大半时限，`CATCHUP_BUDGET=300` 让补推一次都开始不了 | 第 3 轮 E2E（fd84ec5）心月 run2：采集 30 秒，推 49 MB 用了约 6 分钟（四个目标同时推），到第 400 秒才轮到补推，按 300 秒截止退出 6。先把默认改成 420，第 5 轮（52a1a55）心月 run2 推到第 453 秒，仍然没补推（D0 本机 0 份转写，几秒就能推完）。改成按大小估：用今天实测的推送速度估这一天要多久，第 560 秒前推得完才开始（MBA、iMac 采集 automation 的 precheck 时限都是 600s）。修后由心月 run2 的 F3/F9 检查覆盖；大的旧日期仍可能排不上，见 README |
| F20 | 心月 `CATCHUP_ONLY` 时没有今天的实测速度，按 50 KB/s 估，49 MB 的一天估成 999 秒，永远不开始 | 第 7 轮 E2E（4aa34da，逐个跑）心月 run5。默认改成 100 KB/s（实测 100–123 KB/s） |

另外第 7 轮看到：心月 10-19 这 49 MB 单是「今天」的推送就用了 8–11 分钟（run4 整次 654 秒），超过 600s precheck 时限。旧脚本一样，与补推无关；心月推送不能续传，这一点要另外处理，写在 PR 里。
