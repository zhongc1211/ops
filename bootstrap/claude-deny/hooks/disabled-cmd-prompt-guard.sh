#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook (PER-89). Backup only: the main guards are the
# permissions.deny Skill(skill:...) rules and the UserPromptExpansion hook.
# Blocks prompts that start with a disabled command:
#   /poteto-mode /tdd /reflect /setup-pstack (optionally pstack:-prefixed), /lfg (optionally compound-engineering:-prefixed).
# Bash builtins only (no grep/node/python), so it stays fast under load.
# A timeout still lets the prompt through (UserPromptSubmit is fail-open); see README.
# Exit 2 = Claude Code drops the prompt and shows stderr to the user.
IFS= read -r -d '' in
re='"prompt"[[:space:]]*:[[:space:]]*"([[:space:]]|\\[nrt])*/((pstack:)?(poteto-mode|tdd|reflect|setup-pstack)|(compound-engineering:)?lfg)([[:space:]"]|\\|$)'
if [[ $in =~ $re ]]; then
  echo "Blocked (PER-89): this command is disabled on this machine (pstack poteto-mode/tdd/reflect/setup-pstack, compound-engineering lfg). See ops bootstrap/claude-deny/README.md." >&2
  exit 2
fi
exit 0
