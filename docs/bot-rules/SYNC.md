# bot 规矩：Git 唯一来源和同步（PER-106）

## 原则

- ops 仓库 main 是唯一来源。`docs/bot-rules/<skill>/` 里是什么，各落点就该是什么。
- dev-bot-rules 的内容归 dr eggbot：改内容走 PR，由 dr eggbot 定稿，Zack 批合并。
- `scripts/sync-bot-rules` 只把 main 的内容原样拷到落点，不改内容、不合并、不格式化。
- 按目录整体同步：源目录下所有文件都同步（含子目录）。dr eggbot 以后把 dev-bot-rules 拆成「核心 + 附录」时，只要文件都在 `docs/bot-rules/dev-bot-rules/` 下，脚本和目标表都不用改。新增一个 skill 目录，就在 `targets.tsv` 加一行。

## 落点清单

查的时间：2026-10-20 20:00–20:40 SGT，PER-106 工作区的 Claude Code 只读查。
「实体副本」要同步；「引用」只按名字或路径提到它，不同步，规矩改了以后按下面的提示人工核。

### box（主机名 grok-bot-vm-418519647）

10-21 起 box 不做开发（dev-bot-rules「Orca 项目与工作区」第 2 条），开发机器只剩 iMac 和 MBA。但所有 Grok Bot 仍在 box 上运行、读下表第一行这份 SKILL.md，所以 targets.tsv 的 box 行保留，照常同步。

| 落点 | 类型 | 怎么查的 / 查到什么 |
|---|---|---|
| `/home/box/agent-data/workflows/dev-bot-rules/SKILL.md` | 实体副本（同步） | `ls -la` + `sha256sum`：目录里只有这一个 SKILL.md 和 8 个 `SKILL.md.bak-*`。当前 sha256 `f12040ef…71e9ae`，和仓库 `docs/bot-rules/dev-bot-rules/SKILL.md` 一致，最后修改 10-20 19:38。所有 Grok Bot 读这一份。 |
| 7 个 `/home/box/agent-data/agents/<id>/profile.json` | 引用（不同步） | `grep -rIl dev-bot-rules /home/box/agent-data`，再逐个 `grep -c`：description 写了这个路径的是 deepvision 运维（59e92ab1）、deepvision 营销（8e369af7）、心月网站 运维（30408a29）、vllm-omni 开发（b005297a）、deepvision 广告产品（39255575）、Coding助手（c683435e）、ops 系统（a1dd2aef）。其余 4 个不是开发 bot，没有。19:45 排查记的是 8 个，复核是 7 个。 |
| `/home/box/agent-data/agents/03c3ce4a…/attachments/` 下 2 个文件（.md、.html） | 引用（不同步） | 同一次 grep 命中。这是会话附件（历史消息里的文件），不是规矩副本。 |
| Orca 自动任务 bc9ee42b「ops · 12 Linear 状态对齐」 | 引用（不同步，要人工核） | `~/.local/bin/orca automations list --json` 共 22 个任务，只有它的配置里出现 dev-bot-rules。按 19:45 的排查，它的提示词里抄了一段状态定义，不是读文件（本次只确认了命中，没逐字核那段）。**dev-bot-rules 里的状态定义改了，要人工核这段提示词。** |

### iMac（主机名 iMac）

10-21 00:00 SGT 复查（ops 系统，`ssh imac` 只读）：`~/agent-data` 不存在；`find ~ -maxdepth 6 -iname '*dev-bot-rules*'`（跳过 `~/Library`、`~/orca/workspaces`、`node_modules`、`.git`、`projects/`）：0 个。`~/orca/workspaces/ops/` 下只有 ops 仓库工作区自带的 `docs/bot-rules/dev-bot-rules/`（git 检出，跟分支走，不是副本）。结论不变：没有实体副本，targets.tsv 不加 iMac 行。


