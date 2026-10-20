# 禁用命令的确定性拦截（PER-89）

2026-10-20 交接第 5 项停用了 5 个插件命令：pstack 的 `poteto-mode`、`tdd`、`reflect`、`setup-pstack`，compound-engineering 的 `lfg`。本目录把拦截改成三道防线，高负载时主防线不会因为 hook 超时而放行。

## 文件

| 文件 | 作用 |
|---|---|
| `settings-fragment.json` | 要合并进 `~/.claude/settings.json` 的内容：5 条 deny、1 个 `UserPromptExpansion` hook、1 个 `UserPromptSubmit` hook |
| `hooks/disabled-cmd-prompt-guard.sh` | 补充用的 `UserPromptSubmit` 脚本，只用 bash 内建命令 |
| `install.sh` | 合并、核对、回滚，幂等 |
| `tests/e2e-load.sh` | 端到端测试：隔离配置 + 真实 `claude -p` + CPU 加压 + 故障注入 |

## 三道防线

| 防线 | 挡什么 | 失败时 |
|---|---|---|
| `permissions.deny` 里的 `Skill(skill:<名字>)` | 模型用 Skill 工具调用这 5 个 skill | 不涉及 hook，不会超时；`--dangerously-skip-permissions` 下照样生效 |
| `UserPromptExpansion` hook（主防线，挡人手输入） | 人或派活文字直接输入 `/pstack:tdd`、`/tdd` 等，命令展开之前 | 设了 `onFailure: "block"`：hook 超时或起不来也按 exit 2 处理，命令不展开（fail-closed） |
| `UserPromptSubmit` hook `disabled-cmd-prompt-guard.sh`（补充） | 提示词开头是这 5 个命令 | 超时后 Claude Code 丢掉 hook 输出、提示词照常发出（fail-open）。不能给它加 `onFailure: "block"`：那样高负载时所有提示词都会被挡 |

### deny 规则

```
Skill(skill:pstack:poteto-mode)
Skill(skill:pstack:tdd)
Skill(skill:pstack:reflect)
Skill(skill:pstack:setup-pstack)
Skill(skill:compound-engineering:lfg)
```

