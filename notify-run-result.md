# notify-run 收尾测试结果（2026-10-13 22:50–22:58 SGT）

执行者：Claude Code（iMac，工作区 `ops-notify-run-收尾测试`）。box 上的操作通过 `orca --environment grok-bot` 开的终端完成。

7 条测试全部符合预期，webhook 都返回 200。vllm-omni 那条前两次返回 400，原因是接收端限流，第三次 200（见下）。notify-run 脚本没有改。

## 版本核对

| 位置 | sha256 | 说明 |
|------|--------|------|
| iMac `~/.local/bin/notify-run` | `f14f3a313ff8b919048e3151a8779d8fa462a32fc40a28e75d251ddbc038950c` | 基准，5679 字节 |
| 提交 62b2a22 的 `scripts/notify-run` | `f14f3a31…8950c` | 与 iMac 已装版逐字节相同 |
| 仓库工作区文件（`dv运维-notify-run-脚本/scripts/notify-run`，只读取，未改动） | `f14f3a31…8950c` | 与 iMac 已装版相同。没有看到提交之后的改动 |
| box `/home/box/.local/bin/notify-run`（覆盖前） | `9927cf37e4f1de4b2796bf704cc1a7ba68b7d0ccc4136d77638c6b2a8d5afb3b` | 5625 字节，22:40 写入。不是旧版，是截断的文件：停在第 142 行中间，缺结尾 5 行 |
| box `/home/box/.local/bin/notify-run`（覆盖后） | `f14f3a31…8950c` | 755，`bash -n` 通过 |

- 提交 a967957（第一版）的 sha 是 `3c87bb50…a6ada1`，三处都不是它。
- ops 主检出（`~/orca/workspaces/ops`）里没有 `scripts/notify-run`，脚本只在分支 `zack/dv运维-notify-run-脚本` 上。
- box 上被截断的旧文件留作备份：`/home/box/.local/bin/notify-run.bak-truncated-20261013`。它有执行权限且在 bin 目录里，确认不需要后可以删。

以下测试跑的都是 `f14f3a31…8950c` 这一版。

## env 文件

- iMac：`~/.config/grokbot/webhooks/coding-assistant.env` 从 `stuck-webhook.env` 复制，600，键名是 `URL` 和 `KEY`，与 notify-run 读的键名一致，没有改。
- box：`/home/box/.config/grokbot/webhooks/coding-assistant.env`，600，158 字节，键名 `URL`、`KEY`，sha256 前 16 位与 iMac 那份相同（`27113a8f475562dd`）。
- 传输方式与之前不一定相同：笔记和 shell 历史里查不到之前是怎么拷的，box 上也没有内容相同的文件可以直接复制。这次的做法是在 box 上生成一次性 RSA 密钥对，iMac 用公钥加密 env，只把密文经 Orca 终端发过去，box 解密落盘后删除密钥对。明文密钥没有出现在命令行参数和终端输出里。

## 测试结果

| # | 机器 | bot | 命令 | exit_code | status | HTTP |
|---|------|-----|------|-----------|--------|------|
| 1 | iMac | coding-assistant | `true` | 0 | done | 200 |
| 2 | iMac | coding-assistant | `false` | 1 | failed | 200 |
| 3 | iMac | coding-assistant | `sleep 300`，4 秒后 `kill`（TERM） | 143 | killed | 200 |
| 4 | box | coding-assistant | `true` | 0 | done | 200 |
| 5 | box | coding-assistant | `false` | 1 | failed | 200 |
| 6 | box | coding-assistant | `sleep 300`，4 秒后 `kill`（TERM） | 143 | killed | 200 |
| 7 | iMac | vllm-omni | `true`（task「notify-run 连通测试，忽略」） | 0 | done | 200（第 3 次） |

- exit_code 和 status 取自 notify-run 打到 stderr 的那一行，并和 shell 里的 `$?` 核对过，两者一致。HTTP 码是 notify-run 自己报告的 curl 返回码，没有到接收端去查消息是否送达。
- 第 3、6 条 kill 之后 `sleep 300` 进程已退出，webhook 各只发了一次。
- box 上的 task 文本是「notify-run 测试 box true」「notify-run 测试 box false」「notify-run 测试 box sleep 300 后 kill」，iMac 上相应换成 iMac。

