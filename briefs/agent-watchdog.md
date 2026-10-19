# Task: agent-level wake-ups + stuck-check upgrade (owner Coding助手, ops)
Zack 10-13 approved. Background: a vllm Orca agent on the box died at 21:50 (API disconnect) while writing a script; no notify-run had started, the fallback 「卡住工作检查」 did not catch it, nobody knew for 2h.
1) Wrap the whole agent: dispatch template becomes `notify-run --bot <dispatching bot> --task "..." -- claude --dangerously-skip-permissions ...` so exit/crash/disconnect wakes the dispatching bot; long commands inside stay wrapped. Make sure notify-run works for this (interactive TTY passthrough, signals). Update the dispatch template in the box skill /home/box/agent-data/workflows/dev-bot-rules/SKILL.md (box path; edit via ssh/whatever access you have, or write the proposed diff to ~/orca/workspaces/ops/agent-watchdog/dev-bot-rules.diff if you cannot reach it).
2) Orca automation 「卡住工作检查」 (439cd438): check Orca workspaces on BOTH iMac and box (box = orca --environment for the box Orca runtime; find how). Treat "agent process gone but workspace not completed" as stuck. First find out exactly why it did not report the vllm box workspace PER-8-五个PR端到端-4090 for 2h; write the cause.
3) Also stuck: workspace with no new terminal output for >30 min -> wake the dispatching bot directly, no repeat wake for the same thing.
4) Simulate: one wrapped agent on box and one on iMac, kill mid-way -> confirm dispatching bot woken (use --bot coding-assistant); one workspace silent 30 min -> confirm the fallback reports it. Space webhook sends >=5s.
Report to ~/orca/workspaces/ops/agent-watchdog/RESULT.md (cause, changes, test results), then run: ~/.local/bin/notify-run --bot coding-assistant --task "agent-watchdog 完成" -- true
Do not touch other bots' workspaces except reading them.

## Correction to item 3 (replaces it)
Only check workspaces with workspace-status=in-progress; skip todo/in-review/completed/sleeping; a workspace with a running notify-run is not stuck. Among in-progress report only: a) agent at tui-idle (waiting for input) >30 min; b) agent process alive, not tui-idle, no new output >30 min and no notify-run running. Report once per workspace until it shows new activity. Simulation must also verify a sleeping/completed workspace is NOT reported.
## Known issue for item 1
Launching claude under notify-run in an Orca terminal showed an EMPTY terminal (TUI output swallowed, likely stdout piped). Fix notify-run so the wrapped agent keeps a real TTY (e.g. run child in foreground without piping, trap/wait for exit code), and prove it in the simulation.

## Addition (Zack approved): 15-min script-first check
Change 「卡住工作检查」 from hourly to every 15 min (still weekdays 08-23 SGT). Make it a pure script first (workspace status, tui-idle, last output time, notify-run process); only when the script finds a suspect, invoke Claude to double-check and send the webhook. Use the automation --precheck if it fits. Test this together with the rest.

## Addition 2 (Zack approved 10-14 00:02): per-automation model/effort + retries + .due/.ok
Numbering = ~/orca/workspaces/ops/automation-inventory/INVENTORY.md.
1. Set model/effort PER AUTOMATION (orca automations edit --extra-agent-args="--model X --effort Y"). NEVER change ~/.claude/settings.json global defaults. If Orca can't do per-task args, STOP and report.
 - #8 load-triggered cleanup, #9 stuck check: Haiku, effort low. #10 Codex fallback: effort low. (#9 = the 15-min script-first change above; model only on suspects.)
 - #1 CF usage, #2 Linear sync, #4 workspace nightly cleanup, #5 SEO weekly, #6 vllm upstream watch, #7 daily cleanup: Sonnet, medium.
 - #3 nightly regression: Sonnet, high.
 - #11 心月 nightly review: keep Opus, effort high.
2. stuck-check.sh webhook POST: backoff retry 3x; exit 3 only if all fail.
3. .due/.ok marker check for CF usage, SEO weekly, daily cleanup: fold into the existing fallback/stuck script (no new model task): overdue without .ok -> notify-run/webhook to coding-assistant.
Acceptance: trigger each automation once or dry-run, confirm from session logs the specified model was used; test webhook retry with a bad URL once; simulate a missing .ok once. Put all in RESULT.md.
