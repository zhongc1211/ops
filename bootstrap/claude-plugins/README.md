# Claude Code 插件锁版本（pstack + compound-engineering）

新机器或要核对时，在 ops 仓库根目录跑：

```bash
bootstrap/claude-plugins/pin-claude-plugins.sh            # 安装 / 改到钉的版本（可重复运行）
bootstrap/claude-plugins/pin-claude-plugins.sh --check    # 只比对，不写；全部一致退出 0，任何一项不符退出 1
bootstrap/claude-plugins/pin-claude-plugins.sh --home /tmp/sandbox   # 装进别的 HOME（沙箱测试）
```

装完只对新起的 claude 会话生效，正在跑的会话不受影响。

## 钉的版本

写在 `pin-claude-plugins.sh` 顶部：

| 插件 | 常量 | commit | 版本 |
|---|---|---|---|
| pstack（github.com/cursor/plugins） | `PSTACK_SHA` | `88d47514b82e7c44f00f2b2a72ff6dd12158038c` | 0.15.29 |
| compound-engineering（github.com/EveryInc/compound-engineering-plugin） | `CE_SHA` | `2e41b4490a37f53db0beb6d4904618da9af2f559` | 3.31.0 |

上一版 pstack 是 `0148b78c56c72a1b8412055913c79f767095b217`（0.15.27），2026-10-20 交接第 5 项在 iMac、box、MBA 上装的就是它。0.15.29 在 PER-83 里过了两项兼容检查（`/verify-dv-site` 和 `/wake-tla-verify`），结果见 PR 描述。

## 脚本做什么

1. 把两个插件仓库克隆到 `~/.claude/pinned-marketplaces/<名字>`，`git checkout --detach <commit>`。
2. 在 `~/.claude/settings.json` 里：
   - `extraKnownMarketplaces` 把这两个市场改成本地目录源，`autoUpdate: false`；
   - `enabledPlugins` 打开 `pstack@cursor-plugins` 和 `compound-engineering@compound-engineering-plugin`；
   - `permissions.deny` 加 10 条规则（见下）。
3. `~/.claude/plugins/known_marketplaces.json` 同步成目录源、`autoUpdate: false`。
4. `~/.claude/CLAUDE.md` 没有 PER-67 那条插件授权规矩就补上。
5. 跑 `install-block-hook.sh`：把 `block-disabled-skills.sh` 装到 `~/.claude/hooks/`，在 `settings.json` 的 `UserPromptSubmit` 加一条 `timeout: 30`（已有就只把 timeout 改成 30）。
6. `claude plugin marketplace update` 两个市场，再 `claude plugin install/update` 两个插件。检出没切 commit、已装版本也对时跳过这一步（它每次都会改 `known_marketplaces.json` 的 `lastUpdated`）。

原有的其他设置不动；重复跑不改任何文件。

## 为什么用本地目录源 + detached + autoUpdate false

- 用 GitHub 源时，Claude Code 启动或 `plugin update` 会拉市场最新 commit，插件版本跟着上游走，三台机器很快就不一样。
- 目录源指向本机一个 git 检出，Claude Code 只读这个目录里的内容，不去网上拉。
- 检出用 detached HEAD 停在指定 commit，不跟任何分支；`git pull` 不会误把它往前带。
- `autoUpdate: false` 关掉 Claude Code 对这个市场的自动更新，双保险。
- 版本只在改脚本顶部常量再重跑时才变，变更都在 git 历史里。

## 10 条 deny 规则

`permissions.deny` 里，每个 skill 两条（不带参数、带参数）：

```
Skill(pstack:poteto-mode)          Skill(pstack:poteto-mode *)
Skill(pstack:tdd)                  Skill(pstack:tdd *)
Skill(pstack:reflect)              Skill(pstack:reflect *)
Skill(pstack:setup-pstack)         Skill(pstack:setup-pstack *)
Skill(compound-engineering:lfg)    Skill(compound-engineering:lfg *)
```

它们挡的是模型自己调用 Skill 工具。这 5 个命令是 2026-10-20 交接第 5 项停用的；背后的规矩是 `CLAUDE.md` 里那条 PER-67：插件流程里的 push、开 PR、合并、部署按派活授权，测试按「测试规矩」（以 E2E 为准），不按插件的 tdd。

## hook：挡人手输入

deny 规则挡不住人（或派活文字）直接输入 slash 命令。`block-disabled-skills.sh` 是 `UserPromptSubmit` hook：提示词开头是下面任何一个就退出 2，Claude Code 丢掉这条提示并显示原因：

- `/poteto-mode`、`/tdd`、`/reflect`、`/setup-pstack`，可带 `pstack:` 前缀；
- `/lfg`，可带 `compound-engineering:` 前缀。

只看提示词开头，命令写在句子中间不挡；其他 pstack 命令（如 `/pstack:how`）照常。

hook 超时会放行（Claude Code 照常处理这条提示，不挡），所以给 30 秒。`install-block-hook.sh` 对已有条目也会把 `timeout` 改成 30。

已知绕过（都要人有意去做）：

- `claude --settings '{"disableAllHooks":true}'` 关掉所有 hook；
- `claude --setting-sources project,local`（去掉 user）不读 `~/.claude/settings.json`，hook 和 deny 规则都不生效；
- 直接改 `~/.claude/settings.json`。

要彻底挡住只能写 managed settings（macOS `/Library/Application Support/ClaudeCode/managed-settings.json`，Linux `/etc/claude-code/managed-settings.json`），要 sudo，本目录不做。

## `--check`

逐项比对并打印「一致 / 不符」：

- 两个检出的 `HEAD` 是否等于 `PSTACK_SHA` / `CE_SHA`；
- `settings.json` 的 10 条 deny、两个 `extraKnownMarketplaces`、两个 `enabledPlugins`、hook 条目（只有一条且 `timeout` 是 30）；
- `known_marketplaces.json` 两个市场的目录源和 `autoUpdate`；
- `installed_plugins.json` 里两个插件的版本，是否等于钉的 commit 里插件清单的版本；
- `~/.claude/hooks/block-disabled-skills.sh` 是否和本目录的一样；
- `CLAUDE.md` 是否有 PER-67 规矩。

任何一项不符退出 1。不写文件，可以随时在线上机器跑。

## 升级

1. 找到新 commit，在候选版本下跑兼容检查，不改线上：
   `claude --settings '{"enabledPlugins":{"pstack@cursor-plugins":false}}' --plugin-dir <新检出>/harness/pstack/claude-code`
   （PER-83 跑的是 `/verify-dv-site` 和 `/wake-tla-verify`）。
2. 过了就改 `pin-claude-plugins.sh` 顶部常量，开 PR，写明兼容检查结果。
3. 合并后在每台机器跑 `pin-claude-plugins.sh`，再跑 `--check` 确认退出 0。

## 回滚

- 把顶部常量改回上一版（pstack `0148b78c56c72a1b8412055913c79f767095b217`）重跑脚本，或者 `git revert` 改常量的提交后重跑。脚本会把检出切回旧 commit 并 `claude plugin update`。
- 只想关 hook：从 `~/.claude/settings.json` 的 `hooks.UserPromptSubmit` 删掉 `block-disabled-skills.sh` 那条，或把 `~/.claude/hooks/block-disabled-skills.sh` 换成只有 `exit 0` 的版本。
- 脚本改 `settings.json` 前不做备份；要留底先自己 `cp ~/.claude/settings.json ~/.claude/settings.json.bak-$(date +%Y%m%d%H%M)`。
