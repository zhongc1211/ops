# agent-watchdog: result

Done 2026-10-14 00:00–01:40 SGT by Claude Code (Opus 5.5) on the iMac, for brief `briefs/agent-watchdog.md` including both additions. Owner: Coding助手.

Everything in the brief is in place and live. A real workspace Sleep could not be tested, and the live automation has not yet had a scheduled run; both are under "Not tested / limits".

## Why PER-8 was not reported for 2 hours

Source: `~/.orca-state/stuck-check/stuck-check.log`. The agent in box workspace `PER-8-五个PR端到端-4090` died at 21:50.

| Check | What happened |
|---|---|
| 21:23 | Agent still working. Nothing to report. |
| 22:24 | The box Orca query failed with `remote_runtime_unavailable`. The script logged it, skipped every box workspace and exited 0. 12 of the 24 logged checks had failed the same way. Even with the box reachable, the 1-hour threshold would not have fired 34 minutes after the stop. |
| 23:23 | The script did see PER-8 as stopped, then dropped it: `跳过 … PER-8 在别的工作区还在做或已报，视为任务已迁走`. The iMac workspace `PER-8-8714-rebase放出` has the same Linear card (PER-8, in-review), and the rule treated the card as alive elsewhere. |
| after 23:23 | Schedule was hourly, weekdays 08–23. The next check would have been 08:23 and would have been dropped by the same rule. |

So there were three causes: no retry on a box query failure, a rule that suppressed a stopped agent when another workspace shared its Linear card, and an hourly check with a 1-hour threshold. Separately, nothing wrapped the agent process, so its exit woke nobody.

## What changed

### 1. notify-run can wrap a whole agent

`~/.local/bin/notify-run` on the iMac and `/home/box/.local/bin/notify-run` on the box (same file, sha256 `dc1bf870…`; previous version kept next to it as `notify-run.bak-20261014`).

