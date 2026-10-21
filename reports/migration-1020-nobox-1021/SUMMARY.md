# B2a drill (run-e2e.sh both)

post (this checkout):

    mode=post
    commit=5820dde3f5670f92773567c5df84f7c4daefb4e0
    base=f828d452345f16898d6c9d133984e170d98d9f83
    tree=/Users/jiawenwang/orca/workspaces/ops/ops-migration-nobox-b2a-1021
    uncommitted=0 (files in the checkout that differ from the commit)
    date=2026-10-22 00:56:39 +0800
    imac: iMac bash=3.2.57(1)-release macOS=26.6.2
    mba: mba bash=3.2.57(1)-release macOS=26.6.2
    notify-run sha256: imac=4ce9845ef12349d4 mba=4ce9845ef12349d4
    box: not contacted (ssh-spy-imac.log, ssh-spy-mba.log)
    rt=mba:/tmp/b2a-e2e-20261022-005640-post-99652 box-address imac=100.64.0.6 mba=100.64.0.6

pre (base, the revert test):

    mode=pre
    commit=5820dde3f5670f92773567c5df84f7c4daefb4e0
    base=f828d452345f16898d6c9d133984e170d98d9f83
    tree=/private/tmp/claude-501/-Users-jiawenwang-orca-workspaces-ops-ops-migration-nobox-b2a-1021/ab93b969-c8ee-4fc6-8748-adf58cc346ca/scratchpad/e2e-20261022-005430/pre/tree
    uncommitted=0 (files in the checkout that differ from the commit)
    date=2026-10-22 00:54:33 +0800
    imac: iMac bash=3.2.57(1)-release macOS=26.6.2
    mba: mba bash=3.2.57(1)-release macOS=26.6.2
    notify-run sha256: imac=4ce9845ef12349d4 mba=4ce9845ef12349d4
    box: not contacted (ssh-spy-imac.log, ssh-spy-mba.log)
    rt=mba:/tmp/b2a-e2e-20261022-005434-pre-95502 box-address imac=100.64.0.6 mba=100.64.0.6

66 checks: new 12 (post PASS, pre FAIL), kept 47 (PASS on both), drill 5 (PASS on both), post-only 2 (post PASS, pre SKIP).
Not as expected: none.