| 落点 | 类型 | 怎么查的 / 查到什么 |
|---|---|---|
| 无实体副本 | — | `find ~/.pi/agent ~/.claude -maxdepth 6 -iname '*dev-bot-rules*'`（跳过 projects/）：0 个。`grep -rIl dev-bot-rules` 查 `~/.agents`、`~/.local/bin`、`~/.orca-state/bin`、`~/.claude/{CLAUDE.md,agents,hooks,skills,settings.json,statusline-command.sh,plugins}`、`~/.pi/agent/{AGENTS.md,agents,bin,extensions,install,missions}`：0 条。`~/orca/workspaces/*/*/{AGENTS,CLAUDE}.md` 共 57 个：0 条。整棵 `~/.pi/agent`、`~/.claude` 的 grep 在 90 秒内没跑完（会话记录太多），所以改成上面这些配置目录；会话记录（`*.jsonl`、`projects/`）和 `auth.json` 没查。 |
| ops 仓库里按名字引用的文件 | 引用（跟 ops main 走） | `git grep -l dev-bot-rules origin/main`：`scripts/stuck-check.sh`、`scripts/box-load-gate.sh`、`scripts/naming-check.py`、`orca-projects.md`、`everos-mcp/MCP-WIRING-STANDARD-v2.md`、`everos-deploy/PLAN.md`、`everos-deploy/HANDOFF-coding.md`、`docs/per67/` 下 3 个。 |
| Orca 自动任务 16 个 | 无引用 | `orca automations list --json` 逐个查整条配置：0 个提到 dev-bot-rules。 |

### MBA（主机名 mba）

10-21 00:00 SGT 复查（ops 系统，`ssh mba` 只读），结论变了：**有实体副本，已加进 targets.tsv**（主机名通配 `mba`）。

| 落点 | 类型 | 怎么查的 / 查到什么 |
|---|---|---|
| `/Users/jiawenwang/agent-data/workflows/dev-bot-rules/SKILL.md` | 实体副本（同步） | `ls -la` + `shasum -a 256`：ops 系统 10-20 晚上从 box 手工拷来（目录时间 23:04，SKILL.md 文件时间 22:36，`SOURCE.txt` 写的是 23:15 同步），只读权限 `-r--r--r--`，sha256 `c517c576…0c430d2f`，是 #67 合并前的旧版，和 main（`b4610e94…7c94918b`）不一致。只要 MBA 上有人读它，就得跟 main 一致（dr eggbot 10-20 23:59）。 |
| 同目录 `SOURCE.txt`、`SHA256SUMS.txt` | 手工拷贝时留的说明和校验和（git 里没有） | `--check` 会报 `extra`，脚本只报不删。要不要留、要不要进 git 由 dr eggbot 定。`SOURCE.txt` 里写的「改规矩只改 box 原文」已经过时（现在以 ops main 为准）。 |
| `~/orca/workspaces/ops/*/docs/bot-rules/dev-bot-rules/` | git 检出（不同步） | ops 仓库工作区自带的，跟各自分支走，不是副本。 |

以下是 10-20 的查询记录（当时 `~/agent-data` 还不存在）：


| 落点 | 类型 | 怎么查的 / 查到什么 |
|---|---|---|
| 无实体副本 | — | `ssh mba` 只读：`grep -rIl dev-bot-rules` 查 `~/.pi/agent/{AGENTS.md,bin,extensions}`、`~/.claude/{CLAUDE.md,hooks,skills,settings.json}`、`~/.agents`、`~/.local/bin`、`~/.orca-state/bin`：0 条（`~/.pi/agent/agents`、`~/.claude/agents` 不存在）。`find ~/.pi ~/.claude ~/.agents -maxdepth 6 -iname '*dev-bot-rules*'`：0 个。`~/orca/workspaces/*/*/{AGENTS,CLAUDE}.md` 共 20 个：0 条。 |
| Orca 自动任务 8 个 | 无引用 | 同 iMac 的查法：0 个提到。 |

所以 `targets.tsv` 现在有 box 和 MBA 两行（10-21 加 MBA）。iMac 上跑 `sync-bot-rules --check` 会打印「本机在 targets.tsv 里没有目标」并退出 0；以后 iMac 上有了实体副本，就在 targets.tsv 加一行。

MBA 和 iMac 上的 `--apply` 只在本 PR 合并、Zack 在卡上批了以后才跑；合并前只跑 `--check`。

