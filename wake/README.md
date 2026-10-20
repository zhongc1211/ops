# wake：派活 agent 叫醒

> **状态：已上线（iMac + box）。** 2026-10-17 起，五个派活 bot 都已列进 `enabled-bots` 真发叫醒，不再是影子模式（之前只有 Coding助手放行）。
>
> 本目录原是独立仓库 `zhongc1211/orca-agent-wake`，2026-10-17 用 `git subtree` 并进 ops（保留提交历史），原仓库设为只读归档。以后只在 ops 里改、从 ops 安装。

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
| `bin/orca-agent-launch` | `~/.local/bin/orca-agent-launch` | 统一的起 agent 入口：检查后 exec `notify-run --tty`；没带 `--bot`、没有 webhook 配置、经 `bash -c` 转一层的一律拒绝 |
| `pi/dispatch-wake.ts` | `~/.pi/agent/extensions/dispatch-wake.ts` | Pi 扩展 |
| `hooks/claude-settings.example.json` | — | hook 条目示例（`orca-wake-hooks install` 写入的就是这些） |
| `.env.example` | `~/.config/grokbot/webhooks/<bot>.env` | webhook 配置格式（与 notify-run 共用） |
| `tests/unit.sh`、`tests/mock_webhook.py` | — | 离线测试和本地模拟 webhook |
| `tests/lint-bash32-utf8.sh` | — | 在仓库根目录跑：查 wake/、scripts/ 的 shell 里 `$name` 紧跟全角字符（/bin/bash 3.2 会报 unbound variable，要写 `${name}`），有命中打印「文件:行」并 exit 1 |

## 安装

在 ops 仓库根目录运行（iMac、box 通用，可重复运行）：

```bash
wake/install.sh --check     # 只比对已装版本和仓库版本，有差异退出 1
wake/install.sh --dry-run   # 列出会改哪些文件
wake/install.sh             # 安装：内容相同的不动，要覆盖的先备份成 <文件>.bak-<时间戳>
```

`install.sh` 装 `bin/` 下三个脚本和 ops 的 `scripts/agent-probe` 到 `~/.local/bin/`；有 `~/.pi/agent/extensions/` 时同时装 Pi 扩展；没有 `enabled-bots` 时建一个空文件。它不改 `~/.claude/settings.json`、`enabled-bots` 内容和 webhook 配置。首次安装还要手动加 hook：

```bash
mkdir -p ~/orca-wake-backup
orca-wake-hooks install --backup-dir ~/orca-wake-backup  # 改 settings.json 前自动备份
orca-wake-hooks check
```

webhook 配置沿用 notify-run 的 `~/.config/grokbot/webhooks/<bot>.env`（`URL=`、`KEY=`，权限 600）。KEY 只放在请求头里，不写进日志。

派活一律用 `orca-agent-launch` 起 agent（2026-10-19 起，PER-65）。它检查参数后 exec `notify-run --tty`，agent 是 notify-run 的直接子进程：

```bash
orca-agent-launch --bot <bot> --task "<任务>" [--issue X] -- claude --dangerously-skip-permissions ...
orca-agent-launch --bot <bot> --task "<任务>" -- pi ...
# 作为 Orca 终端命令：
orca terminal create --worktree <wt> --command "orca-agent-launch --bot coding-assistant --task 'PER-65 xxx' -- claude --dangerously-skip-permissions '读 BRIEF 并照做'"
```

没带 `--bot`/`--task`、bot 没有 webhook 配置、要起的不是 claude / pi / codex、经 `bash -c` / `env` / `nohup` 转一层、已经在一个活着的 notify-run 里，都拒绝（退出码 2，什么都不起）。漏网的由卡住检查兜底：三台机器上活着、父链里没有 notify-run 的 claude / pi / codex（Orca 自动任务起的除外）会报给派活的 bot（`agent_unwrapped`，见 `scripts/stuck-check.sh`）。直接写 `notify-run --bot <bot> --task "<任务>" --tty -- claude ...` 效果相同，但没有这些检查。

