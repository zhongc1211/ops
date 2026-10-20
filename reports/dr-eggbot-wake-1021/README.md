# dr-eggbot 叫醒接入：stuck-check 映射检查（PR #70）

- 跑的 commit：head `3a466f9a2a4cfb739cdb47dc07d96cdcda47a41c`；base origin/main `a1d9a68f47e8f6cccd5d06b3beb3ccdc7a5162a2`（`git show origin/main:scripts/stuck-check.sh` 存到 scratch 里跑）。之后的提交只加了这份报告。
- 环境：box（grok-bot-vm），2026-10-21 01:04–01:06 SGT。没读、没打印任何 webhook env；webhook 目录只 stat 了文件名、大小和 mtime。

## 1. dry-run（`STUCK_NO_SEND=1 bash scripts/stuck-check.sh --dry-run`）

box 上原来没有 `~/.orca-state/stuck-check`，但脚本启动时不管什么模式都会 `os.makedirs(STATE_DIR)`。为了不在 box 上新建线上状态目录，两次运行都加了 `STUCK_STATE_DIR=<scratch 空目录>`。

| | head | base |
|---|---|---|
| 退出码 | 4（脚本出错） | 4（脚本出错） |
| 出错位置 | `main` → `hist_phase`：`KeyError: 'phases'` | 同左（行号差 1，就是 BOT_SLUG 多出来的那一行） |
| STATE_DIR 里写了什么 | 什么都没写（只有空目录） | 什么都没写 |
| 家目录状态（`snap-*.tsv`） | 只变了本会话自己的 orca-wake 文件（`sessions/claude-1cb789e1….json` 和 `wake.log` 末尾一行，是 01:05:00 本会话 UserPromptSubmit hook 写的），stuck-check 没写 | 没变 |
| POST | 没发（崩之前没走到发送；dry-run 也只走 `recheck --list`） | 没发 |

原因（base 上就有，PER-82 `f6408d0` 起）：dry-run 时 `hist_begin()` 直接返回，`HIST` 一直是 `{}`；扫完第一类后 `HIST["plan"] = plan` 让 `HIST` 变成非空、但没有 `phases` 键，下一次 `hist_phase()` 就报 KeyError。所以 `--dry-run` 现在每次扫完第一类就崩，第二类、due 对账、发送预览都跑不到。这个 PR 不修；要修的话另开一个，比如在 `hist_phase` 里先判断 `DRY` 再返回。

另外，box 上没有 `~/orca/workspaces/ops/orca-projects.md`，所以这次 dry-run 一开始就报「映射文件读不到」，bot 一律记成「未映射」。也就是说，在 box 上跑 dry-run 本身证明不了映射，映射靠第 2 节。

## 2. 映射检查（`map_check.py`）

`map_check.py` 用 `ast` 从 stuck-check.sh 内嵌的 python 里取出原样的 `BOT_SLUG`、`load_mapping`、`bot_for`、`due_bot` 和用到的正则，再对样例 `sample-orca-projects.md`（Bot 列写 `dr eggbot` / `ops 系统` / `Coding助手` / `心月网站 运维`）和样例 Linear issue 跑 `due_bot`。这是对解析函数的单独检查，不是 E2E。

```
python3 -I map_check.py <stuck-check.sh> sample-orca-projects.md ~/.config/grokbot/webhooks
```

| 样例 | head | base |
|---|---|---|
| orca-projects 行 `dr eggbot`（PER-901） | `dr-eggbot`，`dr-eggbot.env` 存在 | `dr eggbot`，没有对应 env 文件 → bot_cfg 改发 coding-assistant |
| `ops 系统`（PER-902） | `ops-system` | `ops 系统`（同上，改发 coding-assistant） |
| `Coding助手`（PER-903） | `coding-assistant` | `Coding助手`（同上，结果仍是 coding-assistant） |
| `心月网站 运维`（PER-904，对照） | `xinyue` | `xinyue` |
| 描述「负责 bot：dr-eggbot」 | `dr-eggbot` | `dr-eggbot` |
| 描述「负责 bot：dr eggbot」 | `dr`（正则不带空格） | `dr` |

原始输出：`map-check.out`。

## 文件

- `dryrun-head.out` / `dryrun-base.out`，`.start` / `.rc` 是开始和结束的时间、退出码
- `snap-{before,after}-{head,base}.tsv`：前后状态快照；`statedir-*.tsv` 是 STATE_DIR 的内容
- `map_check.py`、`sample-orca-projects.md`、`map-check.out`
