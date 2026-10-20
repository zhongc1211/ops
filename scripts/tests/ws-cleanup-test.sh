#!/bin/bash
# ws-cleanup-test.sh: run scripts/ws-cleanup.sh against fake orca / gh / ps data plus real throwaway git repos under mktemp -d.
# One case per failure mode in reports/ws-cleanup-dryrun-1021/RESULT.md (A1-A34). Uses test doubles, so it is not an E2E
# test; the E2E is the real dry-run on iMac / MBA. Touches nothing outside its temp dir and never passes --execute (E1-E4,
# the --execute paths, are not covered this round). WS_CLEANUP=<path> runs another implementation (an empty stub must fail).
S=${WS_CLEANUP:-$(cd "$(dirname "$0")/.." && pwd)/ws-cleanup.sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/ws-cleanup-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
F=$T/fix; mkdir -p "$F" "$T/bin" "$T/wt"; fails=0; n=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
bad(){ n=$((n+1)); fails=$((fails+1)); echo "FAIL $n $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; echo "     stdout/stderr:"; sed 's/^/     | /' "$T/log" | head -20; fi; }
NOW=$(date +%s); SECRET="SECRET-MARKER-$$-devvars"; SCREEN_SECRET="SCREEN-MARKER-$$"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 HOME=$T/home
mkdir -p "$HOME"

# --- real git: bare origin, main clone (proj), second project (ops) sharing the origin, one worktree per case ---
git init -q --bare "$T/origin.git"; git -C "$T/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$T/origin.git" "$T/repos/proj" 2>/dev/null; P=$T/repos/proj
git -C "$P" checkout -q -b main
printf 'x\n' >"$P/README"; printf '.orca-task/\n.dev.vars\nTASK.md\nevidence/\nnode_modules/\ndist/\nscratch/\n*.local.*\n' >"$P/.gitignore"
git -C "$P" add README .gitignore; GIT_COMMITTER_DATE="@$((NOW-400000))" git -C "$P" commit -qm init --date "@$((NOW-400000))"
git -C "$P" push -q origin main
git -C "$P" remote add upstream https://github.com/up/proj.git
git clone -q "$T/origin.git" "$T/repos/ops"; git -C "$T/repos/ops" remote set-url origin https://github.com/zz/ops.git
git -C "$P" remote set-url --push origin "$T/origin.git"; git -C "$P" remote set-url origin https://github.com/zz/proj.git
git -C "$P" config remote.origin.pushurl "$T/origin.git"
add(){ git -C "$P" worktree add -q -b "$2" "$T/wt/$1" main 2>/dev/null; }
for c in c_self c_remote_host c_agent c_agent_noid c_proc c_diag_missing c_dirty c_untracked c_unpushed c_open_pr \
         c_linked_open_pr c_linear_open c_linear_fail c_not_done c_merged_inreview c_recent c_backup c_backup_evidence \
         c_nested c_cache_only c_termhost git_only; do add "$c" "br/$c"; done
git -C "$P" worktree add -q -b br/zh "$T/wt/c_中文 空格" main 2>/dev/null
git -C "$T/repos/ops" worktree add -q -b br/ops_common "$T/wt/c_ops_common" origin/main 2>/dev/null
git -C "$T/repos/ops" worktree add -q -b br/gh_fail "$T/wt/c_gh_fail" origin/main 2>/dev/null
# c_zero_recent_commit: HEAD is a pushed commit from 1 hour ago
add c_zero_recent_commit br/c_zero_recent_commit
printf 'y\n' >"$T/wt/c_zero_recent_commit/y"; git -C "$T/wt/c_zero_recent_commit" add y
GIT_COMMITTER_DATE="@$((NOW-3600))" git -C "$T/wt/c_zero_recent_commit" commit -qm recent --date "@$((NOW-3600))"
git -C "$T/wt/c_zero_recent_commit" push -q origin br/c_zero_recent_commit 2>/dev/null
git -C "$P" fetch -q "$T/origin.git" '+refs/heads/*:refs/remotes/origin/*'
printf 'changed\n' >>"$T/wt/c_dirty/README"
printf 'new\n' >"$T/wt/c_untracked/new.txt"
printf 'z\n' >"$T/wt/c_unpushed/z"; git -C "$T/wt/c_unpushed" add z; git -C "$T/wt/c_unpushed" commit -qm local
mkdir -p "$T/wt/c_backup/.orca-task"; printf 'brief\n' >"$T/wt/c_backup/.orca-task/BRIEF.md"
printf 'API_TOKEN=%s\n' "$SECRET" >"$T/wt/c_backup/.dev.vars"; chmod 644 "$T/wt/c_backup/.dev.vars"
mkdir -p "$T/wt/c_backup_evidence/evidence"; printf 'shot\n' >"$T/wt/c_backup_evidence/evidence/a.png"
mkdir -p "$T/wt/c_nested/scratch/deep"; printf 'task\n' >"$T/wt/c_nested/scratch/deep/TASK.md"
mkdir -p "$T/wt/c_cache_only/node_modules/pkg" "$T/wt/c_cache_only/dist"
printf 'm\n' >"$T/wt/c_cache_only/node_modules/pkg/TASK.md"; printf 'b\n' >"$T/wt/c_cache_only/dist/app.js"
mkdir -p "$T/wt/c_not_git"; printf 'n\n' >"$T/wt/c_not_git/file"

# --- fixtures: orca worktree / terminal / diagnostics / linear, gh PR lists, ps ---
python3 -I - "$T" "$F" "$NOW" "$SCREEN_SECRET" <<'PY'
import json, os, sys
T, F, NOW, SCR = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
old, recent = (NOW - 200000) * 1000, (NOW - 7200) * 1000
R1, R2, R3 = "r-proj", "r-ops", "r-nogh"
def w(path, repo=R1, status="completed", act=old, br=None, main=False, host="local", pr=None, lin=None, proj=None):
    br = br if br is not None else "br/" + os.path.basename(path)
    proj = proj or {R1: "github:up/proj", R2: "github:zz/ops", R3: "github:zz/nogh"}[repo]
    return {"id": f"{repo}::{path}", "repoId": repo, "projectId": proj, "path": path, "displayName": os.path.basename(path),
            "branch": "refs/heads/" + br if br else "", "workspaceStatus": status, "lastActivityAt": act, "hostId": host,
            "isMainWorktree": main, "isBare": False, "isArchived": False, "linkedPR": pr, "linkedLinearIssue": lin}
wt = lambda c: f"{T}/wt/{c}"
W = [w(f"{T}/repos/proj", br="main", main=True, status="in-progress"),
     w(f"{T}/repos/ops", repo=R2, br="main", main=True, status="in-progress"),
     w(wt("c_self")), w(wt("c_remote_host"), host="mba-host"), w(wt("c_agent")), w(wt("c_agent_noid")), w(wt("c_proc")),
     w(wt("c_diag_missing")), w(wt("c_missing")), w(wt("c_dirty")), w(wt("c_untracked")), w(wt("c_unpushed")),
     w(wt("c_open_pr")), w(wt("c_linked_open_pr"), pr=999), w(wt("c_linear_open"), lin="PER-1"),
     w(wt("c_linear_fail"), lin="ZZZ-9"), w(wt("c_not_done"), status="in-review"),
     w(wt("c_merged_inreview"), status="in-review"), w(wt("c_recent"), act=recent), w(wt("c_zero_recent_commit"), act=0),
     w(wt("c_backup")), w(wt("c_backup_evidence")), w(wt("c_nested")), w(wt("c_cache_only")), w(wt("c_termhost")),
     w(wt("c_中文 空格"), br="br/zh"), w(wt("c_ops_common"), repo=R2, br="br/ops_common"),
     w(wt("c_gh_fail"), repo=R3, br="br/gh_fail", proj="github:zz/nogh"), w(wt("c_not_git"), br="br/x")]
json.dump({"result": {"worktrees": W}}, open(F + "/wt.json", "w"), ensure_ascii=False)
# terminals: (handle, case, pid or None, connected, orphaned, agent, tab, children comm list, screen or None)
TS = [("t_agent", "c_agent", 1001, True, False, "claude", "tab-a", ["claude"], "$ "),
      ("t_agent_noid", "c_agent_noid", 1011, True, False, None, "tab-b", ["claude"], "$ "),
      ("t_proc", "c_proc", 1021, True, False, None, "tab-c", ["sleep"], "$ "),
      ("t_diag_missing", "c_diag_missing", None, True, False, None, "tab-d", [], "$ "),
      ("t_resume", "c_recent", 1041, True, False, None, "tab-e", [], f"{SCR}\nResume this session with:\nclaude --resume 0b5f6d2e-1111-2222\n$ "),
      ("t_read_fail", "c_recent", 1051, True, False, None, "tab-f", [], None),
      ("t_dead", "c_recent", None, False, True, None, "tab-g", [], "$ "),
      ("t_self", "c_self", 1061, True, False, None, "tab-h", [], "$ "),
      ("t_empty", "c_termhost", 1071, True, False, None, "tab-i", [], "$ "),
      ("t_sib_empty", "c_proc", 1081, True, False, None, "tab-x", [], "$ "),
      ("t_sib_proc", "c_proc", 1091, True, False, None, "tab-x", ["sleep"], "$ ")]
terms, sess, ps = [], {}, ["  PID  PPID COMM", "    1     0 /sbin/launchd"]
for h, c, pid, con, orph, ag, tab, kids, scr in TS:
    path = wt(c); wid = next(x["id"] for x in W if x["path"] == path)
    terms.append({"handle": h, "worktreeId": wid, "worktreePath": path, "ptyId": "pty-" + h, "connected": con, "orphaned": orph,
                  "agentIdentity": ag, "tabId": tab, "title": h, "lastOutputAt": None})
    if pid:
        sess.setdefault(wid, []).append({"sessionId": "pty-" + h, "pid": pid, "paneKey": h})
        ps += [f"{pid:5d}     1 login", f"{pid+1:5d} {pid:5d} -zsh"] + [f"{pid+2+i:5d} {pid+1:5d} /usr/bin/{k}" for i, k in enumerate(kids)]
    if scr is not None:
        open(f"{F}/read-{h}.txt", "w").write(scr)
json.dump({"result": {"terminals": terms}}, open(F + "/term.json", "w"), ensure_ascii=False)
json.dump({"result": {"worktrees": [{"worktreeId": k, "sessions": v} for k, v in sess.items()]}}, open(F + "/diag.json", "w"))
open(F + "/ps.txt", "w").write("\n".join(ps) + "\n")
json.dump({"result": {"issues": [{"identifier": "PER-1", "state": {"type": "started", "name": "In Progress"}}]}}, open(F + "/lin-PER.json", "w"))
pr = lambda num, st, br, owner="zz": {"number": num, "state": st, "headRefName": br, "headRepositoryOwner": {"login": owner}}
json.dump([pr(1, "OPEN", "br/c_open_pr"), pr(2, "MERGED", "br/c_merged_inreview"), pr(3, "MERGED", "br/c_self")],
          open(F + "/pr-zz__proj.json", "w"))
json.dump([pr(999, "OPEN", "other-branch"), pr(5, "OPEN", "br/c_not_done", owner="someone-else")], open(F + "/pr-up__proj.json", "w"))
json.dump([pr(7, "MERGED", "br/ops_common")], open(F + "/pr-zz__ops.json", "w"))
PY
json_repos='{"result":{"repos":[{"id":"r-proj","displayName":"proj","path":"'"$P"'","kind":"git"},{"id":"r-ops","displayName":"ops","path":"'"$T"'/repos/ops","kind":"git"},{"id":"r-nogh","displayName":"nogh","path":"'"$T"'/repos/ops","kind":"git"}]}}'
printf '%s' "$json_repos" >"$F/repos.json"

cat >"$T/bin/orca" <<'SH'
#!/bin/bash
# fake orca: read-only subcommands answer from $WS_FIX; everything else is logged and "succeeds"
echo "$*" >>"$WS_FIX/orca-calls.log"
case "$1 $2" in
"worktree list") [ -f "$WS_FIX/fail-wt" ] && exit 1; cat "$WS_FIX/wt.json";;
"terminal list") [ -f "$WS_FIX/fail-term" ] && exit 1; cat "$WS_FIX/term.json";;
"diagnostics memory") [ -f "$WS_FIX/fail-diag" ] && exit 1; cat "$WS_FIX/diag.json";;
"repo list") cat "$WS_FIX/repos.json";;
"terminal read") h=; while [ $# -gt 0 ]; do [ "$1" = --terminal ] && h=$2; shift; done
  [ -f "$WS_FIX/read-$h.txt" ] || exit 1
  python3 -I -c 'import json,sys; print(json.dumps({"result":{"terminal":{"tail":open(sys.argv[1]).read().splitlines()}}}))' "$WS_FIX/read-$h.txt";;
"linear list-issues") t=; while [ $# -gt 0 ]; do [ "$1" = --team ] && t=$2; shift; done
  [ -f "$WS_FIX/lin-$t.json" ] || exit 1; cat "$WS_FIX/lin-$t.json";;
*) echo '{"result":{}}';;
esac
SH
cat >"$T/bin/gh" <<'SH'
#!/bin/bash
echo "$*" >>"$WS_FIX/gh-calls.log"
r=; while [ $# -gt 0 ]; do case $1 in -R|--repo) r=$2;; esac; shift; done
f="$WS_FIX/pr-${r%%/*}__${r#*/}.json"; [ -f "$f" ] || exit 1; cat "$f"
SH
chmod +x "$T/bin/orca" "$T/bin/gh"
export WS_FIX=$F WS_ORCA=$T/bin/orca WS_GH=$T/bin/gh WS_PS_FILE=$F/ps.txt WS_NOW=$NOW WS_HOST=iMac WS_SELF=$T/wt/c_self \
  WS_SELF_TERM=t_self WS_ARCHIVE=$T/archive WS_NO_DU=1
gitsnap(){ for d in "$P" "$T/repos/ops" "$T"/wt/*; do [ -d "$d" ] || continue
  echo "== $d"; git -C "$d" status --porcelain=v1 --ignored 2>&1; git -C "$d" rev-parse HEAD 2>&1; done
  git -C "$P" worktree list --porcelain; git -C "$T/repos/ops" worktree list --porcelain
  ls -la "$T/wt/c_backup/.dev.vars"; }
run(){ out=$1; shift; bash "$S" --out "$out" "$@" >"$T/log" 2>&1; echo $?; }
col(){ python3 -I - "$1" "$2" "$3" <<'PY'
import csv, sys
f, key, field = sys.argv[1:]
rows = list(csv.DictReader(open(f), delimiter="\t"))
m = [r for r in rows if r.get("path", "").endswith("/" + key) or r.get("handle") == key]
print(m[0][field] if m else "<none>")
PY
}
gitsnap >"$T/git-before"

rc=$(run "$T/out1")
check "G1 dry-run exits 0" '[ "$rc" = 0 ]'
WT=$T/out1/worktrees.tsv; TM=$T/out1/terminals.tsv
expect(){ v=$(col "$WT" "$1" action)/$(col "$WT" "$1" rule); want=$3; check "$2 $1 -> $3 (got $v)" '[ "$v" = "$want" ]'; }
expect proj A1 SKIP/W1
expect c_self A2 SKIP/W2
expect c_remote_host A3 LIST/W3
expect c_agent A4 SKIP/W5
expect c_agent_noid A4 SKIP/W5
expect c_proc A5 SKIP/W6
expect c_diag_missing A6 SKIP/W6
expect c_dirty A7 SKIP/W7
expect c_untracked A7 SKIP/W7
expect c_unpushed A8 SKIP/W8
expect c_open_pr A9 SKIP/W9
expect c_linked_open_pr A9 SKIP/W9
expect c_gh_fail A10 SKIP/W9
expect c_linear_open A11 SKIP/W10
expect c_linear_fail A12 SKIP/W10
expect c_not_done A13 SKIP/W11
expect c_merged_inreview A13 RM/W14
expect c_recent A14 SKIP/W12
expect c_zero_recent_commit A14 SKIP/W12
expect c_backup A15 BACKUP_RM/W13
expect c_backup_evidence A15 BACKUP_RM/W13
expect c_nested A15 BACKUP_RM/W13
expect c_cache_only A16 RM/W14
expect c_ops_common A17 RM/W14
expect "c_中文 空格" A18 RM/W14
expect c_not_git A19 SKIP/W7
expect c_missing A20 RM/W4
expect git_only A21 LIST/W16
check "A15 c_backup lists .dev.vars and .orca-task" 'b=$(col "$WT" c_backup backup); case "$b" in *.dev.vars*) case "$b" in *.orca-task*) true;; *) false;; esac;; *) false;; esac'
check "A15 c_nested finds scratch/deep/TASK.md" '[ "$(col "$WT" c_nested backup)" = "scratch/deep/TASK.md" ]'
check "A18 every TSV row has the header's column count" 'awk -F"\t" "NR==1{n=NF} NF!=n{bad=1} END{exit bad}" "$WT" && awk -F"\t" "NR==1{n=NF} NF!=n{bad=1} END{exit bad}" "$TM"'
RMPAT="orca worktree rm --worktree 'id:"
check "A20 planned rm has no --force" '! grep -q -- "--force" "$WT" && grep -qF "$RMPAT" "$WT"'
texp(){ v=$(col "$TM" "$1" action)/$(col "$TM" "$1" rule); want=$3; check "$2 $1 -> $3 (got $v)" '[ "$v" = "$want" ]'; }
texp t_agent A22 SKIP/T1
texp t_agent_noid A22 SKIP/T1
texp t_resume A22 SKIP/T2
texp t_self A22 SKIP/T3
texp t_proc A22 SKIP/T6
texp t_sib_proc A22 SKIP/T6
texp t_read_fail A23 SKIP/T2
texp t_diag_missing A6 SKIP/T6
texp t_empty A25 CLOSE/T4
texp t_dead A25 CLOSE/T5
texp t_sib_empty A24 CLOSE/T4
check "A24 sibling of a live pane closes without --tab" '! col "$TM" t_sib_empty planned | grep -q -- "--tab"'
check "A24 sole pane in its tab closes with --tab" 'col "$TM" t_empty planned | grep -q -- "--tab"'
check "A26 fake orca saw no rm / close / set / send" '! grep -E "^(worktree (rm|set)|terminal (close|send|stop))" "$F/orca-calls.log"'
check "A26 no backup root created" '[ ! -e "$T/archive" ]'
gitsnap >"$T/git-after"
check "A26 git state and .dev.vars mode unchanged" 'cmp -s "$T/git-before" "$T/git-after"'
check "A30 fake secrets not in output or stdout" '! grep -rq -e "$SECRET" -e "$SCREEN_SECRET" "$T/out1" "$T/log"'

rc=$(run "$T/out2")
strip(){ python3 -I -c 'import csv,sys
r=list(csv.reader(open(sys.argv[1]),delimiter="\t")); h=r[0]; drop={i for i,c in enumerate(h) if c in ("idle_h",)}
[print("\t".join(c for i,c in enumerate(x) if i not in drop)) for x in r]' "$1"; }
check "A28 two runs give the same TSVs (minus idle_h)" '[ "$rc" = 0 ] && [ "$(strip "$T/out1/worktrees.tsv")" = "$(strip "$T/out2/worktrees.tsv")" ] && cmp -s "$T/out1/terminals.tsv" "$T/out2/terminals.tsv"'

rc=$(run "$T/out3" --list-only); [ -n "${WS_TEST_KEEP:-}" ] && cp -R "$T/out1" "$T/out3" "$WS_TEST_KEEP/"
check "A27 --list-only: every action is LIST" '[ "$rc" = 0 ] && [ -z "$(awk -F"\t" "FNR==1{for(i=1;i<=NF;i++)if(\$i==\"action\")a=i;next} \$a!=\"LIST\"" "$T/out3/worktrees.tsv" "$T/out3/terminals.tsv")" ]'

touch "$F/fail-wt"; rc=$(run "$T/out4"); rm -f "$F/fail-wt"
check "A29 worktree list fails -> exit 4, no result files" '[ "$rc" = 4 ] && [ ! -e "$T/out4/worktrees.tsv" ]'
touch "$F/fail-term"; rc=$(run "$T/out5"); rm -f "$F/fail-term"
check "A29 terminal list fails -> exit 4, no result files" '[ "$rc" = 4 ] && [ ! -e "$T/out5/worktrees.tsv" ]'
touch "$F/fail-diag"; rc=$(run "$T/out6"); rm -f "$F/fail-diag"
check "A6 diagnostics fails -> worktrees with terminals are SKIP W6, nothing to CLOSE" '[ "$rc" = 0 ] && [ "$(col "$T/out6/worktrees.tsv" c_termhost action)" = SKIP ] && ! grep -q "	CLOSE	" "$T/out6/terminals.tsv"'

echo "not run: E1-E4 (--execute paths; --execute is banned this round, see RESULT.md)"
echo "$((n-fails))/$n passed"; [ $fails = 0 ]
