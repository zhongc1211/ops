# ops-system webhook（PER-90）

发给 ops-system 的叫醒有三条路径：notify-run（命令结束）、orca-wake（agent 停下）、stuck-check（卡住检查补叫醒）。三条都读 `~/.config/grokbot/webhooks/ops-system.env`（`URL=`、`KEY=`，权限 600）；orca-wake 还要求 `~/.config/orca-wake/enabled-bots` 里有 ops-system，否则只写影子日志不发。

## 三台现状（2026-10-20 21:00 SGT，只读核对）

| 机器 | ops-system.env | 权限 | URL= / KEY= | enabled-bots 含 ops-system | 已装 notify-run / orca-wake / orca-agent-launch 与 origin/main | 测试叫醒 |
|---|---|---|---|---|---|---|
| box（grok-bot-vm） | 有 | 600 | 各 1 行 | 是（8 行） | 一致 | 21:01:07 HTTP 200 |
| MBA | 有 | 600 | 各 1 行 | 是（7 行） | 一致（`wake/install.sh --check` 全部一致） | 21:00:59 HTTP 200 |
| iMac | 有 | 600 | 各 1 行 | 是（9 行） | 一致；stuck-check.sh 与 origin/main 一致 | 21:01:09 HTTP 200 |

三台 ops-system.env 内容一致（比过 sha256，只记结论，不记指纹）。三台的 `test.env` 都在、不在 enabled-bots（影子，符合预期）。

### stuck-check 怎么找到 ops-system

stuck-check 按「agent 外面包的 `notify-run --bot`」优先定 bot。orca-agent-launch 已经用 `notify-run --bot ops-system` 包住 ops 系统派的 agent，所以这类会发给 ops-system。

没有被 notify-run 包住的 ops 工作区（例如手开的终端）：origin/main（b28b7a5）的 stuck-check.sh 把 ops 仓库（「定时任务」）映射到 bot `ops`，三台都没有 `ops.env`，会转发 coding-assistant，不会到 ops-system。PR #45（`ops-stuck-routing-1020`）把这条映射改成 ops-system；合并并装到 iMac 之前，这条路径仍到 coding-assistant。本 PR 不改 stuck-check.sh。

## 怎么核对

```bash
# 本机
scripts/check-bot-webhooks --require ops-system
# 远端（脚本经 stdin 传过去，不需要远端有仓库）
ssh box  'bash -s -- --require ops-system' < scripts/check-bot-webhooks
ssh imac 'bash -s -- --require ops-system' < scripts/check-bot-webhooks
```

退出码 0 正常、1 有问题、2 用法错误。只看文件存在、权限、变量名和值是否非空，不输出值，不发请求。

真送达要另发一条测试叫醒（会真的打到 ops 系统，按需发）：

```bash
NOTIFY_RUN_TRIES=1 notify-run --no-tty --bot ops-system --task "[演练 <编号> webhook <机器>]" -- true
tail -1 ~/.orca-state/notify-run/notify-run.log   # 看 http= 那一列；日志不含 URL / KEY
```

## 回退测试

`docs/ops-system-webhook/regress.sh <仓库路径> <输出目录>`：在临时 HOME 里放假 env（值都是 FAKE*），逐项跑下面的情况，核对退出码、报错文字、输出里没有 FAKE。跑完删掉临时 HOME。

## 回滚

本次只新增 `scripts/check-bot-webhooks` 和 `docs/ops-system-webhook/`，没有装到任何机器、没改线上配置。回滚就是删掉这些文件（或 revert 这个 PR）。

## check-bot-webhooks 要分辨的情况（先写，后写脚本）

1. 某 bot 在 enabled-bots 里，但没有 `<bot>.env`：叫醒发不出去，报「缺 env」。
2. `<bot>.env` 存在但不可读：notify-run 退到 /home/box 路径、orca-wake 跳过，报「不可读」。
3. 权限不是 600：报「权限」。
4. 缺 `URL=` 或 `KEY=`，或值为空：三个读取方都当没配置，报「缺 URL / 缺 KEY」。
5. 同一个变量写了多行：不同读取方取的值可能不同（source 取最后一行），报「重复」。
6. 有 env 但不在 enabled-bots 里：orca-wake 只写影子日志不发，报「影子」（提示，不算错）。
7. enabled-bots 文件不存在：所有 bot 都是影子，报错。
8. enabled-bots 写了 `*`：全部放行，照常逐个查 env。
9. `--require <bot>` 指定的 bot 不在 enabled-bots 或没有 env：报错。
10. 脚本自己不能泄露：不输出值、不输出 sha、不发网络请求。
