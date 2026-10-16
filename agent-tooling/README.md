# agent-tooling — 唤醒系统

coding agent 停在输入框、要权限或报错时叫醒派活的 bot 的那套东西，原样从 box 收进来（2026-10-16，box 与 iMac 当时 sha 一致），行为没改。

**维护人：Coding助手。** 项目 bot 不直接改这里的文件，也不直接改两台机器上装好的副本；要改先找 Coding助手，改完走 PR，合并后再在两台跑 `install.sh`。

## 装到哪里

| 仓库里 | 装到（box 和 iMac 同一相对路径） |
|---|---|
| `bin/orca-wake` | `~/.local/bin/orca-wake` |
| `bin/orca-wake-hooks` | `~/.local/bin/orca-wake-hooks` |
| `bin/notify-run` | `~/.local/bin/notify-run` |
| `pi-extensions/dispatch-wake.ts` | `~/.pi/agent/extensions/dispatch-wake.ts` |
| `pi-extensions/orca-agent-status.ts` | `~/.pi/agent/extensions/orca-agent-status.ts` |
| `claude/orca-wake-hooks.settings-fragment.json` | `~/.claude/settings.json` 里 orca-wake 的 5 组 hook（只是结构，由 `orca-wake-hooks install` 写入） |

不归 install.sh 管、也不进仓库的：

- 密钥：`~/.config/grokbot/webhooks/<bot>.env`、`~/.config/grokbot/runpod.env`、`~/.config/everos/*.env`。仓库里只有 `env-examples/` 下的 `.example`（只有键名），`.gitignore` 挡住所有 `*.env`。新机器照 `.example` 手填，权限 600。
- `~/.config/orca-wake/enabled-bots`（真发 webhook 的 bot 名单，其余 shadow），2026-10-16 两台都是 `coding-assistant`。

`everos/` 暂时是空目录，等心月样板交来再收。

## 检查（不改任何文件）

```bash
agent-tooling/install.sh --check
```

逐个文件比对 sha256，settings.json 里摘出 orca-wake 的 hook 组和 `claude/` 片段比对。全一致输出 `check: all ok`、退出 0；有 `differs` / `missing` 退出 1。

## 安装

```bash
agent-tooling/install.sh
```

- 只装 sha 不一样或缺的文件；一样的跳过，重复跑结果不变，全一致时输出 `nothing to do`，不建备份目录。
- 覆盖前把旧文件备份到 `~/.agent-tooling-backup/<YYYYmmdd-HHMMSS>/`（保留 `~` 下的相对路径），原来没有的文件记进 `new-files.txt`。
- settings.json 只经 `bin/orca-wake-hooks install` 改：只替换 command 同时含 `orca-wake` 和 `claude-hook` 的 hook 组，Orca 自己的 hook 和其他设置不动；改前整文件副本也放进同一备份目录。
- 装完自动再跑一次 `--check`。

## 回滚

```bash
agent-tooling/install.sh --rollback ~/.agent-tooling-backup/<时间>
```

把备份目录里的文件拷回原处，删掉 `new-files.txt` 里那次新装的文件；settings.json 用恢复后的 `orca-wake-hooks` 改回（原来没有 hook 就 `remove`，原来有就按旧版本 `install`）。万一还不对，备份目录里有 `settings.json.bak-<时间>` 整文件副本，可人工比对后恢复。

只想临时停掉唤醒、不回滚文件：在会话目录（或其上到 git 根的任一级）`touch .orca-wake-mute`；或 `~/.local/bin/orca-wake-hooks remove` 拿掉 Claude hooks。
