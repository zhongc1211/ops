#!/bin/bash
# snap.sh <prefix>: read-only snapshot used for the dry-run proof (orca worktree / terminal list, git worktree list per repo)
p=$1
orca worktree list --json > "$p-wt.json"
orca terminal list --json > "$p-term.json"
orca worktree list --json | python3 -I -c 'import json,sys
for w in json.load(sys.stdin)["result"]["worktrees"]:
    if w.get("isMainWorktree"): print(w["path"])' | sort -u | while IFS= read -r m; do
  echo "== $m"; [ -e "$m" ] && GIT_OPTIONAL_LOCKS=0 git -C "$m" worktree list
done > "$p-git.txt" 2>&1
