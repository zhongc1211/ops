# Orca automation inventory

Collected 2026-10-13 23:45–23:57 SGT by Claude Code (Opus 5.5) on the iMac, read-only. Owner: Coding助手. For review by dr eggbot.

Updated 2026-10-14 by Claude Code (Opus 5.5): the trigger, model, effort and enabled columns now match `orca automations list` as of 2026-10-14, after the agent-watchdog changes (`agent-watchdog/RESULT.md`). The run counts and average durations are still the 10-13 figures, measured when every Claude automation ran Opus 5.5 at xhigh.

The iMac has 11 Orca automations. Ten are enabled; Nightly regression (#3) is disabled (Zack stopped it permanently). The box has none: its Orca runtime lists zero automations, and it has no crontab or systemd. Each automation now sets its own model and effort through Orca's extra agent arguments: seven run Claude Sonnet, two Claude Haiku, one Claude Opus, and one is a Codex fallback.

All times are SGT. Every automation was created on 2026-10-11 or later, so "last 7 days" covers each one's full history (102 run records in total).

## iMac — Orca automations

| # | Name | Host | Trigger | What it does | Main model + effort | Fallback | Runs, last 7 days | Avg duration |
|---|---|---|---|---|---|---|---|---|
| 1 | CF usage watch | iMac | Daily 21:17. Precheck `cf-usage-check.sh`; the agent starts only when 24h Cloudflare usage is over threshold | Read-only investigation of which Worker / D1 / R2 / Durable Object caused the usage, via GraphQL Analytics with a read-only token.<br>Writes a report to `~/.orca-state/cf-usage/reports/`. No messages, no config changes. | Claude Sonnet 5.5 / medium | None | 3 checks, 0 agent runs (precheck exit 1 each time) | n/a |
| 2 | Linear sync | iMac | Weekdays 08:47. Precheck: `orca linear team list` succeeds | Aligns PER/FDV Linear issue status, project and assignee with PRs, worktrees and deploy state. GitHub is read-only.<br>Logs each change to `~/.orca-state/linear-sync/changes.log` and writes a daily report. | Claude Sonnet 5.5 / medium | None | 4 agent runs (2 scheduled, 2 manual) | 4m21s (3 of 4 runs; range 1m29s–7m45s) |
| 3 | Nightly regression | iMac | **Disabled** (stopped permanently by Zack). Was daily 03:17. Precheck: `npm` and `orca` on PATH | Runs full unit tests for xinyue-site and deepvision-site in throwaway detached worktrees, then checks production pages in a headless browser. vllm-omni is not tested.<br>Creates or updates a Linear issue only on failure; report in `~/.orca-state/nightly/reports/`. | Claude Sonnet 5.5 / high (set, but the automation is disabled) | None | 2 agent runs | 28m47s (2 runs) |
| 4 | Orca 工作区夜间清理 | iMac | Daily 02:17. No precheck. New worktree per run | Archives finished Orca workspaces (completed, or Linear Done/Canceled, or PR merged/closed; idle over 24h; nothing uncommitted or unpushed) and closes stale terminal tabs in permanent workspaces.<br>Report to `~/orca/workspaces/ops/workspace-cleanup/`, then `notify-run` to coding-assistant. | Claude Sonnet 5.5 / medium | None | 0 (created 10-13 23:24; first run due 10-14 02:17) | n/a |
| 5 | SEO weekly check | iMac | Mondays 08:47. Precheck `seo-weekly-precheck.sh` fetches robots.txt, sitemap.xml, llms.txt | Read-only SEO/GEO check of deepvision.sg: Search Console 28-day comparison, sitemap page spot checks, and 5 fixed WebSearch questions to see whether deepvision.sg is cited.<br>Report and raw JSON in `~/deepvision/seo-geo/<date>/`. | Claude Sonnet 5.5 / medium | None | 1 agent run | 4m16s (1 run) |
| 6 | vllm-omni upstream watch | iMac | Every 3h at :17. Precheck hashes `gh` output for 6 PRs and 1 issue; the agent starts only when the hash changed | Read-only report on new comments, reviews and CI changes on vllm-project/vllm-omni PRs #8713–#8716, #8718, #8746 and issue #8686.<br>Report in `~/.orca-state/vllm-upstream/`; writes `~/orca-alerts/vllm-upstream.flag` on substantive changes. | Claude Sonnet 5.5 / medium | None | 18 checks, 5 agent runs, 13 skipped | 2m28s (4 of 5 runs) |
| 7 | 内存与 CPU 日常清理 | iMac | Daily 04:37. Precheck `orca-due.sh` (always passes) | Runs `scripts/mem-cpu-cleanup.sh --trigger nightly`, which closes idle `claude` processes (over 24h old and idle, under 1% CPU, issue closed).<br>The agent then diagnoses memory and CPU itself and ends orphaned dev-tool processes (headless Chrome bridges, wrangler, vite and similar) unused for 12h. | Claude Sonnet 5.5 / medium | None | 2 agent runs | 2m15s (2 runs) |
| 8 | 内存与 CPU 清理（负载触发） | iMac | Every 30 min (:07, :37). Precheck `mem-cpu-cleanup.sh --pressure-check`: 5-min load over 2× cores or free memory under 25%, and over 3h since the last cleanup | Runs `scripts/mem-cpu-cleanup.sh --trigger pressure` and nothing else.<br>Reports the result in one or two sentences. | Claude Haiku 5.5 / low | None | 31 checks, 3 agent runs, 28 skipped | 1m16s (3 runs) |
| 9 | 卡住工作检查 | iMac | Every 15 min (:03, :18, :33, :48), 08:00–23:00, weekdays. Precheck `scripts/stuck-check.sh --scan` (timeout 300s) does the whole check without a model; the agent starts only when it finds a suspect, an unsent message or an error | The precheck checks in-progress task workspaces on both the iMac and the box Orca for an agent that is gone, idle at the input box for 30 min, or silent for 30 min. It also sends, without a model: work reported but not accepted after 1h (about hourly, to Coding助手), overdue `.due`/`.ok` markers, and a box-unreachable alert.<br>The agent reads each suspect's terminal screen, then runs `--send`, which wakes the dispatching bot. | Claude Haiku 5.5 / low | #10 (Codex) | 20 agent runs | 1m40s (20 runs; range 41s–2m56s) |
| 10 | 卡住工作检查（codex 备用） | iMac | Hourly at :53, 08:00–23:00, weekdays. Precheck `orca-fallback.sh stuck-check 25 60`: starts only when #9's agent was started over 25 min ago and left no success marker | Runs `scripts/stuck-check.sh` with no arguments, which checks and sends without the review step.<br>If the fallback also leaves no success marker within 60 min, the precheck writes `~/orca-alerts/stuck-check.flag`. | Codex gpt-6.1-sol / low | This is the fallback for #9 | 20 checks, 5 agent runs, 15 skipped | 2m10s (4 of 5 runs) |
| 11 | 心月夜审 | iMac | Daily 23:30. No precheck. New worktree per run from `origin/feat/xinyue-site` | Reviews the day's xinyue-site commits, PRs and Linear comments for rework, bad merges and weak verification; records rules in `docs/solutions/` and Zack's decisions in `docs/decisions.md`.<br>Pushes branch `ops/nightly-review` and opens or updates a docs-only PR. Wakes the xinyue bot only on first run or when a rule reaches 3 distinct days. | Claude Opus 5.5 / high | None | 1 agent run | 6m02s (1 run) |

IDs, in table order: `93dd232e`, `dadfc502`, `4641791b`, `5d8c9d50`, `827e1814`, `e90babeb`, `b0e92e5c`, `c498bba3`, `439cd438`, `c7692ae9`, `0ad74d58`. All run in the `ops` project workspace (`~/orca/workspaces/ops`) except #11, which runs in the xinyue-site project.

## Box (grok-bot-vm, Orca environment `grok-bot`)

Reached through the paired Orca runtime. I opened one temporary terminal on the box, ran listing commands only, and closed it.

| Source | Result |
|---|---|
| Orca automations | None. `orca automations list --environment grok-bot` from the iMac and `orca automations list` on the box both return no automations. |
| crontab | None. The `crontab` command is not installed; `/etc/crontab`, `/etc/cron.d` and `/var/spool/cron/crontabs` do not exist. `/etc/cron.daily` holds only package defaults (apt-compat, dpkg, google-chrome), and no cron daemon is running. |
| systemd timers | None. `systemctl` is not installed; PID 1 is `tini` running `pod-daemon`. |
| `at` jobs | None. `atq` is not installed. |

Two shell loops were running on the box. They are not Orca automations and use no model:

| Name | Host | Trigger | What it does | Model |
|---|---|---|---|---|
| `/workspace/ops/orca-remote/watchdog.sh` | box | Loop, every 45s; up 1d 1h when checked | Keeps the box's Orca remote server and tunnel up: restarts on a stale tunnel (public 502/530 while local is 200), after resume from pause, or after 2 unhealthy checks.<br>Re-extracts the Orca app from the saved `.deb` if app files are missing. | None (bash) |
| `watchdog.sh 31.2246826432 7500` in `…/vllm-omni/PER-8-五个PR端到端-4090/analysis/e2e` | box | Loop, every 15s; started 10-13 23:43, exits about 2h10m later | One-off PER-8 spend guard: deletes every `upacc-*` RunPod pod when run spend reaches the cap or the 7500s deadline passes. | None (bash) |

The remaining long-running processes on the box (`sand-*`, `supervise-*`, `orbitd`) belong to the VM platform.

## How the model, effort and duration figures were obtained

- Since 2026-10-14 every automation has extra agent arguments (`orca automations list` shows them as `extraAgentArgs`): `--model sonnet --effort medium` for #1, #2, #4, #5, #6, #7; `--model sonnet --effort high` for #3; `--model haiku --effort low` for #8, #9; `-c model_reasoning_effort=low` for #10; `--model opus --effort high` for #11. Orca starts Claude as `claude --dangerously-skip-permissions <those arguments> <prompt>`. `~/.claude/settings.json` was not changed and still has `effortLevel: xhigh`, which now applies only to sessions without these arguments.
- On 2026-10-14 each automation was triggered once. The model in each run's session log matched (`claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-opus-5-5`, `gpt-6.1-sol` with `effort: low`), and the effort flag was on each process command line. #3 was triggered before it was disabled.
- Before 2026-10-14 none of the 11 had extra agent arguments, so model and effort came from each agent's own defaults. The two bullets below describe how those earlier figures were read.
- Claude model: read from the session transcript of each agent run (`claude-opus-5-5` in all 36 matched runs out of 38). Claude effort: `effortLevel: xhigh` in `~/.claude/settings.json`. This is the configured value; the transcripts do not record effort per run.
- Codex model and effort: `gpt-6.1-sol` and `xhigh`, both recorded in the 4 Codex session logs. `config.toml` sets `model_reasoning_effort = "xhigh"` and no model.
- Duration: Orca records when a run starts but not when it ends. I used run start to the last entry in the matching agent session log. Runs with no matching session log are left out of the average (1 Linear sync run, 1 vllm watch run, 1 Codex run).
- Orca's token usage is unavailable for every Claude run ("No Claude usage session matched this run"). For Codex, 4 runs total 459,572 tokens.

## Things a reviewer may want to know

- Orca's `completed` status means the agent was started, not that the task succeeded. Five of the 20 primary stuck-check runs ended with the script exiting 3 because the webhook POST failed (four on 10-12 20:23–23:23 with URLError, one on 10-13 14:23 with HTTP 400). Those are the five times the Codex fallback started.
- One fallback start (10-12 20:53) has no Codex session and no usage record; its captured output is a shell prompt. Whether Codex ran that time is unknown.
- Only stuck-check has a fallback automation. CF usage watch, SEO weekly check and 内存与 CPU 日常清理 also write the `.due`/`.ok` markers in `~/.orca-state/runs/`. Since 2026-10-14 the stuck-check precheck reads them and sends one webhook to coding-assistant when a `.due` is over 60 min old with no newer `.ok`.
- #8, #9 and #10 only run a script and report a sentence or two. Until 10-13 they used the same model and effort as the analysis tasks, and #9 started an agent every hour (20 runs since 10-12 20:23). They now run at low effort, and #9 starts an agent only when its precheck finds something.

## Not covered

- iMac launchd agents (`~/Library/LaunchAgents`, for example `com.deepvision.daily-growth`, `com.worker.daily-compound`, `com.ershe.*`) are scheduled jobs outside Orca. I listed their names only and did not inventory them. The iMac user crontab is empty.
- The grok-bot side's own automations (the webhook receivers the bots run on) were not checked.
- Other root-owned schedulers on the box, if any, would not be visible to the `box` user beyond what is listed above.
