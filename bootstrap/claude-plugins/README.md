# Claude Code 插件锁版本（pstack + compound-engineering）

S11 当前交付与逐台安装/回退见 [S11.md](S11.md)。只支持默认配置目录或 `--home`，不支持独立 `CLAUDE_CONFIG_DIR`；不一致时在写文件之前退出 2。更新命令失败（含 timeout）即退出，不再忽略；最终 `--check` 同时核对安装记录版本和完整 `gitCommitSha`，同版本不同提交也失败。

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
2. 在 `~/.claude/settings.json` 里（内容有变时先备份成 `settings.json.bak-<YYYYmmddHHMMSS>`）：
   - `extraKnownMarketplaces` 把这两个市场改成本地目录源，`autoUpdate: false`；
   - `enabledPlugins` 打开 `pstack@cursor-plugins` 和 `compound-engineering@compound-engineering-plugin`；
   - `permissions.deny` 加 10 条规则（见下）。
3. `~/.claude/plugins/known_marketplaces.json` 同步成目录源、`autoUpdate: false`（内容有变时先备份成 `known_marketplaces.json.bak-<YYYYmmddHHMMSS>`）。
4. `~/.claude/CLAUDE.md` 没有 PER-67 那条插件授权规矩就补上（追加前先备份成 `CLAUDE.md.bak-<YYYYmmddHHMMSS>`）。
5. 跑 `../claude-deny/install.sh --apply`：加 29 条 `Skill(skill:...)` deny、`UserPromptExpansion` hook 和 `UserPromptSubmit` 补充脚本，换掉旧的 `block-disabled-skills.sh` 条目（见 [`../claude-deny/README.md`](../claude-deny/README.md)）。
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

deny 规则挡不住人（或派活文字）直接输入 slash 命令。这部分只有一套实现，在 [`../claude-deny/`](../claude-deny/README.md)（PER-89）：`UserPromptExpansion` hook（`onFailure: "block"`，超时也挡）为主，纯 bash 的 `UserPromptSubmit` 补充脚本为辅，超时只取 `../claude-deny/hook-timeout`。原来的 `block-disabled-skills.sh`（grep 版、`timeout: 30`、超时放行）已删除；`install-block-hook.sh` 只剩一个转调 `../claude-deny/install.sh --apply` 的入口。

已知绕过和 managed settings 的说明见 `../claude-deny/README.md`。

## `--check`

逐项比对并打印「一致 / 不符」：

- 两个检出的 `HEAD` 是否等于 `PSTACK_SHA` / `CE_SHA`；
- `settings.json` 的 10 条 deny、两个 `extraKnownMarketplaces`、两个 `enabledPlugins`；
- `known_marketplaces.json` 两个市场的目录源和 `autoUpdate`；
- `installed_plugins.json` 里两个插件的版本，是否等于钉的 commit 里插件清单的版本；
- `../claude-deny/install.sh --check`：29 条 `Skill(skill:...)` deny、两个 hook 条目（timeout 等于 `hook-timeout`）、`~/.claude/hooks/disabled-cmd-prompt-guard.sh` 和仓库里的一样、旧 `block-disabled-skills.sh` 条目已不在；
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
- 只想撤掉禁用命令的拦截：`bootstrap/claude-deny/install.sh --uninstall`。
- 撤掉本 PR 的代码：`git revert -m 1 <合并提交>`。
- 脚本改 `settings.json`、`plugins/known_marketplaces.json`、`CLAUDE.md` 前都自动备份成同目录的 `<文件>.bak-<YYYYmmddHHMMSS>`（内容没变就不写也不备份；同一秒已有备份不覆盖；备份失败就退出、不改）。回滚：`cp -p ~/.claude/settings.json.bak-<时间> ~/.claude/settings.json`，另两个文件同理。
