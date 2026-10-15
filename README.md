# orca-agent-wake

> **Status: testing.** Running on one macOS machine with a local mock webhook. Not yet rolled out to the second machine, and real bots stay in shadow mode until they are listed in `enabled-bots`.

Wakes the bot that dispatched an interactive coding agent (Claude Code or Pi) when the agent stops at its prompt, without relying on the agent to report on its own. Full docs to follow in this README and `docs/DESIGN.md`.
