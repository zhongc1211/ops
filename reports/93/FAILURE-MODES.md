# PR 93 失败方式清单（写代码之前列的）

演练用例名和 `rerun.sh` 里的 case 一一对应。每条断言都先在没改代码的版本上跑过一次并挂掉，证据在产物目录的 `prefail/`。

## A. orca-agent-launch 启动前检查

| 用例 | 会怎么错 | 断言 |
|---|---|---|
| L1-claude-global-ok | 全局 AGENTS 有标记句、`~/.claude/CLAUDE.md` 用 `@~/.pi/agent/AGENTS.md` 引用它，却被误拒（`~` 没展开、家目录写死成 `/Users/…`） | 退出码 0；stderr 有「启动检查：claude 指令链」和「标记句在 <沙箱>/.pi/agent/AGENTS.md」 |
| L2-claude-global-no-marker | 全局 AGENTS 删了标记句仍放行；或拒绝了但退出码不是 2；或没说缺在哪 | 退出码 2；stderr 有「应当包含标记句的文件：<沙箱>/.pi/agent/AGENTS.md」 |
| L3a-claude-ws-agents-imported | 工作区 `CLAUDE.md` 写 `@AGENTS.md`、`AGENTS.md` 有标记句，全局没有，却被误拒 | 退出码 0；标记句在 <工作区>/AGENTS.md |
| L3b-claude-ws-agents-not-imported | 把 pi 的规则套到 claude 上：工作区 `AGENTS.md` 有标记句但没被 `CLAUDE.md` 引用，Claude Code 读不到，却放行 | 退出码 2；点名 <沙箱>/.pi/agent/AGENTS.md |
| L3c-pi-ws-agents | 把 claude 的规则套到 pi 上：同样布局 pi 会直接读工作区 `AGENTS.md`，却被误拒 | 退出码 0；标记句在 <工作区>/AGENTS.md |
| L4a-import-missing-other-ok | `@` 引用的文件不存在时脚本崩溃或整条拒绝 | 退出码 0；清单里那个文件写「不存在」 |
| L4b-import-missing-global | `~/.claude/CLAUDE.md` 引用的全局 AGENTS 不存在，却放行或说不清缺哪 | 退出码 2；点名 <沙箱>/.pi/agent/AGENTS.md；清单写「不存在」 |
| L4c-marker-in-imported-file | 只看顶层文件、不展开 `@` 引用，标记句在被引用文件里却被拒 | 退出码 0；标记句在 <工作区>/docs/rules.md |
| L4d-import-cycle | 两个文件互相 `@` 引用，展开时死循环 | 20 秒内结束；退出码 2 |
| L4e-unreadable | 链上文件读不了（权限 000），被当成「不存在」跳过或放行 | 退出码 2；stderr 有「读不了」 |
| L4f-empty-chain | 链上一个文件都没有，却放行或报错不清 | 退出码 2；stderr 有「一个文件都没有」 |
| L4g-codex-global-ok | codex 的全局文件位置弄错（`~/.codex/AGENTS.md`） | 退出码 0；标记句在 <沙箱>/.codex/AGENTS.md |
| L4h-codex-missing | codex 读不到规矩却放行 | 退出码 2；点名 <沙箱>/.codex/AGENTS.md |
| L4i-reject-not-dry | 非 dry-run 拒绝后仍 exec notify-run（agent 照样起来） | 退出码 2；假 notify-run 没被调用 |

## B. install.sh --check 全局 AGENTS 三机一致

假对端用 `PATH` 里的假 `ssh`，它把沙箱目录 `peers/<主机>` 当对端的 `HOME` 执行命令。

| 用例 | 会怎么错 | 断言 |
|---|---|---|
| I1-same | 三份相同却报 FAIL；或已装文件一致时整体退出码不是 0 | 退出码 0；有「PASS  全局 AGENTS 一致」 |
| I2-differ | 有一份不同仍 PASS，或 FAIL 时不列出每台 sha | 退出码 1；有「FAIL  全局 AGENTS 不一致」和三台各自的 sha 前 12 位 |
| I3-unreachable | 连不上的对端被跳过、算通过 | 退出码 1；有「无法核对」；对端被试了 2 次 |
| I4-flaky | 第一次连不上就判 FAIL（没有重试一次） | 退出码 0；对端被试了 2 次 |
| I5-claude-no-ref | 对端 `~/.claude/CLAUDE.md` 没引用全局 AGENTS 不报 | 退出码 1；有「peer-b 的 ~/.claude/CLAUDE.md 没有引用」 |
| I6-no-peers | `WAKE_CHECK_PEERS=""` 时仍去连对端或报错 | 退出码 0；假 ssh 没被调用 |
