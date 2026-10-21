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
# R6 (Zack 10-21, PER-139 R6): init builds ~/ops-drill from nothing and adds it as its own Orca repo; then with DRILL_TAG=r6
#   r6-setup  h1-h4 workspaces (no Linear issue) + DELETE_OK review records in ~/ops-drill/reviews-r6, snapshot before
#   r6-dry    dry-run with --no-issue-reviews (bash 3.2 and 5.3)
#   r6-exec   one --execute per case, each --only-from holding just that drill row (checked first)
#   r6-post   snapshot after, archive tree, MANIFEST copies and checks
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
if [ "$PHASE" = init ]; then                  # R6: build ~/ops-drill from nothing and register it as its own Orca repo
  if [ ! -d "$MAIN/.git" ]; then
    mkdir -p "$R" && git init -q --bare "$R/origin.git" && git --git-dir="$R/origin.git" symbolic-ref HEAD refs/heads/main
    git init -q "$MAIN" && git -C "$MAIN" symbolic-ref HEAD refs/heads/main && git -C "$MAIN" remote add origin "$R/origin.git"
    printf 'ws-cleanup drill repo (local only)\n' > "$MAIN/README"; printf '.orca-task/\n.dev.vars\n*.local\n' > "$MAIN/.gitignore"
    $G -C "$MAIN" add README .gitignore && $G -C "$MAIN" commit -qm init && git -C "$MAIN" push -q -u origin main || exit 1
  fi
  "$O" repo add --path "$MAIN" --json > "$OUT/repo-add.json" 2>&1; echo "repo add exit $?"
  exit 0