## 怎么同步

```
scripts/sync-bot-rules [--check|--apply] [--repo DIR] [--ref REF] [--no-fetch] [--machine NAME]
```

- 内容来源：`--repo`（默认脚本所在仓库）里 `--ref`（默认 `origin/main`，先 `git fetch origin`）的 `git show <ref>:<path>`。工作区脏不脏、在哪个分支都不影响。
- 目标表：`docs/bot-rules/targets.tsv`，也从同一个 ref 读。制表符分隔：机器、主机名通配、源目录、目标目录（绝对路径）。本机只处理主机名匹配的行；`--machine` 按机器名选行（测试用）。
- `--check`（默认，只读）：每个文件一行 `机器 | 目标路径 | 源 sha256 | 目标 sha256 | 状态`，状态是 `same`、`drift`（两边不同）、`missing`（git 里有、目标没有）、`extra`（目标有、git 里没有）。目标目录里的 `*.bak*` 不算 extra。全部 same 退出 0，否则 1，出错 2（ref 不存在、targets.tsv 不在、目标目录不存在等）。不打印文件内容。
- `--apply`：只写 drift 和 missing 的文件。drift 的旧文件先复制到**同目录**的 `<文件>.bak-YYYYMMDD-HHMM`（重名时加秒），和 box 上已有的 `SKILL.md.bak-*` 一样放法；写完重算 sha256 打印。extra 只报不删。目标目录不存在就报错退出 2，不自己建。重复跑第二次是 0 改动。
- 脚本不碰目标表以外的路径，不读 env 或密钥文件。
- `--repo` 必须是仓库根目录。指向子目录时，`git ls-tree` 按子目录解析路径，会报 `no files under ...` 并退出 2（10-21 在 MBA 上用 `~/orca/workspaces/ops/everos-deploy` 跑时就是这样：那是 `~/orca/workspaces/ops` 这个克隆下的子目录）。

上线后的用法（合并 main、Zack 批了同步以后）：dr eggbot 负责，box 上自己跑，MBA 上派 coding agent 跑。L9 固定在全新克隆里跑（`git clone` 后在克隆根目录执行），不用现成的工作区。

1. `scripts/sync-bot-rules --check`，看结果。
2. 只有 drift 是「main 比落点新」时才 `--apply`。drift 的来历先按下一节判断。

## 怎么发现不一致

不新建 routine 或 automation：

- MBA 落点：由 MBA 的「ops · 24 未推送扫描」顺带跑 `--check`。改这个线上任务另走 Zack 卡，本 PR 不改。
- box 落点：L9 同步时由 dr eggbot 跑 `--check`。

## 反方向的漂移：有人直接改了 box 上的 SKILL.md

10-20 19:29 和 19:40 就是这样改的（box 上留了 `SKILL.md.bak-20261020-1930`、`-1940`）。`--check` 报 drift 时：

1. **先别 `--apply`**。drift 只说明两边不同，不说明哪边新。用 `ls -l` 看 box 文件修改时间，和 `git log -1 -- docs/bot-rules/dev-bot-rules/` 比。
2. 如果 box 版是新改的、没进 Git：ops 系统把 box 版原样拷进一个分支（`docs/bot-rules/dev-bot-rules/`），开 PR 请 dr eggbot 审。合并后 main 和 box 一致，`--check` 回到 same。
3. 只有 main 比落点新（PR 合并了、还没同步），才跑 `--apply`。`--apply` 会先备份，但备份不等于进了 Git，不要用它代替第 2 步。
4. extra 文件（box 上多出来的、git 里没有的）同样按第 2 步处理：要的进 PR，不要的由 dr eggbot 决定删不删，脚本不删。

## 相关文件

- `docs/bot-rules/targets.tsv`：目标表。
- `scripts/sync-bot-rules`：同步和检查脚本。
- `scripts/tests/sync-bot-rules-test.sh`：测试（临时仓库 + 假目标，不碰真实落点）。
- `reports/git-source-of-truth-1020/`：PER-106 的干跑结果和密钥扫描记录。
