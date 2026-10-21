# B2a 演练产物（PER-146）：新任务不在 box 上跑

- 演练提交：`5820dde3f5670f92773567c5df84f7c4daefb4e0`（META 里 `uncommitted=0`）。之后的提交只加本目录。
- base：`f828d452345f16898d6c9d133984e170d98d9f83`（`git merge-base HEAD origin/main`）。修前那一轮用 `git archive` 取出来跑，不检出。
- 命令（在 iMac 上）：`E2E_OUT=<目录> /bin/bash automations/migration-1020/e2e/run-e2e.sh both`，退出码 0。
- 机器：iMac（`hostname -s` = iMac）和 MBA（mba），都是 macOS 26.6.2，/bin/bash 3.2.57。iMac 本机跑；MBA 经 ssh 跑 `/tmp/b2a-e2e-*` 里的副本，跑完删掉。
- 时间：2026-10-22 00:54:33–00:58:42（+0800）。修前一轮约 2 分钟，修后一轮约 2 分钟。

这是 dry-run 演练，不是现网 E2E：

- 叫醒发到两台机器 127.0.0.1 上的假 webhook（`mock_webhook.py`），env 文件和 KEY 是假的（`e2e-fake`）。
- 日期用 2099 年（`NR_D`），时钟（`NR_NOW`）、pmset、ioreg 用固定值或文件，`orca` 换成记录器。
- 存放位置用本地目录；只有 N8、G1a、G1b 用默认的 box，由不联网的 `fake-ssh.py` 扮演。

演练没有连 box，没有连真 webhook，没有注册或改动任何任务。闸门和同步脚本在 PATH 里先找到的 ssh 是 `ssh-spy`，它按名字和地址（`ssh -G box` = 100.64.0.6）拒绝 box，并记录每次调用。两台机器四份记录里都没有 box，也没有被拒的调用。

## 结果

66 项检查，全部符合预期（`SUMMARY.md`、`revert.tsv`）：

| 类别 | 项数 | 修后（本分支） | 修前（base，回退测试） |
|---|---|---|---|
| 新加（N1–N9、W0、M5a、M5b） | 12 | 12 PASS | 12 FAIL |
| 保留（PER-79 里不靠 box 的行为） | 47 | 47 PASS | 47 PASS |
| 演练自检（X0、X1、X2、W7c、K1c） | 5 | 5 PASS | 5 PASS |
| 只在修后跑（G1a、G1b） | 2 | 2 PASS | SKIP |

## 任务书里的五条演练

| 任务书要求 | 检查 | 修后 | 修前 | 产物 |
|---|---|---|---|---|
| `run-e2e.sh both` 在 iMac 上用假 webhook 跑通，不连 box、不连真 webhook，列出每个场景的结果 | 全部；X0、X1、W7c 查 ssh 和 webhook | 66/66 PASS | 见上表 | `post/results.tsv`、`post/log`、`*/ssh-spy-*.log`、`*/hooks.jsonl`、`*/mba-hooks.jsonl` |
| `register.sh imac`、`register.sh mba` 的打印输出存档，任务名集合和 defs.json 一致 | N3、R1a、R1b | PASS：MBA 9 条、iMac 10 条，合起来 19 条 = defs.json 全部 create | N3 FAIL：base 的 defs 有 23 条，4 条 box 看守哪台 Mac 都不打印 | `*/register-{mba,imac}.{out,err,rc}`、`*/register-names.txt`、`*/defs-table.tsv` |
| `register.sh box` 退出 2 | N2 | PASS：rc 2，stdout 空，stderr 一行说明 | FAIL：rc 0，打印了 box 的命令（3291 字节） | `*/register-box.{out,err,rc}` |
| `rg -n 'machine": *"box"' automations/migration-1020/defs.json` 为空 | N1 | PASS：rc 1，没有输出 | FAIL：13 行（4 条 create、9 条 edit） | `*/rg-box.txt` |
| 新旧 `night-review-gate.sh` 在默认变量下对同一组状态文件判定一致 | G1a（什么都不设）、G1b（只设旧变量名） | PASS：各 44 个场景，每个版本 48 次调用，计入的差异 0 | SKIP（修前新旧是同一份） | `post/g1/G1a/REPORT.md`、`post/g1/G1b/REPORT.md`（`old.json`、`new.json` 是逐次调用的记录） |

