# orca-agent-wake

> **状态：测试中。** 已在一台 macOS 机器和一台 Linux 机器上安装，并用本地模拟 webhook 和专用测试 webhook 跑过测试。真实 bot 默认处于影子模式（只记日志、不发送），列进 `enabled-bots` 后才会真发。

派活 bot 用 `notify-run --tty` 在终端里启动交互式 Claude Code 或 Pi 后，agent 做完会停在输入框，不会退出，`notify-run` 也就不会发完工通知。这个仓库在 agent 停下时直接通知派活 bot，不依赖 agent 自己记得汇报。

- Claude Code：全局 hook（Stop、StopFailure、Notification 等）调用 `orca-wake claude-hook`。
- Pi：扩展 `dispatch-wake.ts` 在 `agent_settled`、`ui_prompt_start` 时调用 `orca-wake send`。
- 两者共用 `orca-wake`：判断要不要叫、去重、发 webhook、写 `wake.log`。
- `notify-run` 在 `--tty` 模式下导出 `ORCA_DISPATCH_*` 环境变量，用来识别「派出的主会话」。

设计细节见 [docs/DESIGN.md](docs/DESIGN.md)，测试清单和结果见 [docs/TESTS.md](docs/TESTS.md)。

## 文件

| 路径 | 安装位置 | 作用 |
|---|---|---|
| `bin/orca-wake` | `~/.local/bin/orca-wake` | 共用脚本（Python 3，只用标准库） |
| `bin/orca-wake-hooks` | `~/.local/bin/orca-wake-hooks` | 在 `~/.claude/settings.json` 里添加、删除、检查本项目的 hook 条目，其他条目不动 |
| `bin/notify-run` | `~/.local/bin/notify-run` | 派活包装脚本，`--tty` 时导出 `ORCA_DISPATCH_*` |
| `pi/dispatch-wake.ts` | `~/.pi/agent/extensions/dispatch-wake.ts` | Pi 扩展 |
| `hooks/claude-settings.example.json` | — | hook 条目示例（`orca-wake-hooks install` 写入的就是这些） |
| `.env.example` | `~/.config/grokbot/webhooks/<bot>.env` | webhook 配置格式（与 notify-run 共用） |
| `tests/unit.sh`、`tests/mock_webhook.py` | — | 离线测试和本地模拟 webhook |
| `tests/pi-ext.test.mjs` | — | Pi 扩展的离线测试（假事件、假 orca-wake），`node --experimental-strip-types tests/pi-ext.test.mjs` |

## 安装

```bash
install -m 755 bin/orca-wake bin/orca-wake-hooks bin/notify-run ~/.local/bin/
cp pi/dispatch-wake.ts ~/.pi/agent/extensions/          # 用 Pi 时
mkdir -p ~/orca-wake-backup
orca-wake-hooks install --backup-dir ~/orca-wake-backup  # 改 settings.json 前自动备份
orca-wake-hooks check
mkdir -p ~/.config/orca-wake && touch ~/.config/orca-wake/enabled-bots
```

webhook 配置沿用 notify-run 的 `~/.config/grokbot/webhooks/<bot>.env`（`URL=`、`KEY=`，权限 600）。KEY 只放在请求头里，不写进日志。

派活时 agent 必须是 `notify-run` 的直接子进程：

```bash
notify-run --bot <bot> --task "<任务>" --tty -- claude --dangerously-skip-permissions ...
notify-run --bot <bot> --task "<任务>" --tty -- pi ...
```

不要写成 `notify-run ... -- bash -c "cd x; claude ..."`：这时 agent 的父进程是 bash，hook 会按「不是派出的主会话」跳过并在 `wake.log` 记 `parent_mismatch`。（bash 对 `bash -c "claude ..."` 这种单条命令会直接 exec，碰巧能用，但不要依赖。）

## 放行与静音

- **影子模式**：`~/.config/orca-wake/enabled-bots` 一行一个 bot 名，写 `*` 表示全部放行。不在名单里的 bot 照常判断、去重、写 `wake.log`（`event: shadow`），但不发 webhook。
- **人接手会话**：在会话工作目录（或它到 git 根之间的任一上级目录）放一个 `.orca-wake-mute` 文件，该会话停止叫醒；删掉后恢复。

## 回滚

```bash
orca-wake-hooks remove --backup-dir ~/orca-wake-backup   # 只删本项目的 hook 条目
rm ~/.pi/agent/extensions/dispatch-wake.ts
# notify-run 换回旧版本（导出的变量没有其他用途，不换也不影响原功能）
rm -rf ~/.local/state/orca-wake ~/.config/orca-wake      # 可选：删状态和配置
```

## 卡住检查补叫醒

`orca-wake recheck --agent-pid <pid>`：调用方（卡住检查）发现 agent 停在输入框时调用。该停顿已有成功的叫醒就跳过，否则补发一次（`source=stuck-check-recheck`），默认要求会话至少 30 分钟没有新动静（`--idle-min`）。`orca-wake recheck --list` 只列出候选，不发送。卡住检查脚本本身不在这个仓库里，接入方式（包括 orca-wake 不认识的会话怎么兜底）见 DESIGN。

## 已知限制

- Claude Code 的 `idle_prompt` 触发条件和 transcript 里的 `queue-operation` 记录都不是公开接口，Claude Code 升级后要重跑 `docs/TESTS.md` 的核心场景。已测版本：2.1.299、2.1.300。
- Esc 中断、权限被拒这类没有 Stop 的停顿，只能靠卡住检查补叫醒，最长约 45 分钟（30 分钟阈值 + 15 分钟检查周期）。
- 卡住检查判断「停在输入框」依赖 Orca 的 agent 状态和等待输入检测。Orca 丢了这些状态时（测试中第二台机器的 Orca 断线重连后出现过），卡住检查会把停着的 agent 当成 agent_silent，按原来的方式报，不经过 orca-wake 的去重。
- 另一个 Stop hook 先 block 一次时，按「同一回合」只叫一次，正文取最后一次 Stop 的消息。
- Pi 的 `--mode rpc` 跳过逻辑与 json/print 相同（`ctx.mode` 不是 `tui`），只实测了 json 和 print。

## 许可

MIT，见 [LICENSE](LICENSE)。