- When stdout is a terminal, the command now uses the terminal directly instead of pipes, so Claude's TUI displays and takes input. `--tty` / `--no-tty` force either mode. In this mode no output is captured; `log_tail` says so.
- This was the cause of the empty terminal: the old version always piped stdout and stderr through `tee`.
- Ctrl-C reaches the wrapped command. Closing the terminal (HUP), TERM and a crash of the command all still send the webhook.
- The webhook POST is retried: 3 tries, 20 s then 45 s apart.
- When stdout is not a terminal (inside an agent's Bash tool) behaviour is unchanged.

Dispatch template, now in the box skill `/home/box/agent-data/workflows/dev-bot-rules/SKILL.md`:

```
notify-run --bot <派活的 bot> --task "<Linear 编号> <简述>：agent 进程退出了" -- claude --dangerously-skip-permissions ...
```

I edited the skill on the box through an Orca terminal (backup `SKILL.md.bak-20261014-watchdog` in the same directory, checksum verified after the write). The diff is in `agent-watchdog/dev-bot-rules.diff`. Three places changed: the launch rule, the fallback description, and a line saying long commands inside a wrapped agent still need their own notify-run.

### 2. 「卡住工作检查」 (439cd438) is now a script-first check every 15 minutes

- Schedule: `3,18,33,48 8-23 * * 1-5` SGT (was `23 8-23 * * 1-5`).
- Precheck: `stuck-check.sh --scan`, timeout 300 s. The script does the whole check without a model. It exits 1 when nothing is found, and Orca skips the run. It exits 0 only when it has a suspect, an unsent message, or an error of its own.
- Agent (Haiku, effort low): runs `--list`, reads each suspect's terminal screen, then `--send`, with `--dismiss S<n>=reason` for any it rules out. The new prompt is in `agent-watchdog/automation-prompt-439cd438.txt`.
- Codex fallback (c7692ae9): prompt updated to match (`automation-prompt-c7692ae9.txt`). It runs the script with no arguments, which sends without review.

`scripts/stuck-check.sh` was rewritten (old live copy: `agent-watchdog/stuck-check.sh.before-20261014`). It now checks four things.

**Stuck agents** (every run, both the iMac and the box). Only task workspaces with workspace-status `in-progress`. `todo`, `in-review`, `completed` and sleeping are skipped. A workspace with a notify-run running a long command is skipped; the notify-run that wraps the agent itself does not count. Three cases:

| kind | Meaning | Threshold |
|---|---|---|
| `agent_gone` | No agent process in the workspace, terminal still open | quiet for 10 min |
| `agent_idle` | Agent sitting at the input box | 30 min |
| `agent_silent` | Agent process alive, not at the input box, no terminal output | 30 min |

Each one goes straight to the dispatching bot's webhook (`~/.config/grokbot/webhooks/<bot>.env`, mapped through `orca-projects.md`; bots without a file go to coding-assistant). Payload: `{bot, task, worktree, status:"stuck", kind, note, machine, source:"stuck-check"}`. A workspace is reported once, and again only after the agent does something new. Workspaces created by an automation run are never reported.

Process information comes from a new helper, `~/.local/bin/agent-probe` (installed on both hosts). On the box the script runs it in a temporary Orca terminal and closes it.

**Reported but not accepted** (about once an hour, unchanged in meaning): `completed` / `in-review` workspaces nobody has accepted after 1 hour, merged into one POST to Coding助手.

**Other automations' `.due` / `.ok` markers** (every run): `cf-usage`, `seo-weekly`, `mem-cpu-cleanup`. A `.due` newer than its `.ok` for over 60 minutes sends one webhook to coding-assistant.

**Box unreachable**: each box query is retried 3 times, 8 s apart. Two consecutive failed checks send one webhook to coding-assistant. During this task I polled the box every 15–25 s for 90 minutes: 21 of 216 polls failed, never two in a row long enough to defeat the retry.

Webhook POSTs are spaced at least 6 s apart and retried 3 times (5, 15, 45 s). The script exits 3 only when all tries fail; the unsent message stays queued and goes out on the next run.

The "任务已迁走" rule is gone.

### 3. Model and effort per automation

Set with `orca automations edit <id> --extra-agent-args=…`. Orca accepted it for all 11. `~/.claude/settings.json` was not touched (still `effortLevel: xhigh`, last modified 10-12 18:28).

## Test results

### Wrapped agent killed mid-way

| Host | What I did | Result |
|---|---|---|
| iMac | Started `notify-run --bot coding-assistant … -- claude --dangerously-skip-permissions --model haiku …` in an Orca terminal. The TUI rendered and accepted a prompt. Killed the claude process at 00:15:22. | `webhook bot=coding-assistant status=failed exit_code=143 http=200 第1次` |
| box | Same, in a temporary box workspace. TUI rendered (trust prompt, then the reply). Killed at 00:18:35. | `webhook bot=coding-assistant status=failed exit_code=143 http=200 第1次` |

Also in real Orca terminals on the iMac: Ctrl-C gave `killed 130`, closing the terminal gave `killed 143`, `kill -9` of the command gave `failed 137`. Each sent its webhook.

### Fallback on silent and idle workspaces

Five temporary workspaces, real 30-minute thresholds, scan at 01:06, sent to coding-assistant at 01:07 (HTTP 200 ×3, 7–8 s apart):

| Workspace | State | Reported? |
|---|---|---|
| iMac `wd-sim-idle` | in-progress, agent at the input box for 71 min | Yes, `agent_idle` |
| iMac `wd-sim-silent` | in-progress, agent process frozen with SIGSTOP for 60 min | Yes, `agent_silent` |
| box `wd-sim-box` | in-progress, wrapped agent killed 49 min earlier, shell left open | Yes, `agent_gone` |
| iMac `wd-sim-completed` | completed, agent idle | No |
| iMac `wd-sim-notifyrun` | in-progress, agent running `notify-run … sleep 3000` | No while notify-run ran (checked at 00:19 with shortened thresholds). It had ended by 01:06, and the workspace was not yet 30 min idle. |

Follow-up checks:

- A second scan right after sending reported nothing.
- After a new agent was started in `wd-sim-idle` and went idle, it was flagged again. A workspace with no new agent activity was not.
- `--dismiss` drops a suspect without a POST, and it is not raised again.
- An in-progress workspace with all terminals closed is skipped (this is how a slept workspace looks; see limits).

### The live automation, end to end

At 01:21 I ran the live `--scan` by hand, then triggered automation 439cd438. Haiku listed 5 suspects, read all five screens (two of them twice, 20 s apart), dismissed none, and sent them. All five POSTs returned 200. These were real stale workspaces, so three bots were woken at 01:23–01:24:

- xinyue: `心月-PER-46-泡泡砰砰核心玩法`, agent gone
- deepvision-ads: box `fdv-53-compare`, agent gone
- vllm-omni: box `PER-7-review-导入挪顶部`, agent gone
- coding-assistant: `ops-自动任务模型清单` and `ops-notify-run-收尾测试`, agents idle

The Codex fallback run at 01:25 found nothing new and sent nothing.

### Precheck under the scheduler

I created a temporary automation with the same precheck (`stuck-check.sh --scan`, timeout 300 s), scheduled for 01:32, and removed it afterwards. Orca ran the precheck in 37 s, it exited 1 (nothing new to report), and the run was recorded as `skipped_precheck` with no agent started. The earlier hand-run scan that included the hourly part took 92 s.

### Webhook retry and missing `.ok`

| Test | Result |
|---|---|
| stuck-check with a bad URL (`http://127.0.0.1:9`) | 4 attempts (first try + 3 retries), then exit 3. 78 s. |
| stuck-check against a test server returning 400 twice, then 200 | Delivered on the 3rd attempt, exit code not 3. |
| Missing `.ok`: `seo-weekly.due` 2 h old with an older `.ok`, in a test directory | One webhook, `kind: automation_no_ok`. Not repeated on the next run. A fresh `.ok` clears it. A `cf-usage.due` with no `.ok` at all is reported too. `mem-cpu-cleanup` with `.ok` newer than `.due` is not. |
| notify-run against a test server returning 400 twice, then 200 | Delivered on the 3rd try after 65 s. |

### Model per automation

I triggered each automation once with `orca automations run`. Model is from the session log of that run; effort is from the process command line, because Claude's session logs do not record effort.

| # | Automation | Command line | Model in session log |
|---|---|---|---|
| 1 | CF usage watch (93dd232e) | `--model sonnet --effort medium` | claude-sonnet-5-5 |
| 2 | Linear sync (dadfc502) | `--model sonnet --effort medium` | claude-sonnet-5-5 |
| 3 | Nightly regression (4641791b) | `--model sonnet --effort high` | claude-sonnet-5-5 |
| 4 | Orca 工作区夜间清理 (5d8c9d50) | `--model sonnet --effort medium` | claude-sonnet-5-5 |
| 5 | SEO weekly check (827e1814) | `--model sonnet --effort medium` | claude-sonnet-5-5 |
| 6 | vllm-omni upstream watch (e90babeb) | `--model sonnet --effort medium` | claude-sonnet-5-5 |
| 7 | 内存与 CPU 日常清理 (b0e92e5c) | `--model sonnet --effort medium` | claude-sonnet-5-5 |
| 8 | 内存与 CPU 清理（负载触发） (c498bba3) | `--model haiku --effort low` | claude-haiku-5-5 |
| 9 | 卡住工作检查 (439cd438) | `--model haiku --effort low` | claude-haiku-5-5 |
| 10 | 卡住工作检查（codex 备用） (c7692ae9) | `-c model_reasoning_effort=low` | gpt-6.1-sol, `effort: low` (Codex logs record it) |
| 11 | 心月夜审 (0ad74d58) | `--model opus --effort high` | claude-opus-5-5 |

## Not tested / limits

- **The live automation's own scheduled run.** A manual `orca automations run` skips the precheck, so automation 439cd438 first runs its precheck on schedule at 08:03 today. I tested the same precheck under the scheduler with a temporary automation (below), not on 439cd438 itself. The path where a scheduled precheck exits 0 and then starts Haiku was tested only in two halves: the scan by hand, the agent by manual trigger.
- **A real Sleep.** Orca's CLI cannot sleep a workspace and does not mark one as sleeping. The script treats an in-progress workspace with no connected terminal as sleeping and skips it. Consequence: if every terminal of an in-progress workspace is closed, the check stays quiet. The notify-run wrapper covers that case, because closing the terminal sends its webhook.
- **`agent_silent` means no terminal output.** Claude's spinner and timer count as output, so this fires for a frozen or hung agent, not for one waiting on a long tool call. When Orca has no agent record for a workspace, the script cannot tell which terminal holds the agent, and output in any terminal of that workspace restarts the 30 minutes.
- **Two idle simulation agents exited on their own at 01:09:39.** I did not find the cause. The logs of the two cleanup runs I had triggered show they closed no agent. It did not affect the results above, which were taken at 01:06–01:07.
- First reports for workspaces Orca has no agent record for can take one extra check, because the script has to see the screen unchanged across two runs.
- A notify-run killed with `kill -9` sends nothing. That is the case the 15-minute check covers.

## Side effects of the tests

- coding-assistant received test webhooks: the two wrapped-agent kills, three simulated stuck reports at 01:07, two real idle reports at 01:23, and one merged "not accepted" report (2 items) at 01:22.
- Triggering every automation once meant each did its normal job once more tonight: Linear sync, nightly regression, both cleanups, SEO check, CF usage report, vllm upstream report, the first run of Orca 工作区夜间清理, and a second 心月夜审 run.
- All simulation workspaces, branches and terminals are removed (iMac and box).

## Files

- Live: `scripts/stuck-check.sh` in the main `ops` checkout (uncommitted there, as it already was), `~/.local/bin/notify-run`, `~/.local/bin/agent-probe`, and the same two under `/home/box/.local/bin/`.
- Source: worktree `ops-agent-整体唤醒与卡住检查`, `scripts/notify-run`, `scripts/agent-probe`, `scripts/stuck-check.sh`. Committed on 10-14, see "Wrap-up" below.
- Log: `~/.orca-state/stuck-check/stuck-check.log`. State: `agents.json`, `pending.json`, `track.json`, `notified.json` in the same directory.

## Wrap-up (2026-10-14, requested by Coding助手)

Done by Claude Code (Opus 5.5). Both commits are local, on branch `zack/ops-agent-整体唤醒与卡住检查` in worktree `ops-agent-整体唤醒与卡住检查`. Nothing was pushed; the `ops` repo has no remote configured.

| Commit | Files |
|---|---|
| `ad224a2` feat(ops): agent-watchdog — whole-agent notify-run wrap + 15-min script-first stuck check | `scripts/notify-run` (new), `scripts/agent-probe` (new), `scripts/stuck-check.sh` (rewritten). Same content as the live copies. |
| `82ee5d9` docs(ops): automation inventory — current model, effort and schedule per automation | `automation-inventory/INVENTORY.md` (new in git) |

`INVENTORY.md` was updated in place at `~/orca/workspaces/ops/automation-inventory/INVENTORY.md` and the same file was committed on the branch. It now matches `orca automations list`: model and effort per automation, #9 every 15 minutes with the `--scan` precheck, #10 at effort low, and #3 Nightly regression marked disabled. Run counts and average durations are still the 10-13 figures.

Two things to know when this branch is merged into `main`: the main checkout has `automation-inventory/` as an untracked directory and `scripts/stuck-check.sh` as an uncommitted modification. Both are identical to the committed versions, but git will refuse the merge until those local copies are removed or committed there.
