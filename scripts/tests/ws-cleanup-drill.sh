#!/bin/bash
# ws-cleanup-drill.sh setup|dry|execute|post OUTDIR — real-Orca drill for ws-cleanup.sh --execute (Zack 10-21 03:40).
# Only iMac. Everything lives under ~/ops-drill (local bare origin, a clone registered as its own Orca repo, external
# git worktrees under ~/ops-drill/wt). Every ws-cleanup.sh call passes --repo <drill repo id>; backups go to
# ~/ops-drill/archive. No GitHub, no other repo, no terminal close.
#   setup    create the drill workspaces (cases below), snapshot before
#   dry      dry-run with the new script (bash 3.2 and 5.3) and the old d3efbf0 script (OLD=path)
#   execute  change some workspaces after the dry-run, run the guard checks (W40, E10, E11, E14), then the real --execute
#            twice (second run = E12), with an appender running on d12 (E1)
#   post     snapshot after, compare with before, check backups
set -u
PHASE=${1:?phase}; OUT=${2:?outdir}
O=/Applications/Orca.app/Contents/Resources/bin/orca
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$HERE/scripts/ws-cleanup.sh
SNAP=$HERE/reports/ws-cleanup-rework-r1/snap.sh
R=$HOME/ops-drill; MAIN=$R/ws-cleanup-drill
SUF=${DRILL_TAG:+-$DRILL_TAG}                  # DRILL_TAG=r2 → a second set of workspaces in wt-r2, backups in archive-r2
WT=$R/wt$SUF; ARCH=$R/archive$SUF
G="git -c user.name=drill -c user.email=drill@localhost"
[ "$(hostname -s)" = iMac ] || { echo "drill: only on iMac" >&2; exit 2; }
mkdir -p "$OUT"
RID=$("$O" repo list --json | python3 -I -c 'import json,sys
print("".join(r["id"] for r in json.load(sys.stdin)["result"]["repos"] if r["path"] == sys.argv[1]))' "$MAIN")
[ -n "$RID" ] || { echo "drill: $MAIN is not an Orca repo (orca repo add --path $MAIN)" >&2; exit 2; }
echo "$RID" > "$OUT/repo-id.txt"
export WS_ARCHIVE=$ARCH WS_IDLE_H=0         # drill workspaces are minutes old; every other rule is unchanged
run() { local name=$1; shift; echo "\$ $*" > "$OUT/$name.cmd"; "$@" > "$OUT/$name.stdout" 2> "$OUT/$name.stderr"; local c=$?; echo $c > "$OUT/$name.exit"; echo "$name exit $c"; }
wid() { echo "$RID::$WT/$1"; }
status() { "$O" worktree set --worktree "id:$(wid "$1")" --workspace-status "$2" --json > /dev/null || echo "drill: status $1 failed" >&2; }
mk() {  # mk NAME [base]: external worktree on its own branch, pushed, status completed
  local n=$1 base=${2:-origin/main}
  [ -e "$WT/$n" ] && return 0
  git -C "$MAIN" worktree add -q -b "drill$SUF/$n" "$WT/$n" "$base" && git -C "$WT/$n" push -q -u origin "drill$SUF/$n"
}
wait_listed() { local i; for i in 1 2 3 4 5 6 7 8 9 10; do "$O" worktree list --json | grep -q "\"$WT/$1\"" && return 0; sleep 1; done; echo "drill: $1 not listed" >&2; return 1; }

case $PHASE in
setup)
  mkdir -p "$WT"
  "$O" repo set --repo "id:$RID" --external-worktree-visibility show --json > /dev/null
  # d01-clean is the one Orca-created workspace (orca worktree create opens a terminal in it) → W6
  mk d02-probe                                                        # RM W14 → deleted
  mk d03-backup; echo "drill notes, not rebuildable" > "$WT/d03-backup/notes.local"   # BACKUP_RM: notes.local + .dev.vars
  echo "DRILL_FAKE=not-a-secret" > "$WT/d03-backup/.dev.vars"; mkdir -p "$WT/d03-backup/node_modules/x"; echo 1 > "$WT/d03-backup/node_modules/x/i.js"
  mk d04-unpushed; echo a > "$WT/d04-unpushed/a.txt"; $G -C "$WT/d04-unpushed" add a.txt; $G -C "$WT/d04-unpushed" commit -qm local   # W8
  mk d05-dirty; echo b > "$WT/d05-dirty/b.txt"                                                           # W7
  if [ ! -e "$OUT/d06.head" ] && [ ! -e "$WT/d06-gone-local" ]; then                                       # F1 / E9: detached local commit, dir gone
    git -C "$MAIN" worktree add -q --detach "$WT/d06-gone-local" origin/main
    echo c > "$WT/d06-gone-local/c.txt"; $G -C "$WT/d06-gone-local" add c.txt; $G -C "$WT/d06-gone-local" commit -qm only-local
    git -C "$WT/d06-gone-local" rev-parse HEAD > "$OUT/d06.head"
  fi
  mk d07-gone-pushed                                                   # E13: dir gone, HEAD on origin → RM W4
  mk d08-inreview                                                      # W11
  mk d09-late-commit; mk d10-late-dirty                                # E4b / E4a: change after the dry-run
  mk d11-locked; echo "DRILL_FAKE=not-a-secret" > "$WT/d11-locked/.dev.vars"   # E2 / E3: locked after the dry-run
  mk d12-sha; mkdir -p "$WT/d12-sha/.orca-task"; python3 -I -c 'import sys; open(sys.argv[1],"wb").write(b"x"*(32<<20))' "$WT/d12-sha/.orca-task/log.local"  # E1
  mk d13-noperm; mkdir -p "$WT/d13-noperm/secret-notes"; echo n > "$WT/d13-noperm/secret-notes/locked.txt"; chmod 000 "$WT/d13-noperm/secret-notes/locked.txt"  # E8
  mk d14-fifo; [ -p "$WT/d14-fifo/pipe.local" ] || mkfifo "$WT/d14-fifo/pipe.local"                        # W13 odd
  mk d15-nested; mkdir -p "$WT/d15-nested/secret-notes/inner"; git -C "$WT/d15-nested/secret-notes/inner" init -q   # W13 nested .git
  mk d16-linear-missing                                                # W10: Linear issue that does not exist
  mk d17-branch-only; echo d > "$WT/d17-branch-only/d.txt"; $G -C "$WT/d17-branch-only" add d.txt; $G -C "$WT/d17-branch-only" commit -qm on-branch
  git -C "$WT/d17-branch-only" push -q origin "drill$SUF/d17-branch-only"  # pushed, not on main, no PR → W17
  for n in d02-probe d03-backup d04-unpushed d05-dirty d06-gone-local d07-gone-pushed d08-inreview d09-late-commit d10-late-dirty d11-locked d12-sha d13-noperm d14-fifo d15-nested d16-linear-missing d17-branch-only; do
    wait_listed $n && status $n completed
  done
  status d08-inreview in-review
  "$O" worktree set --worktree "id:$(wid d16-linear-missing)" --linear-issue PER-999999 --json > "$OUT/d16-set.json" 2>&1; echo "d16 linear set exit $?"
  rm -rf "$WT/d06-gone-local" "$WT/d07-gone-pushed"
  ORCA=$O "$SNAP" "$OUT/before"
  git -C "$MAIN" for-each-ref --format='%(refname) %(objectname)' > "$OUT/before-refs.txt"
  ;;