G1a、G1b 比较每次调用的这些结果：退出码、状态文件、接替标记、同步标记、锁、存放目录里的文件、叫醒的 status / reason / task、同步调用、ssh 的目标主机和命令种类。只列出、不计入的差异是两类有意改动：

- 发给 box 的路径：修前是本机展开的 `/Users/...`（演练里是假 HOME 下的路径），修后是字面 `~/xinyue-deploy/nightly-review`。只出现在 G1a。
- 两条 stuck 叫醒：`machine=box`、「run the disabled box task by hand」改成 `machine=imac`、按 iMac 备用接替；状态文件里的 `escalated=box` 跟着改成 `escalated=imac`。场景是 backup-lock-busy-over-60min、box-watch-nobody、box-watch-imac-down、xinyue-box-watch-nobody，G1a、G1b 都有。

## 回退测试：新加的检查在 base 上为什么挂

每一项都是因为 base 的脚本或定义缺这次的改动，不是环境问题（`pre/log` 里有原文）：

| 检查 | base 上的结果 |
|---|---|
| M5a | `SYNC_SRC_HOST=local` 被当成主机名：`ssh: Could not resolve hostname local`，同步退出 3 |
| M5b | `SYNC_SRC_HOST=imac` 在 iMac 上 ssh 自己：`Host key verification failed.`，同步退出 3 |
| N4、N9、W0 | base 不认 `NR_STORE_HOST` / `NR_STORE_DIR`，按 `NR_BOX_HOST=nosuchhost.invalid` 去拷：`detail=rsync_failed`，退出 4；W0 里 iMac 看守随后按 asleep 写接替标记，备用放行，同一晚会再跑一遍 |
| N5、N7 | stuck 写 `machine=box`，提示去跑 box 上停用的旧任务 |
| N8 | 什么都不设时，发给存放主机的 mkdir / tar 和 grep 用的是本机展开的路径（`pre/n8/ssh.jsonl`）；修后是字面 `~/...`（`post/n8/ssh.jsonl`） |
| N1、N2、N3 | 见上一节 |
| N6 | 提示词里还有「拷回 box」「box 上 01:00 的兜底检查」「改用 `ssh box ...` 跑 Linear」，noop 里还有 `box-watch` |

## 文件

- `SUMMARY.md`：两轮的 META 和逐项对照表；`revert.tsv`：同一张表的 tsv。
- `pre/`、`post/`：`results.tsv`（id、结果、类别、说明、检查表达式）、`log`（每一步的命令和输出）、`META`、`results.sha256`（`results.tsv` 的 sha256；记录的是原目录的路径，拷过来以后内容的 sha256 仍然一致）。
- `ssh-spy-imac.log`、`ssh-spy-mba.log`：每次 ssh 一行（时间、`pass` 或 `REFUSED`、目标、`ssh -G` 解析出的地址、远端命令）。
- `hooks.jsonl`、`mba-hooks.jsonl`：两台假 webhook 收到的叫醒（只记 KEY 对不对，不记 KEY）。
- `mba-artifacts.tgz`：MBA 上的状态文件、存放目录、夜审目录和 M6 的同步结果。
- `make-prompts-check.txt`：`make-prompts.py --check` 的输出和退出码。
- 没拷过来的：假 HOME、夹具、锁目录、修前取出的 base 代码树。这些可以用上面的命令重新生成。

## 没跑的

- 现网 E2E：要先注册并启用新任务，本 PR 不注册。
- 默认存放位置（box）的真实拷贝和完成判定：不许连 box。只在 N8、G1a、G1b 里用不联网的假 ssh 跑了判定。
- 真 box 拉清单（M1a、M1b、M3a、M3b、M1i）、box 清理预检（C1a–C1e、C2a、C2b）、真 EverOS 读回（E1）：要连 box 或读凭据，B2a 去掉了这些场景（`automations/migration-1020/e2e/FAILURE-MODES.md`「去掉的场景」）。
