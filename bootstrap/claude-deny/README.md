# 禁用命令的确定性拦截（PER-89）

2026-10-20 交接第 5 项停用了 5 个插件命令：pstack 的 `poteto-mode`、`tdd`、`reflect`、`setup-pstack`，compound-engineering 的 `lfg`。本目录把这 5 个命令的拦截改成三道防线，高负载时主防线不会因为 hook 超时而放行。

S11 另加 **24 条 CE 模型调用 deny**（共 29 条 `Skill(skill:...)`），保留 `ce-code-review` 和它写报告时调用的 `ce-noslop`。名单、逐条出处、安装/回退和尚未跑的验收见 [`../claude-plugins/S11.md`](../claude-plugins/S11.md)。新增 24 条不扩展 slash hook：它们只禁模型 Skill 调用，不声称人手输入也被拦；原来的 5 个命令才有三道防线。

## 文件

| 文件 | 作用 |
|---|---|
| `settings-fragment.json` | 要合并进 `~/.claude/settings.json` 的内容：29 条 deny、1 个 `UserPromptExpansion` hook、1 个 `UserPromptSubmit` hook |
| `hooks/disabled-cmd-prompt-guard.sh` | 补充用的 `UserPromptSubmit` 脚本，只用 bash 内建命令 |
| `hook-timeout` | 两个 hook 的 `timeout`（秒）。唯一来源：`install.sh` 写入和 `--check` 核对都读它，片段里不写 timeout |
| `install.sh` | 合并、核对、卸载，幂等 |
| `tests/e2e-load.sh` | 端到端测试：隔离配置 + 真实 `claude -p` + CPU 加压 + 故障注入 |
| `tests/install-sandbox.sh` | 安装器检查：幂等、备份、卸载、备份失败、超时单一来源（含回退用例） |

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

pstack 0.15.27 的 `poteto-mode`、`tdd`、`reflect` 自己带 `disable-model-invocation: true`：模型用 Skill 工具调用时，Claude Code 先按这个字段拒绝（`cannot be used with Skill tool due to disable-model-invocation`），轮不到 deny 规则。所以 E2E 另用一份去掉该字段的 pstack 临时副本（`--plugin-dir`）单独验 deny，并配一组去掉全部 `Skill(...)` deny 的对照。插件以后去掉这个字段，deny 照样挡。`setup-pstack` 和 `lfg` 没有这个字段，直接由 deny 拒绝（`Permission to use Skill with skill:<名字> has been denied.`）。

### 为什么 deny 管不到人手输入的 slash 命令

