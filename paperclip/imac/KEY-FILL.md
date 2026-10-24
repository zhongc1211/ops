# 给 ops-system agent 填 Console API key（Zack 在 iMac 本机做）

agent 用了 `--bare`，claude 只认环境变量 `ANTHROPIC_API_KEY`（或 apiKeyHelper），不会退回订阅登录。
所以 key 填好之前，agent 就算被叫醒也跑不起来。下面两种方法任选一种。key 不经过聊天、不在终端回显、不写日志、不进仓库。

先注意：

- 只在 iMac 本机做（坐在 iMac 前，或者用屏幕共享）。不要经 ssh 粘贴：粘贴的内容会经过另一台机器的终端。
- 填 key 不会让 agent 开工：agent 还是暂停，两个触发器还在 setupPending（带对 bearer 也只记测试回执）。
- 填好以后 agent 一旦被恢复、被触发，就会按这个 key 花钱。月预算上限 200 美元（agent 配置里的 `budgetMonthlyCents`）。

## 方法一：终端，`read -s` 读入（推荐）

1. 在 iMac 上打开「终端」。
2. 运行：

   ```bash
   ~/.local/share/paperclip-ops/scripts/key-fill.sh
   ```

3. 看到「粘贴 Console API key 后回车（屏幕不显示）」后，粘贴 key 并回车。屏幕上不会出现任何字符。
4. 最后一行应是 `填好了，读回： 有 | agent 状态: paused`。

脚本做的事：建 company「ops 系统」的 secret `ANTHROPIC_API_KEY`，再把 agent `ops-system` 的
`adapterConfig.env.ANTHROPIC_API_KEY` 绑到这个 secret（`secret_ref`）。key 用 `read -s` 读，经管道交给 python，
不进命令行参数（`ps` 看不到）、不进 shell 历史、不写文件；任何请求失败都只打印 HTTP 状态码，不打印响应内容。
secret 已经存在时脚本会停下，不覆盖。

## 方法二：Paperclip 网页

1. 在 iMac 上用浏览器打开 `http://127.0.0.1:3110`（只能在 iMac 本机打开）。
2. 进 company「ops 系统」的 Secrets（密钥）页，新建一个 secret，名字和 key 都写 `ANTHROPIC_API_KEY`，值粘贴 Console API key，保存。
3. 进 agent `ops-system` 的配置，在环境变量里加 `ANTHROPIC_API_KEY`，选「引用 secret」，选刚建的 `ANTHROPIC_API_KEY`，保存。
   不要选「明文」：明文值会存在 agent 配置里。
4. 不要点「恢复」（resume）或「运行」。

网页上的菜单名是按 API 推的，没有逐个点过核对；和上面写的不一样时，以「company secret + agent 环境变量引用 secret」为准。

## 检查（只打印 有/没有）

在 iMac 上运行（ssh 进去跑也可以，这一步不碰 key）：

```bash
~/.local/share/paperclip-ops/scripts/key-fill.sh --check
```

secret 存在，并且 agent 的 `env.ANTHROPIC_API_KEY` 引用的正是它，才打印「有」，否则「没有」。
2026-10-25 装好时跑过一次，结果是「没有」。

## 换 key 或撤掉

- 换 key：在网页的 Secrets 页对 `ANTHROPIC_API_KEY` 做轮换（rotate），agent 的引用不用改。
- 撤掉：网页上先删掉 agent 环境变量里的 `ANTHROPIC_API_KEY`，再删 secret。然后跑检查，应为「没有」。