dry)
  run dry-new-bash3.2 /bin/bash "$SCRIPT" --repo "$RID" --out "$OUT/dry-new-bash3.2"
  run dry-new-bash5.3 /usr/local/bin/bash "$SCRIPT" --repo "$RID" --out "$OUT/dry-new-bash5.3"
  # old d3efbf0 has no --repo: full dry-run (read-only), drill rows picked out afterwards
  [ -n "${OLD:-}" ] && run dry-old-d3efbf0 /bin/bash "$OLD" --out "$OUT/dry-old-d3efbf0"
  ;;
execute)
  [ -s "$OUT/dry-new-bash3.2/worktrees.tsv" ] || { echo "drill: no dry-run list" >&2; exit 2; }
  L=$OUT/list.tsv                         # this round's rows only (an earlier round's leftovers stay out of the list)
  python3 -I -c 'import sys
rows = open(sys.argv[1]).read().splitlines(True)
open(sys.argv[3], "w").writelines(rows[:1] + [r for r in rows[1:] if "::" + sys.argv[2] + "/" in r])' "$OUT/dry-new-bash3.2/worktrees.tsv" "$WT" "$L"
  # changes between the dry-run and --execute
  echo late > "$WT/d09-late-commit/late.txt"; $G -C "$WT/d09-late-commit" add late.txt; $G -C "$WT/d09-late-commit" commit -qm late   # E4b
  echo late > "$WT/d10-late-dirty/late.txt"                                                                                         # E4a
  git -C "$MAIN" worktree lock --reason "ws-cleanup drill E2" "$WT/d11-locked"                                                       # E2
  # guard checks: each must exit non-zero and touch nothing
  python3 -I - "$L" "$OUT/w40-list.tsv" <<'EOF'