deny 规则作用在工具调用上。人直接输入 `/name` 不经过 Skill 工具，也不触发 `PreToolUse`。官方文档（[hooks · UserPromptExpansion](https://code.claude.com/docs/en/hooks#userpromptexpansion)）：

> This event covers the path `PreToolUse` doesn't: a `PreToolUse` hook matching the `Skill` tool fires only when Claude calls the tool, but typing `/skillname` directly bypasses `PreToolUse`. `UserPromptExpansion` fires on that direct path.

E2E 的故障注入 (c) 把两个 hook 都去掉、只留 deny：模型调用照样被拒，人手输入 `/pstack:tdd` 照常展开。结果见 PR。

### UserPromptExpansion hook

- `matcher`：`^((pstack:)?(poteto-mode|tdd|reflect|setup-pstack)|(compound-engineering:)?lfg)$`。含 `^`，Claude Code 按 JavaScript 正则处理；整串锚定，不会误伤 `tdd-guide`、`superpowers:tdd`、`pstack:how`、`lfgx`。
- `command_name` 的实际取值（2026-10-20 在 MBA 用探针 hook 记 stdin 实测，Claude Code 2.1.304）：输入 `/pstack:how` 得到 `pstack:how`；输入不带前缀的 `/poteto-mode` 得到 `pstack:poteto-mode`，`command_source` 是 `plugin`。即不带前缀的写法会解析成带前缀的全名。matcher 两种都写上，以防以后版本行为变化。
- `command`：`echo 'Blocked (PER-89): ...' >&2; exit 2`。不读 stdin，不起 node、python、grep。`Blocked (PER-89)` 也是 `install.sh` 认自己条目的标记。
- `timeout` 取 `hook-timeout`（现为 5），`onFailure: "block"`（要求 Claude Code ≥ 2.1.295；三台都是 2.1.304）。官方文档（[Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails)）："With `"block"` set, a failure does what exit code 2 does on that event"。

### UserPromptSubmit 补充脚本

`disabled-cmd-prompt-guard.sh` 取代 #48 的 `block-disabled-skills.sh`：读 stdin 用 `IFS= read -r -d ''`，匹配用 `[[ =~ ]]`，不起子进程。规则和旧脚本一样：提示词开头（允许前导空白或转义换行）是这 5 个命令之一就 exit 2。

它只兜 `UserPromptExpansion` 不触发的情况。实测 `UserPromptSubmit` 在 `UserPromptExpansion` 之前跑，所以两者都在时，多数情况是它先挡下。官方文档写明它超时会放行：

> a `UserPromptSubmit` command, HTTP, or MCP tool hook that reaches its timeout is canceled and its output, including any `additionalContext`, is discarded. The prompt still reaches Claude without that context.

## 安装、核对、回滚

在 ops 仓库根目录跑。只对新起的 claude 会话生效。

```bash
bootstrap/claude-deny/install.sh --dry-run --out /tmp/settings.per89.json   # 看合并结果，不动原文件，打印 sha256
diff -u ~/.claude/settings.json /tmp/settings.per89.json
bootstrap/claude-deny/install.sh --apply       # 先备份 settings 和已有 guard，再逐文件原子写回，打印前后 sha256
bootstrap/claude-deny/install.sh --check       # 一致退出 0；不一致逐项列出，退出 1
bootstrap/claude-deny/install.sh --uninstall   # 撤掉本目录加的项，见下
```

`--settings-file <路径>`、`--hooks-dir <目录>` 可以改目标（测试用）。生成的 hook command 会绑定 `--hooks-dir` 的绝对路径（带 shell 引号），不再仍指向默认 `$HOME/.claude/hooks`。

`install.sh` 只改三处，其他键（插件、notify、Orca 的 hook 等）原样保留、顺序不变，文件保持原来的 2 空格缩进：

- `permissions.deny`：没有的才追加；
- `hooks.UserPromptExpansion`：没有带 `Blocked (PER-89)` 的条目就追加，有就换成片段里的版本；
- `hooks.UserPromptSubmit`：调 `block-disabled-skills.sh` 的那一项原位换成新脚本；已经是新脚本就更新成片段里的版本；都没有就追加。

`--apply` 和 `--uninstall` 都先计算 settings/guard 是否需要改动。有变化时，在创建 hooks 目录、覆盖 guard、删除 guard、写 settings **之前**，给 settings 和已经存在的 guard 各做一份 `<文件>.bak-<YYYYmmddHHMMSS>-<随机后缀>` 备份，逐字节比对成功后才往下写。任一备份失败则清理本轮未完成的备份，退出非 0，两份目标内容/权限不改，不创建 hooks 目录。已有同秒备份不复用、不覆盖。两份目标都没变时不写也不备份；只有 guard 改变也必须过同一备份屏障。拒绝 symlink/非普通文件目标，避免备份对象和覆盖对象不一致；请勿并发运行安装器。

这不是跨两文件的原子事务：**全部备份成功以后的**磁盘/权限故障仍可能留下部分应用，要按打印的成对备份恢复；不要把「备份失败不改目标」扩写成「任何阶段失败都自动回滚」。

`--apply` 把 settings 里调 `block-disabled-skills.sh` 的旧条目换成新脚本后，旧脚本文件还留在 `~/.claude/hooks/`。确认 settings 已不再引用它，再挪走（不直接删，要恢复就挪回来）：

```bash
grep -q block-disabled-skills ~/.claude/settings.json || { [ ! -e ~/.claude/hooks/block-disabled-skills.sh ] || mv ~/.claude/hooks/block-disabled-skills.sh ~/.claude/hooks/block-disabled-skills.sh.bak-$(date +%Y%m%d%H%M%S); }
```

`--uninstall` 撤掉片段中的 29 条 deny、`UserPromptExpansion` 条目、`UserPromptSubmit` 里的新脚本项，删掉 `~/.claude/hooks/disabled-cmd-prompt-guard.sh`；不把旧 hook 加回来。

回滚到装之前的原样：用 `--apply`/`--uninstall` 打印的**本次成对备份路径**，分别 `cp -p <settings备份> ~/.claude/settings.json` 和 `cp -p <guard备份> ~/.claude/hooks/disabled-cmd-prompt-guard.sh`。若本次安装前 guard 不存在，则恢复 settings 后移走本次新增 guard；别误用同秒其他阶段的备份。挪走过旧脚本的，把 `block-disabled-skills.sh.bak-<时间>` 挪回 `~/.claude/hooks/block-disabled-skills.sh`，否则恢复后的 settings 指向一个不存在的脚本。

改超时：只改 `hook-timeout`，再跑 `--apply`；`--check` 读同一个文件。`tests/install-sandbox.sh` 验证改成 7 后两个 hook 都变 7、`--check` 跟着变，并用一个写死 timeout 的安装器副本做回退用例（它不跟着变，检查会挂）。

## 和 bootstrap/claude-plugins 的关系

本目录和 #48 的 `bootstrap/claude-plugins/` 在同一个 PR 里合并（PER-83 + PER-89）。挡禁用命令只有本目录这一套：#48 原来的 `block-disabled-skills.sh` 已删除，`install-block-hook.sh` 改成转调 `install.sh --apply`；`pin-claude-plugins.sh` 安装时调 `install.sh --apply`，`--check` 时调 `install.sh --check`。超时只在 `hook-timeout` 一处。

`pin-claude-plugins.sh` 先写 `settings.json`（并备份），紧接着 `install.sh` 再写一次。deny 安装器即使落在同一秒也生成独立随机后缀备份，保存自己写前的精确内容；pin 的早期快照保留不动。完整 pin 回退仍以操作前整套备份为准，不能把 deny 阶段快照误认为 pin 运行前快照。

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
