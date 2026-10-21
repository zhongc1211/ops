#!/bin/bash
# snap.sh <prefix>: read-only snapshot for the dry-run / drill proof: orca worktree list / terminal list / worktree ps (JSON), git worktree list per repo
p=$1; O=${ORCA:-orca}
"$O" worktree list --json > "$p-wt.json"
"$O" terminal list --json > "$p-term.json"
"$O" worktree ps --limit 100000 --json > "$p-wps.json"
python3 -I -c 'import json,sys
for w in json.load(open(sys.argv[1]))["result"]["worktrees"]:
    if w.get("isMainWorktree"): print(w["path"])' "$p-wt.json" | sort -u | while IFS= read -r m; do
  echo "== $m"; [ -e "$m" ] && GIT_OPTIONAL_LOCKS=0 git -C "$m" worktree list --porcelain
done > "$p-git.txt" 2>&1
