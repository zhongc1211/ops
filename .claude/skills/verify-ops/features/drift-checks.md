# 漂移检查（各种 --check）

ops 有几处「装出去的东西和仓库不一致」的只读检查：叫醒脚本装到 `~/.local/bin` 的副本、bot 规则 skill 的实体副本、迁移任务生成的 prompt、Claude 插件的钉版本。干净时退出码 0，有漂移时非 0，并在输出里指出是哪一项。

## Sub-features

- `DC1` `wake/install.sh --check`：沙箱 HOME 装一遍后 0，且整行是 `PASS  全局 AGENTS 一致（3 台：<机器>=<sha> …）`：台数写死（本机是 imac、mba、box 之一时 3 台，否则 4 台），每台的 sha 都等于沙箱 AGENTS.md，对端被悄悄少探一台时这条会挂；假对端的全局 AGENTS 改一行后 1（`FAIL  全局 AGENTS 不一致`）；改回去，再往已装的 `notify-run` 末尾加一行后 1，输出 `不同  …/.local/bin/notify-run`。
- `DC2` `scripts/sync-bot-rules --check`：沙箱目标目录 `--apply` 后 0（至少 1 行 `same`）；改一个文件、加一个多余文件后 1，分别是 `drift` 和 `extra`。
- `DC3` `automations/migration-1020/make-prompts.py --check`：对被测目录 0（`up to date`）；在沙箱副本里改一个已提交的 prompt 后 1，输出 `<文件> differs from the generated version`。
- `DC4` `bootstrap/claude-plugins/pin-claude-plugins.sh --check --home <沙箱 HOME>`：沙箱装好后 0（`全部一致。`）；从沙箱 settings.json 删掉 `Skill(pstack:tdd)` 这条 deny 后 1，输出 `不符  settings.json deny Skill(pstack:tdd)`。

## How to get to it (user POV)

- 部署后核对：`wake/install.sh --check`、`bootstrap/claude-plugins/pin-claude-plugins.sh --check`。
- bot 规则同步前后：`scripts/sync-bot-rules --check`（默认 ref origin/main，按本机 host 选 `docs/bot-rules/targets.tsv` 里的行）。
- 改了迁移 prompt 规则后：`python3 -I automations/migration-1020/make-prompts.py --check`。

## Driving it with verify.sh

Preconditions: 沙箱 HOME；沙箱全局 AGENTS 和假 ssh（`launch` 写好，DC1 用）；本机 `~/.claude/pinned-marketplaces/cursor-plugins` 和 `compound-engineering-plugin` 两个 git 仓库存在且含钉的 commit（DC4 用，缺了这一项记 skipped）。

- 跑：`bash .claude/skills/verify-ops/verify.sh run drift-checks`（约 10 秒）。
- DC1：`<被测目录>/wake/install.sh`（HOME=沙箱）装，再 `--check`。对端是默认的 imac、mba、box 去掉本机，`ssh` 解析到 `$SB/bin/ssh`，读 `$SB/peers/<机器>`。
- DC2：`git clone --local` 被测仓库到 `$SB/repo-clone`，在克隆里给 `docs/bot-rules/targets.tsv` 加一行 `verify	*	docs/bot-rules/dev-bot-rules/	$SB/bot-rules-target` 并提交，然后 `<被测目录>/scripts/sync-bot-rules --repo $SB/repo-clone --ref HEAD --no-fetch --machine verify --apply|--check`。
- DC3：干净用例直接跑被测目录里的脚本（只读）；漂移用例 `cp -R automations/migration-1020 $SB/mp`，改 `prompts/` 下排序第一个 `.prompt.md`，跑 `$SB/mp/make-prompts.py --check`。
- DC4：先预检：两个仓库都在，且 `git -C <仓库> cat-file -e <钉的 commit>^{commit}` 成功（commit 取自 `pin-claude-plugins.sh` 的 `PSTACK_SHA`、`CE_SHA`）；不满足记 skipped。预检过了，两个插件仓库从本机 `git clone --shared` 进沙箱，沙箱 `installed_plugins.json` 按钉的版本和 commit 预写，跑一次安装模式（插件已是钉的版本 → 不调 `claude plugin`，最后自己 exec `--check`），再单独 `--check`。

## Gotchas

- `sync-bot-rules` 的目标表只有 box 和 MBA 的行，目标是那两台机器上的绝对路径，本机 `--check` 会报「没有目标」。所以在沙箱克隆里加一行指向沙箱目录；被测的是 checkout 里的脚本，表来自克隆的 HEAD。
- `make-prompts.py --check` 比的是脚本所在目录里的已提交文件，没有「换目录」的参数；漂移只能在复制出来的目录里造。
- `pin-claude-plugins.sh` 安装模式在插件版本不对时会调真的 `claude plugin marketplace update / install`（联网、改 `~/.claude`），而且仓库不在时会从 GitHub clone。verify 预写 `installed_plugins.json`（这是 `claude plugin install` 的产物，属于外部 CLI 边界）并预放本地克隆，让它走「已是钉的版本，跳过 claude plugin update」那条路。
- 本机没有那两个插件仓库或缺钉的 commit 时，DC4 记 skipped 并在报告里列出原因，不当通过：离线做不出干净状态，也不去联网 clone，而且这说的是这台机器没准备好，不是被测脚本有问题，报失败会盖住真失败。预检过了之后 DC4 的失败仍然是失败。最后一行的 `（skipped N）` 能看出这一项没跑；N 大于 0 而本机本该有插件仓库时，先查预检。读不到钉的 commit（变量改名、格式变了）算失败，不算缺前置。
- `install.sh --check` 还核对各台全局 AGENTS，对端走 ssh。沙箱 HOME 改不了 ssh 读的配置，不换掉 ssh 就会连到真机器（10-30 main 上的跑次真的连了），而且本机没有这个文件时干净用例必挂。所以用假 ssh 和 `$SB/peers/`，检查本身不关；真机器上三台是否一致，verify-ops 不证明，线上核对见 SKILL.md「没覆盖的入口」。
- `pin-claude-plugins.sh` 见到 `CLAUDE_CONFIG_DIR`（且不等于 `$HOME/.claude`）就退出码 2、报「暂不支持独立 CLAUDE_CONFIG_DIR」。Ubuntu 的 Orca 终端里设了这个变量，verify.sh 开头会 unset，沙箱 HOME 用自己的 `.claude`。
- `wake/install.sh` 有 `~/.pi/agent/extensions/` 时还会装 Pi 扩展；沙箱 HOME 里没有这个目录，所以只核对 6 个脚本。