不要写成 `notify-run ... -- bash -c "cd x; claude ..."`：这时 agent 的父进程是 bash，hook 会按「不是派出的主会话」跳过并在 `wake.log` 记 `parent_mismatch`。（bash 对 `bash -c "claude ..."` 这种单条命令会直接 exec，碰巧能用，但不要依赖。）

## 放行与静音

- **影子模式**：`~/.config/orca-wake/enabled-bots` 一行一个 bot 名，写 `*` 表示全部放行。不在名单里的 bot 照常判断、写 `wake.log`（`event: shadow`），但不发 webhook，也不记成已发（见下方「卡住检查补叫醒」）。
- **人接手会话**：在会话工作目录（或它到 git 根之间的任一上级目录）放一个 `.orca-wake-mute` 文件，该会话停止叫醒；删掉后恢复。

## 回滚

```bash
orca-wake-hooks remove --backup-dir ~/orca-wake-backup   # 只删本项目的 hook 条目
rm ~/.pi/agent/extensions/dispatch-wake.ts
# notify-run 换回旧版本（导出的变量没有其他用途，不换也不影响原功能）
rm -rf ~/.local/state/orca-wake ~/.config/orca-wake      # 可选：删状态和配置
```

## 卡住检查补叫醒

`orca-wake recheck --agent-pid <pid>`：调用方（卡住检查）发现 agent 停在输入框时调用。该停顿已有成功的叫醒就跳过，否则补发一次（`source=stuck-check-recheck`），默认要求会话至少 30 分钟没有新动静（`--idle-min`）。`orca-wake recheck --waiting-pid <pid>[:<since_ms>]`：agent 停在对话框（Orca 状态 waiting）时调用，只补发该对话框的 needs_input，去重键与 hook 相同；hook 已送达时返回 `already_asked`，不重发。`orca-wake recheck --list` 只列出候选，不发送。卡住检查脚本是 ops 的 `scripts/stuck-check.sh`，接入方式（包括 orca-wake 不认识的会话怎么兜底）见 DESIGN。

**依赖关系：** 卡住检查读 orca-wake 的状态目录（`~/.local/state/orca-wake/sent/`，经 `orca-wake recheck`）判断一次停顿是否已叫醒过，所以改 `sent/` 的写法或去重键时要同时看 `scripts/stuck-check.sh`。影子模式不写 `sent/`（只写 `shadow/`），不算已叫醒；卡住检查发现影子停顿时转报 coding-assistant（派活 bot 不在 `enabled-bots` 里），不会悄悄漏掉。

## 已知限制

- Claude Code 的 `idle_prompt` 触发条件和 transcript 里的 `queue-operation` 记录都不是公开接口，Claude Code 升级后要重跑 `docs/TESTS.md` 的核心场景。已测版本：2.1.299、2.1.300。
- Esc 中断、权限被拒这类没有 Stop 的停顿，只能靠卡住检查补叫醒，最长约 45 分钟（30 分钟阈值 + 15 分钟检查周期）。
- 卡住检查判断「停在输入框」依赖 Orca 的 agent 状态和等待输入检测。Orca 丢了这些状态时（测试中第二台机器的 Orca 断线重连后出现过），卡住检查会把停着的 agent 当成 agent_silent，按原来的方式报，不经过 orca-wake 的去重。
- Claude 的对话框是否还开着靠 transcript 判断（最后一条是 assistant 的 tool_use），这也不是公开接口。
- webhook 限流时按 1、5、15 分钟退避，同一次叫醒最多等 25 分钟，之后写 `failed`，留给补叫醒。
- 另一个 Stop hook 先 block 一次时，按「同一回合」只叫一次，正文取最后一次 Stop 的消息。
- Pi 的 `--mode rpc` 跳过逻辑与 json/print 相同（`ctx.mode` 不是 `tui`），只实测了 json 和 print。

## 许可

MIT，见 [LICENSE](LICENSE)。