### 第 7 条的 400

22:55 和 22:56 两次返回 400，22:57 第三次返回 200，三次的 exit_code 都是 0、status 都是 done。中间用同样的 payload 手动发了一次看响应内容，接收端（Cursor automations）返回：

`Automation run rate limit exceeded: global limit 12000 per minute, current_count=19219`

这是接收端的全局限流，不是 notify-run 的问题。同一时段发给 coding-assistant 的 6 条都是 200。vllm-omni 一共被请求 4 次（notify-run 3 次，手动诊断 1 次），只有最后一次被接受。

需要留意的一点：webhook 发送失败时 notify-run 只在 stderr 打一行，不重试，也不改退出码。接收端限流时，这次通知就丢了。要不要加重试由 Coding助手 决定，这次没有动脚本。

## 其他

- box 负载：测试开始时 load average 4.30 / 13.89 / 13.44。box 上只跑了上面三条命令、sha 校验和文件安装。
- box 上为测试开的终端（在 `/workspace/repos/deepvision-site` 下，只借用了目录，没有碰仓库文件）已关闭。
- 工作区「dv运维 · notify-run 脚本」没有改动，只读了 `scripts/notify-run` 的 sha 和 git 状态。

## 追加：全 bot 测试（iMac，2026-10-13 23:08–23:18 SGT）

对 deepvision-ads、deepvision-marketing、xinyue 各跑 true、false、sleep 300 后 kill，vllm-omni 补 false 和 kill，共 11 条。脚本版本同上（`f14f3a31…8950c`），task 都是「notify-run 连通测试，忽略」。11 条的 exit_code 和 status 都符合预期，最终都拿到 200，但其中 7 条要重试才成功。

| # | bot | 命令 | exit_code | status | HTTP（按尝试顺序） | 第一次尝试时间 |
|---|-----|------|-----------|--------|--------------------|----------------|
| 8 | deepvision-ads | `true` | 0 | done | 400, 400, 200 | 23:08:31 |
| 9 | deepvision-ads | `false` | 1 | failed | 200 | 23:10:11 |
| 10 | deepvision-ads | `sleep 300`，4 秒后 kill | 143 | killed | 400, 200 | 23:10:22 |
| 11 | deepvision-marketing | `true` | 0 | done | 400, 200 | 23:11:20 |
| 12 | deepvision-marketing | `false` | 1 | failed | 200 | 23:12:15 |
| 13 | deepvision-marketing | `sleep 300`，4 秒后 kill | 143 | killed | 400, 200 | 23:12:26 |
| 14 | xinyue | `true` | 0 | done | 400, 200 | 23:13:24 |
| 15 | xinyue | `false` | 1 | failed | 200 | 23:14:18 |
| 16 | xinyue | `sleep 300`，4 秒后 kill | 143 | killed | 400, 400, 200 | 23:14:29 |
| 17 | vllm-omni | `false` | 1 | failed | 200 | 23:16:18 |
| 18 | vllm-omni | `sleep 300`，4 秒后 kill | 143 | killed | 400, 400, 200 | 23:16:30 |

- 间隔：一条拿到 200 后等 6 秒再跑下一条；返回 400 后等 45 秒，把同一条整条重跑（命令重新执行一次），最多 3 次。
- 每次重跑的 exit_code 和 status 都相同，表里只写一次。每次 kill 后 `sleep 300` 都已退出，结束时没有残留进程。
- 一共发了 21 次请求：11 次 200，10 次 400。每个 bot 实际收到的条数是 3 条（vllm-omni 本轮 2 条）。
- 这一轮没有读 400 的响应内容。前面第 7 条读到的是接收端全局限流（`global limit 12000 per minute`），这 10 次 400 推测是同一原因，但没有逐条确认。
- 隔 5 秒以上并不能避开 400：限流是接收端全局计数，和我们自己发得多快关系不大。11 条里有 7 条第一次就被拒，也就是说现在的 notify-run（不重试）在这个时段会丢掉一半以上的通知。