| id | class | what | post | pre | as expected |
|---|---|---|---|---|---|
| X0 | drill | 两台机器上，闸门（按它自己的 PATH 行）和同步脚本先找到的 ssh 都是演练的记录用 ssh | PASS | PASS | yes |
| L1 | kept | 锁被占时第二个 acquire 退出 1，status 显示持有者 | PASS | PASS | yes |
| L2 | kept | 8 个并发 acquire 恰好 1 个拿到 | PASS | PASS | yes |
| L3a | kept | 超过 40 分钟的锁被收回 | PASS | PASS | yes |
| L3b | kept | 39 分钟的锁不收回 | PASS | PASS | yes |
| L4a | kept | 名字不对的 release 退出 1，锁还在 | PASS | PASS | yes |
| L5 | kept | refresh 后重新计时 | PASS | PASS | yes |
| L4b | kept | 本人 release 后锁空 | PASS | PASS | yes |
| D1a | kept | 00:30 往回 13 小时 = 昨天 | PASS | PASS | yes |
| D1b | kept | 23:40 往回 6 小时 = 当天 | PASS | PASS | yes |
| D1c | kept | 跨月、跨年、闰年 | PASS | PASS | yes |
| D1d | kept | next：闰年、跨年 | PASS | PASS | yes |
| D2 | kept | MBA / iMac 提示词不含 date -d，日期用 review-date.sh | PASS | PASS | yes |
| D3a | kept | 4 个夜审提示词里算 D 的命令在 MBA /bin/bash 3.2 上实跑出日期 | PASS | PASS | yes |
| D3b | kept | 同样的命令在 iMac（没有 gdate）实跑出日期 | PASS | PASS | yes |
| M2a | kept | 源主机连不上：退出 3，SYNC-STATUS=failed | PASS | PASS | yes |
| M2b | kept | 源主机（MBA）上没有这天：退出 3，SYNC-STATUS=failed | PASS | PASS | yes |
| M5a | new | iMac 上 SYNC_SRC_HOST=local：同步成功，SYNC-STATUS=ok，3 个 transcript 都是本机可读副本 | PASS | FAIL | yes |
| M5b | new | iMac 上 SYNC_SRC_HOST=imac（本机名）：不 ssh 自己，同步成功 | PASS | FAIL | yes |
| M6 | kept | MBA 从 iMac 上的清单同步（ssh imac，只读）：成功，transcript 都是 MBA 本机可读副本 | PASS | PASS | yes |
| W1a | kept | MBA 离线：看守退出 1、写接替标记 reason=offline | PASS | PASS | yes |
| W1b | kept | iMac 备用拿 iMac 锁放行 | PASS | PASS | yes |
| W1c | kept | 收尾经 notify-run：拷进存放目录、记 done、放锁，ops-system 收到 1 条 done，task 含 machine=imac reason=offline | PASS | PASS | yes |
| W2a | kept | 用电池：MBA 主预检退出 1，记 missed reason=asleep | PASS | PASS | yes |
| W2b | kept | 看守（iMac 经 ssh 读 MBA）判 asleep | PASS | PASS | yes |
| W2c | kept | 合盖、没禁睡、没外接屏：主预检退出 1，reason=asleep detail=lid_closed | PASS | PASS | yes |
| W2d | kept | MBA 能连上但当晚预检没跑：看守判 asleep | PASS | PASS | yes |
| W2e | kept | 合盖但接电源、SleepDisabled=1：主预检放行，记 started | PASS | PASS | yes |
| K1a | kept | 主预检起了 caffeinate（MBA 上按 pid 看进程名） | PASS | PASS | yes |
| S1 | kept | 主预检先同步清单再拿锁（同步调用记录有 vllm-omni 2099-01-04 mba） | PASS | PASS | yes |
| W8a | kept | 补跑触发时当晚已 started：退出 1，不记 lock_busy | PASS | PASS | yes |
| W8b | kept | MBA 在跑（started < 60 分钟）：看守不写接替标记 | PASS | PASS | yes |
| W8c | kept | 补跑在 MBA 时间 +25 分钟以后不起（交给 iMac） | PASS | PASS | yes |
| W8d | kept | MBA 时间 +30 分钟以前 iMac 备用不接替 | PASS | PASS | yes |
| W3a | kept | MBA 锁被占：主预检记 lock_busy | PASS | PASS | yes |
| W3b | kept | 看守判 lock_busy 并交给 iMac | PASS | PASS | yes |
| W4 | kept | iMac 锁被占超过 60 分钟：ops-system 收到 1 条 stuck reason=lock_busy，只 1 条 | PASS | PASS | yes |
| N5 | new | 这条 stuck 写 machine=imac，提示按 iMac 备用接替，不提 box | PASS | FAIL | yes |
| W5 | kept | 存放目录已有完成摘要：MBA 主预检退出 1 | PASS | PASS | yes |
| W6 | kept | 存放目录已有完成摘要：iMac 备用预检退出 1，不拿锁 | PASS | PASS | yes |
| W7a | kept | box-watch（保留，没有任务用；这里在 MBA 上跑）：iMac 接替在跑时不发 | PASS | PASS | yes |
| W7b | kept | box-watch：没人完成时 ops-system 收到 1 条 stuck reason=imac_missed，只 1 条 | PASS | PASS | yes |
| N7 | new | box-watch 的 stuck 写 machine=imac，提示按 iMac 备用接替，不提 box | PASS | FAIL | yes |
| F1 | kept | 摘要没有「状态：完成」：finish 退出 3，放锁 | PASS | PASS | yes |
| F2 | kept | 拷不到存放主机：finish 退出 4，记 rsync_failed，放锁 | PASS | PASS | yes |
| K1b | kept | 防睡任务起 caffeinate 后退出 1（不起模型） | PASS | PASS | yes |
| N4 | new | NR_STORE_HOST=local、NR_STORE_DIR 生效（NR_BOX_HOST 指向连不上的主机）：收尾拷到 NR_STORE_DIR 退出 0；同晚备用按新位置看到完成，退出 1、不拿锁 | PASS | FAIL | yes |
| N9 | new | iMac 上 NR_STORE_HOST=imac（本机名）：收尾走本地拷贝，这一步没有 ssh，退出 0、放锁 | PASS | FAIL | yes |
| W0 | new | 存放位置设成 iMac（README「切换到 iMac 存放」）：MBA 主跑、收尾经 ssh 拷到 iMac，iMac 看守 seen_done，备用退出 1、不拿锁，ops-system 收到 MBA 的 done | PASS | FAIL | yes |
| N8 | new | 什么都不设时，发给存放主机 box（这里是不联网的 fake-ssh）的 mkdir / tar 和 grep 里是字面 ~/xinyue-deploy/nightly-review/ | PASS | FAIL | yes |
| R1a | kept | register 默认 dry-run：mba / imac / box 各跑一次，orca 调用 0 次 | PASS | PASS | yes |
| R1b | kept | MBA 9 条、iMac 10 条 create，每条都带 --missed-run-grace-minutes 120 和 --disabled | PASS | PASS | yes |
| N1 | new | defs.json 里没有 box：rg 没有输出，没有 box-watch、/workspace/repos/ops，edit 为空 | PASS | FAIL | yes |
| N2 | new | register.sh box 退出 2：stderr 一行说明，stdout 为空，不调用 orca | PASS | FAIL | yes |
| N3 | new | register.sh mba / imac 打印的任务名和 defs.json 里这台的一致，合起来是 defs.json 的全部 create | PASS | FAIL | yes |
| P1a | kept | MBA / iMac 提示词不含 /workspace/repos、/var/lib/everos-ingest、load>8、coding-assistant | PASS | PASS | yes |
| P1b | kept | 8 个夜审提示词都有 caffeinate、heavy-lock refresh、SYNC-STATUS、finish、状态：完成、首行运行环境 | PASS | PASS | yes |
| P1c | kept | make-prompts.py --check：提交的提示词和生成结果一致 | PASS | PASS | yes |
| P1d | kept | iMac 接替提示词写明读回去重；MBA 版没有 | PASS | PASS | yes |
| N6 | new | 提示词和 noop 里没有 box 兜底（拷回 box、box 上 01:00 的兜底、Linear 连不上改用 box、box-watch）；8 个夜审收尾都写存放位置 NR_STORE_HOST | PASS | FAIL | yes |
| G1a | post | 新旧 night-review-gate.sh 在什么都不设时判定一致（逐个场景见 g1/G1a/REPORT.md） | PASS | SKIP | yes |
| G1b | post | 只设旧变量名 NR_BOX_HOST / NR_BOX_DIR 时判定一致（g1/G1b/REPORT.md） | PASS | SKIP | yes |
| K1c | drill | MBA 主预检和防睡任务起的 caffeinate 到时自己退出 | PASS | PASS | yes |
| X1 | drill | 两台机器的 ssh 记录里没有 box（名字或地址），没有被拒的调用；确有 iMac→MBA、MBA→iMac 的记录（闸门和同步确实经过它） | PASS | PASS | yes |
| X2 | drill | 演练文件里没有结束进程的命令；两台机器的假 webhook 看到停止文件后自己退出 | PASS | PASS | yes |
| W7c | drill | 两台机器的叫醒只到 127.0.0.1 上的假 webhook：ops-system 各至少 1 条，coding-assistant 0 条，KEY 都是假的那个 | PASS | PASS | yes |

G1a / G1b scenario by scenario: post/g1/G1a/REPORT.md, post/g1/G1b/REPORT.md.