这是参数形式。官方文档（[permissions](https://code.claude.com/docs/en/permissions#match-by-input-parameter)）：

> A `Skill(skill:<name>)` deny rule instead matches the skill under any of its names, such as its alias or display name

[skills](https://code.claude.com/docs/en/skills#restrict-claude’s-skill-access) 的表格里，参数形式这一行写的是 "The skill whichever of its names Claude calls it by, including its alias and display name"。

#48 装的 10 条旧规则（`Skill(pstack:tdd)`、`Skill(pstack:tdd *)` 等）保留不动，新规则是追加。

### 为什么 deny 管不到人手输入的 slash 命令

deny 规则作用在工具调用上。人直接输入 `/name` 不经过 Skill 工具，也不触发 `PreToolUse`。官方文档（[hooks · UserPromptExpansion](https://code.claude.com/docs/en/hooks#userpromptexpansion)）：

> This event covers the path `PreToolUse` doesn't: a `PreToolUse` hook matching the `Skill` tool fires only when Claude calls the tool, but typing `/skillname` directly bypasses `PreToolUse`. `UserPromptExpansion` fires on that direct path.

E2E 的故障注入 (c) 把两个 hook 都去掉、只留 deny：模型调用照样被拒，人手输入 `/pstack:tdd` 照常展开。结果见 PR。

### UserPromptExpansion hook

- `matcher`：`^((pstack:)?(poteto-mode|tdd|reflect|setup-pstack)|(compound-engineering:)?lfg)$`。含 `^`，Claude Code 按 JavaScript 正则处理；整串锚定，不会误伤 `tdd-guide`、`superpowers:tdd`、`pstack:how`、`lfgx`。
- `command_name` 的实际取值（2026-10-20 在 MBA 用探针 hook 记 stdin 实测，Claude Code 2.1.304）：输入 `/pstack:how` 得到 `pstack:how`；输入不带前缀的 `/poteto-mode` 得到 `pstack:poteto-mode`，`command_source` 是 `plugin`。即不带前缀的写法会解析成带前缀的全名。matcher 两种都写上，以防以后版本行为变化。
- `command`：`echo 'Blocked (PER-89): ...' >&2; exit 2`。不读 stdin，不起 node、python、grep。`Blocked (PER-89)` 也是 `install.sh` 认自己条目的标记。
- `timeout: 5`，`onFailure: "block"`（要求 Claude Code ≥ 2.1.295）。官方文档（[Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails)）："With `"block"` set, a failure does what exit code 2 does on that event"。

### UserPromptSubmit 补充脚本

`disabled-cmd-prompt-guard.sh` 取代 #48 的 `block-disabled-skills.sh`：读 stdin 用 `IFS= read -r -d ''`，匹配用 `[[ =~ ]]`，不起子进程。规则和旧脚本一样：提示词开头（允许前导空白或转义换行）是这 5 个命令之一就 exit 2。

它只兜 `UserPromptExpansion` 不触发的情况。实测 `UserPromptSubmit` 在 `UserPromptExpansion` 之前跑，所以两者都在时，多数情况是它先挡下。官方文档写明它超时会放行：

> a `UserPromptSubmit` command, HTTP, or MCP tool hook that reaches its timeout is canceled and its output, including any `additionalContext`, is discarded. The prompt still reaches Claude without that context.

## 安装、核对、回滚

在 ops 仓库根目录跑。只对新起的 claude 会话生效。

```bash
bootstrap/claude-deny/install.sh --dry-run --out /tmp/settings.per89.json   # 看合并结果，不动原文件，打印 sha256
diff -u ~/.claude/settings.json /tmp/settings.per89.json
bootstrap/claude-deny/install.sh --apply       # 备份为 settings.json.bak-per89-<时间>，装 hook 脚本，原子写回，打印前后 sha256
bootstrap/claude-deny/install.sh --check       # 一致退出 0；不一致逐项列出，退出 1
bootstrap/claude-deny/install.sh --uninstall   # 回滚，见下
```

`--settings-file <路径>`、`--hooks-dir <目录>` 可以改目标（测试用）。

`install.sh` 只改三处，其他键（插件、notify、Orca 的 hook 等）原样保留、顺序不变，文件保持原来的 2 空格缩进：

- `permissions.deny`：没有的才追加；
- `hooks.UserPromptExpansion`：没有带 `Blocked (PER-89)` 的条目就追加，有就换成片段里的版本；
- `hooks.UserPromptSubmit`：调 `block-disabled-skills.sh` 的那一项原位换成新脚本；已经是新脚本就更新成片段里的版本；都没有就追加。

`--uninstall` 撤掉 5 条 deny 和 `UserPromptExpansion` 条目；`UserPromptSubmit` 里的新脚本项，若 `~/.claude/hooks/block-disabled-skills.sh` 还在就换回旧项（`timeout: 30`，与 #48 一致），否则删掉；再删掉 `~/.claude/hooks/disabled-cmd-prompt-guard.sh`。在 iMac 设置副本上实测：`--apply` 再 `--uninstall`，sha256 回到原值。

也可以直接用 `--apply` 打印的备份文件回滚：`cp -p ~/.claude/settings.json.bak-per89-<时间> ~/.claude/settings.json`。

## 和 #48 的关系

#48（`bootstrap/claude-plugins/`）的 `block-disabled-skills.sh` 和 `install-block-hook.sh` 被本目录取代。本 PR 不改这两个文件，由 #48 的负责人另行处理。注意：#48 的 `pin-claude-plugins.sh` 会调 `install-block-hook.sh`，在装了本目录之后再跑它，会把旧的 `UserPromptSubmit` 项加回来；这时重跑 `install.sh --apply` 即可换回。

## 已知绕过

都要人有意去做：

- `claude --settings '{"disableAllHooks":true}'` 关掉所有 hook，只剩 deny；
- `claude --setting-sources project,local`（不含 user）不读 `~/.claude/settings.json`，deny 和 hook 都不生效；
- 直接改 `~/.claude/settings.json`。

要防有意绕过，只能写 managed settings（macOS `/Library/Application Support/ClaudeCode/managed-settings.json`），要 sudo，要 Zack 批，本 PR 不做。

## 端到端测试

```bash
bootstrap/claude-deny/tests/e2e-load.sh --live ~/.claude/settings.json --out <证据目录> [--load 8] [--budget 1.00]
bootstrap/claude-deny/tests/e2e-load.sh --live ~/.claude/settings.json --out <证据目录> --only selftest   # 只跑匹配表和耗时，不调 claude
```

- live 设置只复制、不改；每种配置都由 `install.sh --dry-run` 对副本生成，用 `--setting-sources project --settings <副本>` 起 `claude -p`（haiku），插件和插件 hook 照常加载。加 `--strict-mcp-config` 不起 MCP 服务器：它们和 skill、hook 无关，在 MBA 高负载下光连 MCP 就要几分钟。单次运行上限 `--run-timeout`（默认 900 秒）。
- 加压：脚本自己起 N 个忙循环（`perl -e 'alarm 300; 1 while 1'`，每轮最多 5 分钟），只 kill 自己的 PID，前后记 `uptime`。
- macOS 上要在图形会话里的终端跑（ssh 会话读不到钥匙串里的登录凭据，`claude -p` 会报 Not logged in）。
- 输出：`results.tsv`（每次运行一行：配置、写法、load、挡/放、由哪个 hook 挡、是否出现 skill 正文、cost）、`selftest.tsv`、每次运行的 stream-json 和 hook 调试日志行、`run.log`。