import csv, sys
rows = list(csv.reader(open(sys.argv[1]), delimiter="\t")); h = rows[0]; i = h.index("id"); v = h.index("verdict")
ok = [r for r in rows[1:] if r[v] == "RM"]
bad = list(ok[0]); bad[i] = "e9b33f9c-7218-4f6c-b03a-3b85fd8933ac::/nonexistent/ws-cleanup-drill-w40"   # ops repo id, path that does not exist
csv.writer(open(sys.argv[2], "w"), delimiter="\t", lineterminator="\n").writerows([h] + ok + [bad])
EOF
  run w40-foreign-row /bin/bash "$SCRIPT" --execute --repo "$RID" --only-from "$OUT/w40-list.tsv" --out "$OUT/w40-foreign-row"
  run e14-no-list /bin/bash "$SCRIPT" --execute --repo "$RID" --out "$OUT/e14-no-list"
  run e10-no-gh env WS_GH=$R/no-such-gh /bin/bash "$SCRIPT" --execute --repo "$RID" --only-from "$L" --out "$OUT/e10-no-gh"
  mkdir -p "$ARCH"; mkdir "$ARCH/.lock" && echo $$ > "$ARCH/.lock/pid"                                                              # E11: live pid (this shell)
  run e11-lock-held /bin/bash "$SCRIPT" --execute --repo "$RID" --only-from "$L" --out "$OUT/e11-lock-held"
  rm -rf "$ARCH/.lock"
  "$O" worktree list --json | python3 -I -c 'import json,sys
print(sum(1 for w in json.load(sys.stdin)["result"]["worktrees"] if w["repoId"] == sys.argv[1]))' "$RID" > "$OUT/count-after-guards.txt"
  # E1: keep appending to d12's file while --execute runs
  python3 -I -c 'import sys, time
f = open(sys.argv[1], "ab"); end = time.time() + 600
while time.time() < end: f.write(b"y" * 4096); f.flush(); time.sleep(0.01)' "$WT/d12-sha/.orca-task/log.local" &
APP=$!
run execute-1 /bin/bash "$SCRIPT" --execute --repo "$RID" --only-from "$L" --out "$OUT/execute-1"
  kill $APP; wait $APP 2> /dev/null
  run execute-2-same-day /bin/bash "$SCRIPT" --execute --repo "$RID" --only-from "$L" --out "$OUT/execute-2-same-day"   # E12
  ;;
post)
  ORCA=$O "$SNAP" "$OUT/after"
  git -C "$MAIN" for-each-ref --format='%(refname) %(objectname)' > "$OUT/after-refs.txt"
  git -C "$MAIN" worktree list --porcelain > "$OUT/after-drill-git.txt"
  find "$ARCH" -path "$ARCH/reports" -prune -o -print | sed "s|^$HOME|~|" | sort > "$OUT/archive-tree.txt"
  find "$ARCH" -path "$ARCH/reports" -prune -o -type f -exec stat -f '%Sp %z %N' {} + | sed "s|$HOME|~|" | sort -k3 > "$OUT/archive-perms.txt"
  find "$ARCH" -path "$ARCH/reports" -prune -o -type d -exec stat -f '%Sp %N' {} + | sed "s|$HOME|~|" | sort -k2 > "$OUT/archive-dirperms.txt"
  for m in $(find "$ARCH" -name MANIFEST.sha256); do (cd "$(dirname "$m")" && shasum -a 256 -c MANIFEST.sha256 > /dev/null 2>&1 && echo "OK ${m#$HOME/}" || echo "FAIL ${m#$HOME/}"); done > "$OUT/manifest-check.txt"
  ls -la "$WT/d11-locked/.dev.vars" 2> /dev/null | awk '{print $1, $NF}' | sed "s|$HOME|~|" > "$OUT/d11-devvars-still-there.txt"
  ;;
*) echo "drill: unknown phase $PHASE" >&2; exit 2 ;;
esac
