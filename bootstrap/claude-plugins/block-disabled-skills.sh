#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook (handover item 5, 2026-10-20).
# Blocks prompts that a human (or a dispatch text) starts with a disabled plugin command:
#   /poteto-mode /tdd /reflect /setup-pstack (optionally pstack:-prefixed) and /lfg (optionally compound-engineering:-prefixed).
# Model-invoked calls are blocked separately by permissions.deny Skill(...) rules.
# Exit 2 = Claude Code drops the prompt and shows stderr to the user.
in=$(cat)
re='"prompt"[[:space:]]*:[[:space:]]*"([[:space:]]|\\[nrt])*/((pstack:)?(poteto-mode|tdd|reflect|setup-pstack)|(compound-engineering:)?lfg)([[:space:]"]|\\|$)'
if printf '%s' "$in" | grep -Eq "$re"; then
  echo "Blocked: this command is disabled on this machine (pstack poteto-mode/tdd/reflect/setup-pstack, compound-engineering lfg). See ops bootstrap claude-plugins README." >&2
  exit 2
fi
exit 0