fi
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
orca_list() {  # this repo's Orca worktrees: id, path, status, branch
  "$O" worktree list --json | python3 -I -c 'import json, os, sys
h = os.path.expanduser("~")
for w in sorted(json.load(sys.stdin)["result"]["worktrees"], key=lambda w: w["path"]):
    if w["repoId"] == sys.argv[1]: print("\t".join([w["id"].replace(h, "~"), w["path"].replace(h, "~"), w.get("workspaceStatus") or "", w.get("branch") or ""]))' "$RID"; }
others() {    # everything outside the drill repo, as a count and a hash of the sorted ids (no names or comments in the report)
  "$O" worktree list --json | python3 -I -c 'import hashlib, json, sys
ids = sorted(w["id"] for w in json.load(sys.stdin)["result"]["worktrees"] if w["repoId"] != sys.argv[1])
print("other worktrees: %d, sha256 of sorted ids: %s" % (len(ids), hashlib.sha256("\n".join(ids).encode()).hexdigest()))' "$RID"; }
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
# ---- R6 (DRILL_TAG=r6): no Linear issue + DELETE_OK review record (h1), HEAD changed after the dry-run (h2),
#      gh failing at --execute time (h3), workspace changed between backup and rm (h4). One --execute per case.
r6-setup)
  [ "$SUF" = -r6 ] || { echo "drill: r6 phases need DRILL_TAG=r6" >&2; exit 2; }
  mkdir -p "$WT"
  "$O" repo set --repo "id:$RID" --external-worktree-visibility show --json > /dev/null
  for n in h1-review-ok h2-late-head h3-gh-fail h4-after-backup; do
    mk $n; mkdir -p "$WT/$n/.orca-task"; echo "drill brief $n" > "$WT/$n/.orca-task/BRIEF.md"
    wait_listed $n && status $n completed
  done
  # review records, as the R4 ones: PATH / HEAD / VERDICT
  DN=$("$O" repo list --json | python3 -I -c 'import json, re, sys
r = [r for r in json.load(sys.stdin)["result"]["repos"] if r["id"] == sys.argv[1]][0]
print(re.sub(r"[^\w.\-]+", "_", r.get("displayName") or r["id"]).strip("_") or "_")' "$RID")
  mkdir -p "$R/reviews-r6/$DN"
  for n in h1-review-ok h2-late-head h3-gh-fail h4-after-backup; do
    printf '# 演练审查记录：%s\n\n演练工作区，只在 ~/ops-drill 里。\n\nPATH: %s\nHEAD: %s\nVERDICT: DELETE_OK\n' \
      "$n" "$WT/$n" "$(git -C "$WT/$n" rev-parse HEAD)" > "$R/reviews-r6/$DN/$n.md"
  done
  cp -R "$R/reviews-r6" "$OUT/reviews-r6"
  orca_list > "$OUT/before-orca-worktree-list.tsv"; others > "$OUT/before-others.txt"
  git -C "$MAIN" worktree list --porcelain | sed "s|$HOME|~|" > "$OUT/before-git-worktrees.txt"
  ;;
r6-dry)
  run dry-bash3.2 /bin/bash "$SCRIPT" --repo "$RID" --no-issue-reviews "$R/reviews-r6" --out "$OUT/dry-bash3.2"
  run dry-bash5.3 /usr/local/bin/bash "$SCRIPT" --repo "$RID" --no-issue-reviews "$R/reviews-r6" --out "$OUT/dry-bash5.3"
  ;;
r6-exec)
  [ -s "$OUT/dry-bash3.2/worktrees.tsv" ] || { echo "drill: no dry-run list" >&2; exit 2; }
  pick() {  # pick CASE: that one row of the dry-run list, refused unless every row is a drill worktree of this repo
    python3 -I - "$OUT/dry-bash3.2/worktrees.tsv" "$RID" "$WT" "$1" "$OUT/list-$1.tsv" <<'EOF' || exit 2
import csv, sys
src, rid, wt, case, dst = sys.argv[1:]
rows = list(csv.reader(open(src), delimiter="\t")); h = rows[0]; I, P = h.index("id"), h.index("path")
keep = [r for r in rows[1:] if r[P] == wt + "/" + case]
bad = [r for r in keep if not (r[I] == rid + "::" + r[P] and r[P].startswith(wt + "/"))]
if len(keep) != 1 or bad: sys.exit("drill: list for %s is not exactly one drill row" % case)
csv.writer(open(dst, "w"), delimiter="\t", lineterminator="\n").writerows([h] + keep)
print("list-%s.tsv: 1 row, %s %s" % (case, keep[0][h.index("verdict")], keep[0][h.index("rule")]))
EOF
  }
  X() { local name=$1 case=$2; shift 2; pick "$case" > "$OUT/$name.listcheck"; cat "$OUT/$name.listcheck"
        run "$name" "$@" /bin/bash "$SCRIPT" --execute --repo "$RID" --no-issue-reviews "$R/reviews-r6" --only-from "$OUT/list-$case.tsv" --out "$OUT/$name"; }
  # case 1: nothing changed → backed up (with NO-ISSUE-REVIEW.md) and removed
  X c1-execute h1-review-ok env
  # case 2: a commit after the dry-run → skipped at the recheck, no backup, no rm
  echo late > "$WT/h2-late-head/late.txt"; $G -C "$WT/h2-late-head" add late.txt; $G -C "$WT/h2-late-head" commit -qm late
  X c2-execute h2-late-head env
  # case 4: a commit between the backup and the rm (hook honoured only with WS_ORCA set; it is the real orca here)
  printf '#!/bin/bash\n# drill case 4: change the workspace after its backup\necho after-backup > "$1/after-backup.txt"\n%s -C "$1" add after-backup.txt && %s -C "$1" commit -qm after-backup\n' "$G" "$G" > "$OUT/hook-c4.sh"
  chmod +x "$OUT/hook-c4.sh"
  X c4-execute h4-after-backup env WS_ORCA="$O" WS_AFTER_BACKUP_HOOK="$OUT/hook-c4.sh"
  # case 3: give the drill repo a GitHub remote (never fetched, never contacted: the gh below fails) so the recheck asks gh
  git -C "$MAIN" remote get-url github > /dev/null 2>&1 || git -C "$MAIN" remote add github https://github.com/zhongc1211/ops-drill-no-such-repo.git
  printf '#!/bin/bash\n# drill case 3a: passes the startup check, every PR query fails\n[ "$1 $2" = "auth status" ] && exit 0\necho "drill: gh always fails" >&2; exit 1\n' > "$OUT/gh-fail-a.sh"
  printf '#!/bin/bash\n# drill case 3b: everything fails, auth status too\necho "drill: gh always fails" >&2; exit 1\n' > "$OUT/gh-fail-b.sh"
  chmod +x "$OUT/gh-fail-a.sh" "$OUT/gh-fail-b.sh"
  X c3a-execute h3-gh-fail env WS_GH="$OUT/gh-fail-a.sh"
  X c3b-execute h3-gh-fail env WS_GH="$OUT/gh-fail-b.sh"
  ;;
r6-post)
  orca_list > "$OUT/after-orca-worktree-list.tsv"; others > "$OUT/after-others.txt"
  git -C "$MAIN" worktree list --porcelain | sed "s|$HOME|~|" > "$OUT/after-git-worktrees.txt"
  find "$ARCH" | sed "s|^$HOME|~|" | sort > "$OUT/archive-tree.txt"
  mkdir -p "$OUT/manifests"
  for m in $(find "$ARCH" -name MANIFEST.sha256); do d=$(dirname "$m"); n=$(basename "$d")
    cp "$m" "$OUT/manifests/$n.MANIFEST.sha256"
    (cd "$d" && shasum -a 256 -c MANIFEST.sha256 > /dev/null 2>&1 && echo "OK ${m#$HOME/}" || echo "FAIL ${m#$HOME/}"); done > "$OUT/manifest-check.txt"
  for n in h2-late-head h3-gh-fail h4-after-backup; do printf '%s\t%s\t%s\n' "$n" "$([ -d "$WT/$n" ] && echo 目录在 || echo 目录不在)" "$(git -C "$WT/$n" log -1 --format='%h %s' 2>&1)"; done > "$OUT/left-workspaces.txt"
  ;;
*) echo "drill: unknown phase $PHASE" >&2; exit 2 ;;
esac
