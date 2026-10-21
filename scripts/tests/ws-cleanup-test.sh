#!/bin/bash
# ws-cleanup-test.sh: run scripts/ws-cleanup.sh against fake orca / gh / ps data plus real throwaway git repos under mktemp -d.
# One case per failure mode in reports/ws-cleanup-dryrun-1021/RESULT.md (A1-A34) and reports/ws-cleanup-rework-r1/FAILURE-MODES.md
# (B1-B29, E1-E19, G1-G11, M1-M5, N1-N8, R1-R13). Uses test doubles, so it is not an E2E test; the E2E is the real dry-run on iMac / MBA.
# The --execute cases run only against the fake orca in the temp dir: guard_fake() refuses to start one otherwise.
# WS_CLEANUP=<path> runs another implementation (an older version or an empty stub must fail).
S=${WS_CLEANUP:-$(cd "$(dirname "$0")/.." && pwd)/ws-cleanup.sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/ws-cleanup-test.XXXXXX")
APPENDER=; trap '[ -n "$APPENDER" ] && kill $APPENDER 2>/dev/null; chmod -R u+rw "$T" 2>/dev/null; rm -rf "$T"' EXIT
F=$T/fix; mkdir -p "$F" "$T/bin" "$T/wt"; fails=0; n=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
bad(){ n=$((n+1)); fails=$((fails+1)); echo "FAIL $n $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; echo "     stdout/stderr:"; sed 's/^/     | /' "$T/log" | head -20; fi; }
NOW=$(date +%s); SECRET="SECRET-MARKER-$$-devvars"; SCREEN_SECRET="SCREEN-MARKER-$$"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 HOME=$T/home
mkdir -p "$HOME"

# --- real git: bare origin, main clone (proj), second project (ops) and the execute project (x) sharing the origin ---
git init -q --bare "$T/origin.git"; git -C "$T/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$T/origin.git" "$T/repos/proj" 2>/dev/null; P=$T/repos/proj
git -C "$P" checkout -q -b main
printf 'x\n' >"$P/README"
printf '.orca-task/\n.dev.vars\nTASK.md\nevidence/\nnode_modules/\ndist/\nscratch/\n*.local.*\ntest-results/\n*.tgz\n.claude/\nbuild/\n.cache/\n.venv/\n' >"$P/.gitignore"
git -C "$P" add README .gitignore; GIT_COMMITTER_DATE="@$((NOW-400000))" git -C "$P" commit -qm init --date "@$((NOW-400000))"
git -C "$P" push -q origin main
git -C "$P" remote add upstream https://github.com/up/proj.git
git clone -q "$T/origin.git" "$T/repos/ops"; git -C "$T/repos/ops" remote set-url origin https://github.com/zz/ops.git
git clone -q "$T/origin.git" "$T/repos/x"; X=$T/repos/x; git -C "$X" remote set-url origin https://github.com/zz/x.git
git -C "$P" remote set-url --push origin "$T/origin.git"; git -C "$P" remote set-url origin https://github.com/zz/proj.git
git -C "$P" config remote.origin.pushurl "$T/origin.git"
git -C "$P" config core.ignorecase true; printf 'REPORT.md\n' >>"$P/.git/info/exclude"
add(){ git -C "$P" worktree add -q -b "$2" "$T/wt/$1" main 2>/dev/null; }
for c in c_self c_remote_host c_agent c_agent_noid c_proc c_diag_missing c_dirty c_untracked c_unpushed c_open_pr \
         c_linked_open_pr c_linear_open c_linear_fail c_not_done c_merged_inreview c_recent c_backup c_backup_evidence \
         c_nested c_cache_only c_termhost c_termhost2 git_only c_testresults c_report c_tgz c_mixed_dir c_nested_git c_fifo \
         c_moved_open c_old_open_pr c_linked_dup c_sleep_cap c_ps_agent c_build c_gone_ownbranch \
         c_head_unmerged c_linear_done_unmerged c_head_pr_merged; do add "$c" "br/$c"; done
git -C "$P" worktree add -q -b br/zh "$T/wt/c_中文 空格" main 2>/dev/null
git -C "$T/repos/ops" worktree add -q -b br/ops_common "$T/wt/c_ops_common" origin/main 2>/dev/null
git -C "$T/repos/ops" worktree add -q -b br/gh_fail "$T/wt/c_gh_fail" origin/main 2>/dev/null
# c_zero_recent_commit: HEAD is a pushed commit from 1 hour ago
add c_zero_recent_commit br/c_zero_recent_commit
printf 'y\n' >"$T/wt/c_zero_recent_commit/y"; git -C "$T/wt/c_zero_recent_commit" add y
GIT_COMMITTER_DATE="@$((NOW-3600))" git -C "$T/wt/c_zero_recent_commit" commit -qm recent --date "@$((NOW-3600))"
git -C "$T/wt/c_zero_recent_commit" push -q origin br/c_zero_recent_commit 2>/dev/null
# W17 cases: a pushed commit on the branch only (not in main); c_head_pr_merged's HEAD is a merged PR's head
for c in c_head_unmerged c_linear_done_unmerged c_head_pr_merged; do
  printf '%s\n' "$c" >"$T/wt/$c/f"; git -C "$T/wt/$c" add f; git -C "$T/wt/$c" commit -qm "$c"
  git -C "$T/wt/$c" push -q origin "br/$c" 2>/dev/null; done
MERGED_SHA=$(git -C "$T/wt/c_head_pr_merged" rev-parse HEAD)
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
mkdir -p "$T/wt/c_testresults/test-results/run1"; printf 'trace\n' >"$T/wt/c_testresults/test-results/run1/trace.zip"; printf 'v\n' >"$T/wt/c_testresults/test-results/run1/page@0a1b2c3d.webm"
mkdir -p "$T/wt/c_report/docs/e2e"; printf 'report\n' >"$T/wt/c_report/docs/e2e/report.md"
printf 'tgz\n' >"$T/wt/c_tgz/lessons-import.tgz"
mkdir -p "$T/wt/c_mixed_dir/scratch"; printf 't\n' >"$T/wt/c_mixed_dir/scratch/TASK.md"; printf 'notes\n' >"$T/wt/c_mixed_dir/scratch/notes.txt"
mkdir -p "$T/wt/c_nested_git/.claude/worktrees/x/.git"; printf 'ref: refs/heads/x\n' >"$T/wt/c_nested_git/.claude/worktrees/x/.git/HEAD"
mkdir -p "$T/wt/c_fifo/scratch"; mkfifo "$T/wt/c_fifo/scratch/pipe"
mkdir -p "$T/wt/c_build/build" "$T/wt/c_build/.cache/x" "$T/wt/c_build/.venv/bin"
printf 'o\n' >"$T/wt/c_build/build/out.js"; printf 'c\n' >"$T/wt/c_build/.cache/x/c"; printf 'p\n' >"$T/wt/c_build/.venv/bin/py"
# G cases (Zack 10-21 07:34): git locks / unfinished operations in the worktree's own gitdir -> SKIP W18 GIT_LOCKED
for c in c_lk_index c_lk_merge c_lk_rebase c_lk_am c_lk_cherry c_lk_bisect c_lk_wtlock c_email c_email_long; do add "$c" "br/$c"; done
gd(){ git -C "$T/wt/$1" rev-parse --absolute-git-dir; }
blob=$(printf 'other\n' | git -C "$P" hash-object -w --stdin)
tree=$({ git -C "$P" ls-tree main | grep -v '	README$'; printf '100644 blob %s\tREADME\n' "$blob"; } | git -C "$P" mktree)
git -C "$P" branch lkother "$(git -C "$P" commit-tree "$tree" -p main -m other)"
for c in c_lk_merge c_lk_rebase c_lk_cherry; do printf 'mine\n' >"$T/wt/$c/README"; git -C "$T/wt/$c" commit -qam mine; done
git -C "$T/wt/c_lk_merge" merge -q lkother >/dev/null 2>&1
git -C "$T/wt/c_lk_rebase" rebase lkother >/dev/null 2>&1
git -C "$T/wt/c_lk_cherry" cherry-pick lkother >/dev/null 2>&1
touch "$(gd c_lk_index)/index.lock"; mkdir "$(gd c_lk_am)/rebase-apply"
git -C "$T/wt/c_lk_bisect" bisect start >/dev/null 2>&1
git -C "$P" worktree lock "$T/wt/c_lk_wtlock"
git -C "$P" worktree add -q --detach "$T/wt/c_lk_gone" main 2>/dev/null; git -C "$P" worktree lock "$T/wt/c_lk_gone"; rm -rf "$T/wt/c_lk_gone"
# N cases (Zack 10-21 08:44): no linked Linear issue -> SKIP W19 NO_LINEAR_ISSUE, even with a merged PR / HEAD on main
for c in c_nolin c_nolin_pr c_nolin_backup c_nolin_blank c_rev_inreview c_rev_bad c_rev_wrongpath; do add "$c" "br/$c"; done
printf 'API_TOKEN=%s\n' "$SECRET" >"$T/wt/c_nolin_backup/.dev.vars"
NOLIN_SHA=$(git -C "$T/wt/c_nolin_pr" rev-parse HEAD)
git -C "$P" worktree add -q --detach "$T/wt/c_nolin_gone" main 2>/dev/null; rm -rf "$T/wt/c_nolin_gone"
# W4 cases: directory gone, git record kept (pushed / local-only detached / only in its own branch) or never there (c_missing)
git -C "$P" worktree add -q --detach "$T/wt/c_gone_pushed" main 2>/dev/null
git -C "$P" worktree add -q --detach "$T/wt/c_gone_local" main 2>/dev/null
printf 'l\n' >"$T/wt/c_gone_local/l"; git -C "$T/wt/c_gone_local" add l; git -C "$T/wt/c_gone_local" commit -qm only-here
GONE_SHA=$(git -C "$T/wt/c_gone_local" rev-parse --short=7 HEAD)
printf 'o\n' >"$T/wt/c_gone_ownbranch/o"; git -C "$T/wt/c_gone_ownbranch" add o; git -C "$T/wt/c_gone_ownbranch" commit -qm own
rm -rf "$T/wt/c_gone_pushed" "$T/wt/c_gone_local" "$T/wt/c_gone_ownbranch"
# execute project x: one worktree per --execute case
for c in x_ok x_bk x_sha x_rmfail x_e8a_noperm x_e8b_after x_late x_late2 x_late3 x_late4 x_late5 x_notlisted x_listchanged x_lin_fail x_lin_gone \
         x_late_lock x_late_nolin x_rev_ok x_rev_moved x_rev_stale_rec x_q01 x_q02 x_q03 x_q04 x_q05 x_q06 x_q07 x_q08 x_q09 x_q10 x_term x_term2 x_term3; do
  git -C "$X" worktree add -q -b "br/$c" "$T/wt/$c" origin/main 2>/dev/null; done
mkdir -p "$T/wt/x_bk/.orca-task"; printf 'brief\n' >"$T/wt/x_bk/.orca-task/BRIEF.md"
printf 'API_TOKEN=%s\n' "$SECRET" >"$T/wt/x_bk/.dev.vars"
mkdir -p "$T/wt/x_sha/.orca-task"; dd if=/dev/zero of="$T/wt/x_sha/.orca-task/grow.log" bs=1048576 count=32 2>/dev/null
mkdir -p "$T/wt/x_rmfail/.orca-task"; printf 'b\n' >"$T/wt/x_rmfail/.orca-task/BRIEF.md"
printf 'API_TOKEN=%s\n' "$SECRET" >"$T/wt/x_rmfail/.dev.vars"
mkdir -p "$T/wt/x_e8a_noperm/.orca-task"; printf 'secret-ish\n' >"$T/wt/x_e8a_noperm/.orca-task/locked"
chmod 000 "$T/wt/x_e8a_noperm/.orca-task/locked"

# --- fixtures: orca worktree / terminal / diagnostics / worktree ps / linear, gh PR lists, ps ---
python3 -I - "$T" "$F" "$NOW" "$SCREEN_SECRET" "$MERGED_SHA" "$NOLIN_SHA" <<'PY'
import json, os, sys
T, F, NOW, SCR, MERGED_SHA, NOLIN_SHA = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]
old, recent = (NOW - 200000) * 1000, (NOW - 7200) * 1000
R1, R2, R3, RX = "r-proj", "r-ops", "r-nogh", "r-x"
def w(path, repo=R1, status="completed", act=old, br=None, main=False, host="local", pr=None, lin="", proj=None, name=None,
      comment="note https://example.invalid/hook/abc"):
    br = br if br is not None else "br/" + os.path.basename(path)
    lin = ("OKX-1" if repo == RX else "PER-2") if lin == "" else lin   # lin=None: nothing linked
    proj = proj or {R1: "github:up/proj", R2: "github:zz/ops", R3: "github:zz/nogh", RX: "github:zz/x"}[repo]
    return {"id": f"{repo}::{path}", "repoId": repo, "projectId": proj, "path": path, "displayName": name or os.path.basename(path),
            "branch": "refs/heads/" + br if br else "", "workspaceStatus": status, "lastActivityAt": act, "hostId": host,
            "isMainWorktree": main, "isBare": False, "isArchived": False, "linkedPR": pr, "linkedLinearIssue": lin,
            "isUnread": False, "comment": comment}
wt = lambda c: f"{T}/wt/{c}"
W = [w(f"{T}/repos/proj", br="main", main=True, status="in-progress"),
     w(f"{T}/repos/ops", repo=R2, br="main", main=True, status="in-progress"),
     w(f"{T}/repos/x", repo=RX, br="main", main=True, status="in-progress"),
     w(wt("c_self")), w(wt("c_remote_host"), host="mba-host"), w(wt("c_agent")), w(wt("c_agent_noid")), w(wt("c_proc")),
     w(wt("c_diag_missing")), w(wt("c_missing")), w(wt("c_dirty")), w(wt("c_untracked")), w(wt("c_unpushed")),
     w(wt("c_open_pr")), w(wt("c_linked_open_pr"), pr=999), w(wt("c_linear_open"), lin="PER-1"),
     w(wt("c_linear_fail"), lin="ZZZ-9"), w(wt("c_not_done"), status="in-review"),
     w(wt("c_merged_inreview"), status="in-review"), w(wt("c_recent"), act=recent), w(wt("c_zero_recent_commit"), act=0),
     w(wt("c_backup")), w(wt("c_backup_evidence")), w(wt("c_nested")), w(wt("c_cache_only")), w(wt("c_termhost")),
     w(wt("c_termhost2")), w(wt("c_中文 空格"), br="br/zh"), w(wt("c_ops_common"), repo=R2, br="br/ops_common"),
     w(wt("c_gh_fail"), repo=R3, br="br/gh_fail", proj="github:zz/nogh"), w(wt("c_not_git"), br="br/x"),
     w(wt("c_testresults")), w(wt("c_report")), w(wt("c_tgz")), w(wt("c_mixed_dir")), w(wt("c_nested_git")), w(wt("c_fifo")),
     w(wt("c_moved_open"), proj="github:zz/moved"), w(wt("c_old_open_pr")), w(wt("c_linked_dup"), pr=50, proj="github:zz/proj"),
     w(wt("c_sleep_cap"), status="Sleep", lin="PER-2"), w(wt("c_ps_agent")), w(wt("c_build")),
     w(wt("c_gone_pushed"), br=""), w(wt("c_gone_local"), br=""), w(wt("c_gone_ownbranch")),
     w(wt("c_head_unmerged")), w(wt("c_linear_done_unmerged"), lin="PER-2"), w(wt("c_head_pr_merged"))]
W += [w(wt(c)) for c in ("c_lk_index", "c_lk_merge", "c_lk_rebase", "c_lk_am", "c_lk_cherry", "c_lk_bisect", "c_lk_wtlock")]
W += [w(wt("c_lk_gone"), br=""),
      w(wt("c_email"), name="bob.smith@example.com", comment="Bob.Smith@example.com ops-admin@corp.example.org pkg@1.2.3 node@20"),
      w(wt("c_email_long"), comment="x" * 50 + " admin.person@example.com")]
XS = ["x_ok", "x_bk", "x_sha", "x_rmfail", "x_e8a_noperm", "x_e8b_after", "x_late", "x_late2", "x_late3", "x_late4", "x_late5",
      "x_notlisted", "x_listchanged", "x_lin_fail", "x_lin_gone", "x_late_lock", "x_late_nolin", "x_rev_ok", "x_rev_moved", "x_rev_stale_rec"] + ["x_q%02d" % i for i in range(1, 11)] + ["x_term", "x_term2", "x_term3"]
W += [w(wt(c), repo=RX, lin={"x_late5": "XXX-1", "x_lin_fail": "YYY-1", "x_lin_gone": "XXX-2"}.get(c, None if c.startswith("x_rev_") else "")) for c in XS]
W += [w(wt("c_rev_inreview"), lin=None, status="in-review"), w(wt("c_rev_bad"), lin=None), w(wt("c_rev_wrongpath"), lin=None)]
W += [w(wt("c_nolin"), lin=None), w(wt("c_nolin_pr"), lin=None), w(wt("c_nolin_backup"), lin=None), w(wt("c_nolin_blank"), lin="  "),
      w(wt("c_nolin_gone"), br="", lin=None)]
json.dump({"result": {"worktrees": W}}, open(F + "/wt.json", "w"), ensure_ascii=False)
# terminals: (handle, case, pid or None, connected, orphaned, agent, tab, children comm list, screen or None, lastOutputAt)
P_ = "$ "
TS = [("t_agent", "c_agent", 1001, True, False, "claude", "tab-a", ["claude"], P_, old),
      ("t_agent_noid", "c_agent_noid", 1011, True, False, None, "tab-b", ["claude"], P_, old),
      ("t_proc", "c_proc", 1021, True, False, None, "tab-c", ["sleep"], P_, old),
      ("t_diag_missing", "c_diag_missing", None, True, False, None, "tab-d", [], P_, old),
      ("t_resume", "c_termhost2", 1041, True, False, None, "tab-e", [], f"{SCR}\nResume this session with:\nclaude --resume 0b5f6d2e-1111-2222\n$ ", old),
      ("t_read_fail", "c_termhost2", 1051, True, False, None, "tab-f", [], None, old),
      ("t_dead", "c_recent", None, False, True, None, "tab-g", [], P_, old),
      ("t_self", "c_self", 1061, True, False, None, "tab-h", [], P_, old),
      ("t_self_sib", "c_self", 1101, True, False, None, "tab-h2", [], P_, old),
      ("t_empty", "c_termhost", 1071, True, False, None, "tab-i", [], P_, old),
      ("t_sib_empty", "c_proc", 1081, True, False, None, "tab-x", [], P_, old),
      ("t_sib_proc", "c_proc", 1091, True, False, None, "tab-x", ["sleep"], P_, old),
      ("t_agent_sib", "c_agent", 1111, True, False, None, "tab-a2", [], P_, old),
      ("t_agent_sib_fresh", "c_agent", 1171, True, False, None, "tab-a3", [], P_, (NOW - 6 * 3600) * 1000),
      ("t_main", "MAIN", 1121, True, False, None, "tab-m", [], P_, old),
      ("t_folder", None, 1131, True, False, None, "tab-f2", [], P_, old),
      ("t_fresh", "c_termhost2", 1141, True, False, None, "tab-n", [], P_, (NOW - 600) * 1000),
      ("t_nolast", "c_termhost2", 1151, True, False, None, "tab-n2", [], P_, None),
      ("t_midoutput", "c_termhost2", 1161, True, False, None, "tab-n3", [], "Compiling...\n50% done", old),
      ("t_x_close", "x_term", 1201, True, False, None, "tab-xc", [], P_, old),
      ("t_late", "x_term2", 1211, True, False, None, "tab-l1", [], P_, old),
      ("t_late_tab", "x_term2", 1221, True, False, None, "tab-L", [], P_, old),
      ("t_x_arcfail", "x_term", 1231, True, False, None, "tab-xa", [], P_, old),
      ("t_x_agent", "x_term3", 1241, True, False, "claude", "tab-xg", ["claude"], P_, old),
      ("t_x_agent_sib", "x_term3", 1251, True, False, None, "tab-xs", [], P_, old),
      ("t_email", "c_email", 1301, True, False, None, "tab-em", [], P_, old)]
terms, sess, ps = [], {}, ["  PID  PPID COMM", "    1     0 /sbin/launchd"]
for h, c, pid, con, orph, ag, tab, kids, scr, last in TS:
    path = f"{T}/repos/proj" if c == "MAIN" else wt(c) if c else f"{T}/folder"
    wid = next((x["id"] for x in W if x["path"] == path), "folder-1")
    terms.append({"handle": h, "worktreeId": wid, "worktreePath": path, "ptyId": "pty-" + h, "connected": con, "orphaned": orph,
                  "agentIdentity": ag, "tabId": tab, "title": h, "lastOutputAt": last})
    if pid:
        sess.setdefault(wid, []).append({"sessionId": "pty-" + h, "pid": pid, "paneKey": h})
        ps += [f"{pid:5d}     1 login", f"{pid+1:5d} {pid:5d} -zsh"] + [f"{pid+2+i:5d} {pid+1:5d} /usr/bin/{k}" for i, k in enumerate(kids)]
    if scr is not None:
        open(f"{F}/read-{h}.txt", "w").write(scr)
json.dump({"result": {"terminals": terms}}, open(F + "/term.json", "w"), ensure_ascii=False)
json.dump({"result": {"worktrees": [{"worktreeId": k, "sessions": v} for k, v in sess.items()]}}, open(F + "/diag.json", "w"))
wps = [{"worktreeId": x["id"], "workspaceKind": "git", "agents": []} for x in W] + [{"worktreeId": "folder-1", "workspaceKind": "folder-workspace", "agents": []}]
next(x for x in wps if x["worktreeId"].endswith("/c_ps_agent"))["agents"] = [{"agentType": "claude", "state": "working"}]
json.dump({"result": {"worktrees": wps, "truncated": False, "totalCount": len(wps)}}, open(F + "/wps.json", "w"))
open(F + "/ps.txt", "w").write("\n".join(ps) + "\n")
st = lambda k, t: {"identifier": k, "state": {"type": t, "name": t}}
json.dump({"result": {"issues": [st("PER-1", "started"), st("PER-2", "completed")]}}, open(F + "/lin-PER.json", "w"))
json.dump({"result": {"issues": [st("XXX-1", "completed"), st("XXX-2", "completed")]}}, open(F + "/lin-XXX.json", "w"))
json.dump({"result": {"issues": [st("YYY-1", "completed")]}}, open(F + "/lin-YYY.json", "w"))
json.dump({"result": {"issues": [st("OKX-1", "completed")]}}, open(F + "/lin-OKX.json", "w"))
pr = lambda num, s, br, owner="zz": {"number": num, "state": s, "headRefName": br, "headRepositoryOwner": {"login": owner},
                                    "headRefOid": "0" * 40, "baseRefName": "main"}
# newest first, like gh; a list call without --head only sees the newest one (stands in for the --limit cut-off)
json.dump([pr(61, "MERGED", "br/c_head_pr_merged") | {"headRefOid": MERGED_SHA}, pr(62, "MERGED", "br/c_nolin_pr") | {"headRefOid": NOLIN_SHA}, pr(60, "MERGED", "br/newest"), pr(1, "OPEN", "br/c_open_pr"), pr(2, "MERGED", "br/c_merged_inreview"),
           pr(3, "MERGED", "br/c_self"), pr(50, "MERGED", "other"), pr(4, "OPEN", "br/c_old_open_pr")], open(F + "/pr-zz__proj.json", "w"))
json.dump([pr(999, "OPEN", "other-branch"), pr(5, "OPEN", "br/c_not_done", owner="someone-else"), pr(50, "OPEN", "br/c_linked_dup", owner="zz")],
          open(F + "/pr-up__proj.json", "w"))
json.dump([pr(7, "MERGED", "br/ops_common")], open(F + "/pr-zz__ops.json", "w"))
json.dump([pr(8, "OPEN", "br/c_moved_open", owner="newowner")], open(F + "/pr-newowner__moved.json", "w"))
json.dump([], open(F + "/pr-zz__x.json", "w"))
json.dump({"zz/moved": "newowner/moved"}, open(F + "/renames.json", "w"))
PY
json_repos='{"result":{"repos":[{"id":"r-proj","displayName":"proj","path":"'"$P"'","kind":"git"},{"id":"r-ops","displayName":"ops","path":"'"$T"'/repos/ops","kind":"git"},{"id":"r-nogh","displayName":"nogh","path":"'"$T"'/repos/ops","kind":"git"},{"id":"r-x","displayName":"x/proj","path":"'"$X"'","kind":"git"}]}}'
printf '%s' "$json_repos" >"$F/repos.json"

cat >"$T/bin/orca" <<'SH'
#!/bin/bash
# fake orca: read-only subcommands answer from $WS_FIX; rm / close are logged and "succeed" unless listed in fail-rm
echo "$*" >>"$WS_FIX/orca-calls.log"
case "$1 $2" in
"worktree list") [ -f "$WS_FIX/fail-wt" ] && exit 1; cat "$WS_FIX/wt.json";;
"worktree ps") [ -f "$WS_FIX/fail-wps" ] && exit 1; cat "$WS_FIX/wps.json";;
"terminal list") [ -f "$WS_FIX/fail-term" ] && exit 1; cat "$WS_FIX/term.json";;
"diagnostics memory") [ -f "$WS_FIX/fail-diag" ] && exit 1; cat "$WS_FIX/diag.json";;
"repo list") cat "$WS_FIX/repos.json";;
"terminal read") h=; scr=; while [ $# -gt 0 ]; do [ "$1" = --terminal ] && h=$2; [ "$1" = --screen ] && scr=1; shift; done
  [ -z "$scr" ] && [ -f "$WS_FIX/fail-stream-$h" ] && exit 1
  [ -f "$WS_FIX/read-$h.txt" ] || exit 1
  python3 -I -c 'import json,sys; print(json.dumps({"result":{"terminal":{"tail":open(sys.argv[1]).read().splitlines()}}}))' "$WS_FIX/read-$h.txt";;
"terminal show") h=; while [ $# -gt 0 ]; do [ "$1" = --terminal ] && h=$2; shift; done
  python3 -I -c 'import json,sys; t=[x for x in json.load(open(sys.argv[1]))["result"]["terminals"] if x["handle"]==sys.argv[2]]
print(json.dumps({"result":{"terminal":t[0]}})) if t else sys.exit(1)' "$WS_FIX/term.json" "$h";;
"linear list-issues") t=; while [ $# -gt 0 ]; do [ "$1" = --team ] && t=$2; shift; done
  [ -f "$WS_FIX/lin-$t.json" ] || exit 1; cat "$WS_FIX/lin-$t.json";;
"worktree rm") sel=; while [ $# -gt 0 ]; do [ "$1" = --worktree ] && sel=$2; shift; done
  [ -x "$WS_FIX/on-rm.sh" ] && "$WS_FIX/on-rm.sh"
  if [ -f "$WS_FIX/fail-rm" ] && grep -qxF -- "$sel" "$WS_FIX/fail-rm"; then echo "error: worktree is locked" >&2; exit 1; fi
  echo '{"result":{"removed":true,"by":"ops.admin@example.com"}}';;
*) echo '{"result":{}}';;
esac
SH
cat >"$T/bin/gh" <<'PYGH'
#!/usr/bin/env python3
# fake gh: repo view (renames.json), pr list (--head filters; without --head only the newest PR), pr view, auth status
import json, os, sys
F = os.environ["WS_FIX"]; a = sys.argv[1:]
open(F + "/gh-calls.log", "a").write(" ".join(a) + "\n")
opt = lambda k: a[a.index(k) + 1] if k in a else None
ren = json.load(open(F + "/renames.json"))
if a[:2] == ["auth", "status"]: sys.exit(1 if os.path.exists(F + "/fail-gh-auth") else 0)
if a[:2] == ["repo", "view"]:
    r = a[2]; print(json.dumps({"nameWithOwner": ren.get(r, r)})); sys.exit(0)
r = ren.get(opt("-R"), opt("-R")); f = "%s/pr-%s.json" % (F, r.replace("/", "__"))
if not os.path.exists(f): print("HTTP 404", file=sys.stderr); sys.exit(1)
prs = json.load(open(f))
if a[:2] == ["pr", "list"]:
    h = opt("--head"); print(json.dumps([p for p in prs if p["headRefName"] == h] if h else prs[:1])); sys.exit(0)
if a[:2] == ["pr", "view"]:
    hit = [p for p in prs if str(p["number"]) == a[2]]
    if not hit: print("GraphQL: Could not resolve to a PullRequest with the number of %s." % a[2], file=sys.stderr); sys.exit(1)
    print(json.dumps(hit[0])); sys.exit(0)
sys.exit(2)
PYGH
cat >"$T/bin/lsof" <<'SH'
#!/bin/bash
# fake lsof: -a -d cwd -p <pid> -Fn
echo "$*" >>"$WS_FIX/lsof-calls.log"; p=; while [ $# -gt 0 ]; do [ "$1" = -p ] && p=$2; shift; done
printf 'p%s\nfcwd\nn/fake/cwd/%s\n' "$p" "$p"
SH
chmod +x "$T/bin/orca" "$T/bin/gh" "$T/bin/lsof"
export PATH="$T/bin:$PATH" WS_FIX=$F WS_ORCA=$T/bin/orca WS_GH=$T/bin/gh WS_PS_FILE=$F/ps.txt WS_NOW=$NOW WS_HOST=iMac \
  WS_SELF=$T/wt/c_self WS_SELF_TERM=t_self WS_ARCHIVE=$T/archive WS_NO_DU=1
gitsnap(){ for d in "$P" "$T/repos/ops" "$T"/wt/c_*; do [ -d "$d" ] || continue
  echo "== $d"; git -C "$d" status --porcelain=v1 --ignored 2>&1; git -C "$d" rev-parse HEAD 2>&1; done
  git -C "$P" worktree list --porcelain; git -C "$T/repos/ops" worktree list --porcelain
  ls -la "$T/wt/c_backup/.dev.vars"; }
B=${WS_TEST_BASH:-bash}   # which bash runs the script under test
run(){ out=$1; shift; "$B" "$S" --out "$out" "$@" >"$T/log" 2>&1; echo $?; }
guard_fake(){ [ "$WS_ORCA" = "$T/bin/orca" ] && [ -x "$T/bin/orca" ] && [ "$(command -v orca)" = "$T/bin/orca" ] || {
  echo "refusing to run --execute: orca is not the fake one in $T"; exit 99; }; }
col(){ python3 -I - "$1" "$2" "$3" <<'PY'
import csv, sys
f, key, field = sys.argv[1:]
try: rows = list(csv.DictReader(open(f), delimiter="\t"))
except OSError: rows = []
m = [r for r in rows if r.get("path", "").endswith("/" + key) or r.get("handle") == key]
print(m[0].get(field, "<nocol>") if m else "<none>")
PY
}
# R cases (Zack 10-21 09:18): review records for W19 workspaces
RV=$T/reviews; mkdir -p "$RV/proj" "$RV/x_proj"
rec(){ printf '# review\nPATH: %s\nHEAD: %s\n\nVERDICT: %s\nreason text\n' "$2" "$3" "$4" >"$RV/$1.md"; }
hd(){ git -C "$T/wt/$1" rev-parse HEAD; }
MAIN_SHA=$(git -C "$P" rev-parse main)
rec proj/c_nolin_pr "$T/wt/c_nolin_pr" "$(hd c_nolin_pr)" KEEP                  # R2
rec proj/c_nolin_backup "$T/wt/c_nolin_backup" "$(hd c_nolin_backup)" DELETE_OK  # R3
rec proj/c_nolin_blank "$T/wt/c_nolin_blank" "$MERGED_SHA" DELETE_OK             # R4: stale sha
rec proj/c_rev_inreview "$T/wt/c_rev_inreview" "$(hd c_rev_inreview)" DELETE_OK  # R5
rec proj/c_nolin_gone "$T/wt/c_nolin_gone" "$MAIN_SHA" DELETE_OK                 # R6
rec proj/c_rev_bad "$T/wt/c_rev_bad" "$(hd c_rev_bad)" DELETE_OK; echo "VERDICT: KEEP" >>"$RV/proj/c_rev_bad.md"   # R7
rec proj/c_rev_wrongpath "$T/wt/c_nolin_backup" "$(hd c_rev_wrongpath)" DELETE_OK  # R8
for c in x_rev_ok x_rev_moved x_rev_stale_rec; do rec "x_proj/$c" "$T/wt/$c" "$(hd $c)" DELETE_OK; done
touch "$T/repos/ops/.git/index.lock"   # G11
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
expect c_gh_fail A10/B14 SKIP/W9
expect c_linear_open A11 SKIP/W10
expect c_linear_fail A12 SKIP/W10
expect c_not_done A13 SKIP/W11
expect c_recent A14 SKIP/W12
expect c_zero_recent_commit A14 SKIP/W12
expect c_backup A15 BACKUP_RM/W13
expect c_backup_evidence A15 BACKUP_RM/W13
expect c_nested A15 BACKUP_RM/W13
expect c_cache_only A16/B8 RM/W14
expect c_ops_common A17 RM/W14
expect "c_中文 空格" A18 RM/W14
expect c_not_git A19 SKIP/W7
expect git_only A21 LIST/W16
expect c_gone_local B1 SKIP/W4
expect c_missing B2 SKIP/W4
expect c_gone_pushed B3 RM/W4
expect c_gone_ownbranch B4 SKIP/W4
expect c_testresults B5 BACKUP_RM/W13
expect c_report B6 BACKUP_RM/W13
expect c_tgz B6 BACKUP_RM/W13
expect c_mixed_dir B7 BACKUP_RM/W13
expect c_nested_git B9 SKIP/W13
for c in c_lk_index c_lk_merge c_lk_rebase c_lk_am c_lk_cherry c_lk_bisect c_lk_wtlock c_lk_gone; do expect $c G1-G9 SKIP/W18; done
check "G1 GIT_LOCKED reasons name the lock" 'col "$WT" c_lk_index reason | grep -q "^GIT_LOCKED：index.lock" && col "$WT" c_lk_merge reason | grep -q "^GIT_LOCKED：merge" && col "$WT" c_lk_rebase reason | grep -q "^GIT_LOCKED：rebase" && col "$WT" c_lk_am reason | grep -q "^GIT_LOCKED：rebase" && col "$WT" c_lk_cherry reason | grep -q "^GIT_LOCKED：cherry-pick" && col "$WT" c_lk_bisect reason | grep -q "^GIT_LOCKED：bisect" && col "$WT" c_lk_wtlock reason | grep -q "^GIT_LOCKED：git worktree lock" && col "$WT" c_lk_gone reason | grep -q "^GIT_LOCKED：git worktree lock"'
for c in c_nolin c_nolin_pr c_nolin_gone c_nolin_backup c_nolin_blank; do expect $c N1-N5 SKIP/W19; done
check "N1 NO_LINEAR_ISSUE reason, nothing planned" '[ -z "$(for c in c_nolin c_nolin_pr c_nolin_gone c_nolin_backup c_nolin_blank; do col "$WT" $c reason | grep -v "^NO_LINEAR_ISSUE"; col "$WT" $c planned; done)" ]'
check "N2 c_nolin_pr: the merged PR is seen but does not override" 'col "$WT" c_nolin_pr pr | grep -q "#62 MERGED"'
check "N8 summary counts NO_LINEAR_ISSUE" 'grep -q "NO_LINEAR_ISSUE（W19）：11 个" "$T/out1/summary.md"'
check "R12 without --no-issue-reviews the reviewed ones stay SKIP W19" '[ "$(col "$WT" c_nolin_backup action)/$(col "$WT" c_nolin_gone rule)" = SKIP/W19 ] && ! grep -q "审查记录" "$WT"'
rc=$(run "$T/out11" --no-issue-reviews "$RV"); RW=$T/out11/worktrees.tsv
check "R0 dry-run with --no-issue-reviews exits 0" '[ "$rc" = 0 ]'
rv(){ v=$(col "$RW" "$1" verdict)/$(col "$RW" "$1" rule); r=$(col "$RW" "$1" reason); want=$3; pat=$4; check "$2 $1 -> $3 ($pat) (got $v: $r)" '[ "$v" = "$want" ] && printf "%s" "$r" | grep -q "$pat"'; }
rv c_nolin R1 SKIP/W19 "^NO_LINEAR_ISSUE：没有审查记录 proj/c_nolin.md"
rv c_nolin_pr R2 SKIP/W19 "审查结论是 KEEP"
rv c_nolin_backup R3 BACKUP_RM/W19 "审查记录 DELETE_OK（proj/c_nolin_backup.md）"
rv c_nolin_blank R4 SKIP/W19 "记录里的 HEAD ${MERGED_SHA:0:7} 和现在的 .* 不一样"
rv c_rev_inreview R5 SKIP/W11 "in-review"
rv c_nolin_gone R6 BACKUP_RM/W19 "目录已不在"
rv c_rev_bad R7 SKIP/W19 "审查记录格式不对"
rv c_rev_wrongpath R8 SKIP/W19 "记录里的 PATH 不是这个工作区"
check "R3 c_nolin_backup planned backup + rm, review column set" 'col "$RW" c_nolin_backup planned | grep -q "^备份到 .* orca worktree rm" && [ "$(col "$RW" c_nolin_backup review)" = proj/c_nolin_backup.md ]'
check "R3 summary counts the reviewed BACKUP_RM ones" 'grep -q "审查记录 DELETE_OK 且 HEAD 对得上、走 BACKUP_RM 的：5 个" "$T/out11/summary.md"'
rc=$(run "$T/out12" --no-issue-reviews "$T/no-such-dir")
check "R13 --no-issue-reviews with a missing dir -> exit 2" '[ "$rc" = 2 ]'
check "G11 index.lock in the ops main repo does not lock c_ops_common / c_gh_fail" '[ "$(col "$WT" c_ops_common rule)" = W14 ] && [ "$(col "$WT" c_gh_fail rule)" = W9 ]'
check "G1 summary counts GIT_LOCKED" 'grep -q "GIT_LOCKED（W18）：8 个" "$T/out1/summary.md"'
EM='bob\.smith|Bob\.Smith|ops-admin@|admin\.person|ops\.admin@'
check "M1 no raw email anywhere in dry-run output or stdout" '! grep -rqE "$EM" "$T/out1" "$T/log"'
check "M1 c_email comment / name masked as first char + domain" 'col "$WT" c_email comment | grep -qF "B***@example.com" && col "$WT" c_email comment | grep -qF "o***@corp.example.org" && [ "$(col "$WT" c_email name)" = "b***@example.com" ]'
check "M2 email cut by the 60-char limit is still masked" 'col "$WT" c_email_long comment | grep -qF "a***@"'
check "M3 version strings pkg@1.2.3 / node@20 left alone" 'col "$WT" c_email comment | grep -qF "pkg@1.2.3 node@20"'
check "M5 file name page@<hash>.webm is not taken for an email" 'grep -qF "test-results/run1/page@0a1b2c3d.webm" "$T/out1/backup-files.tsv"'
check "M4 terminals.tsv worktree column masked" 'grep -qF "b***@example.com" "$TM" && ! grep -qE "$EM" "$TM"'
expect c_fifo B10 SKIP/W13
expect c_moved_open B11 SKIP/W9
expect c_old_open_pr B12 SKIP/W9
expect c_linked_dup B13 SKIP/W9
expect c_merged_inreview B15 SKIP/W11
expect c_sleep_cap B15 SKIP/W11
expect c_ps_agent B16 SKIP/W5
expect c_termhost B17 SKIP/W6
expect c_build B28 RM/W14
expect c_head_unmerged B34 SKIP/W17
expect c_linear_done_unmerged B35 SKIP/W17
expect c_head_pr_merged B36 RM/W14
check "B36 c_head_pr_merged merged_via names PR #61" 'col "$WT" c_head_pr_merged merged_via | grep -q "PR #61 的 head"' 
check "B1 c_gone_local reason names the commit $GONE_SHA" 'col "$WT" c_gone_local reason | grep -q "$GONE_SHA"'
check "B3 c_gone_pushed reason says the git worktree record goes too" 'col "$WT" c_gone_pushed reason | grep -q "git worktree 记录"'
check "B5 c_testresults backup lists test-results" '[ "$(col "$WT" c_testresults backup)" = "test-results" ]'
check "B7 c_mixed_dir backup is the whole scratch dir" '[ "$(col "$WT" c_mixed_dir backup)" = "scratch" ]'
check "B29 backup-files.tsv lists scratch/notes.txt and scratch/TASK.md of c_mixed_dir" 'grep "c_mixed_dir" "$T/out1/backup-files.tsv" | grep -q "scratch/notes.txt" && grep "c_mixed_dir" "$T/out1/backup-files.tsv" | grep -q "scratch/TASK.md"'
check "B8 c_cache_only rebuild column shows both cache entries" 'col "$WT" c_cache_only rebuild | grep -q "^2 项"'
check "B15 c_merged_inreview reason says 状态冲突" 'col "$WT" c_merged_inreview reason | grep -q "状态冲突"'
check "B24 reason has no time-derived number (c_recent)" '[ "$(col "$WT" c_recent reason)" = "最近 24 小时内有活动" ]'
check "A15 c_backup lists .dev.vars and .orca-task" 'b=$(col "$WT" c_backup backup); case "$b" in *.dev.vars*) case "$b" in *.orca-task*) true;; *) false;; esac;; *) false;; esac'
check "A18 every TSV row has the header's column count" '(for f in "$WT" "$TM" "$T/out1/backup-files.tsv"; do awk -F"\t" "NR==1{n=NF} NF!=n{bad=1} END{exit bad}" "$f" || exit 1; done)'
RMPAT="orca worktree rm --worktree 'id:"
check "A20 planned rm has no --force" '! grep -q -- "--force" "$WT" && grep -qF "$RMPAT" "$WT"'
check "M7 comment column masks URLs" '! grep -q "example.invalid" "$WT" && col "$WT" c_ops_common comment | grep -q "<url>"'
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
texp t_agent_sib "B18'" CLOSE/T4
texp t_agent_sib_fresh "B18'" SKIP/T7
texp t_self_sib B19 SKIP/T3
texp t_folder B20 SKIP/T8
texp t_main B20 SKIP/T8
texp t_fresh B21 SKIP/T7
texp t_nolast B21 SKIP/T7
texp t_midoutput B22 SKIP/T2
check "B33 every CLOSE row has an archive path" '[ -z "$(awk -F"\t" "FNR==1{for(i=1;i<=NF;i++){if(\$i==\"verdict\")v=i;if(\$i==\"archive\")a=i};next} \$v==\"CLOSE\" && \$a==\"\"" "$TM")" ] && grep -q "/terminals/" "$TM" && grep -q "README.txt" "$T/out1/summary.md"'
check "B23 no planned close uses --tab" '! grep -q -- "--tab" "$TM" && grep -q "orca terminal close --terminal t_empty" "$TM"'
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
check "A6 diagnostics fails -> worktrees with terminals are SKIP W6, nothing to CLOSE, exit 5" '[ "$rc" = 5 ] && [ "$(col "$T/out6/worktrees.tsv" c_termhost action)" = SKIP ] && ! grep -q "	CLOSE	" "$T/out6/terminals.tsv"'
touch "$F/fail-wps"; rc=$(run "$T/out7"); rm -f "$F/fail-wps"
check "B16 worktree ps fails -> no RM at all, exit 5" '[ "$rc" = 5 ] && ! grep -qE "	(RM|BACKUP_RM)	" "$T/out7/worktrees.tsv"'
rc=$(run "$T/out8" --dry-run)
check "B25 --dry-run is accepted (exit 0)" '[ "$rc" = 0 ]'
rc=$(run "$T/out9" --precheck)
check "B27 --precheck writes output and exits 1" '[ "$rc" = 1 ] && [ -s "$T/out9/summary.md" ]'
rc=$(WS_REBUILD_DIRS=node_modules run "$T/out10")
check "B28 WS_REBUILD_DIRS=node_modules -> c_cache_only must back up dist (BACKUP_RM)" '[ "$(col "$T/out10/worktrees.tsv" c_cache_only verdict)" = BACKUP_RM ]'
rc=$(WS_ARCHIVE=$T/archive2 "$B" "$S" >"$T/log" 2>&1; echo $?)
check "B26 default output goes under the archive root, not the ops workspace" '[ "$rc" = 0 ] && ls "$T/archive2/reports"/ws-cleanup-*/summary.md >/dev/null 2>&1'

# ---------------- --execute against the fake orca (project x only) ----------------
guard_fake
XD=$T/xd; rc=$(run "$XD" --repo r-x --no-issue-reviews "$RV")
check "E0 scoped dry-run of project x lists only x worktrees" '[ "$rc" = 0 ] && ! grep -q "/wt/c_" "$XD/worktrees.tsv" && [ "$(col "$XD/worktrees.tsv" x_ok verdict)" = RM ]'
check "B30 t_x_agent (agent itself) SKIP T1; t_x_agent_sib CLOSE" '[ "$(col "$XD/terminals.tsv" t_x_agent rule)" = T1 ] && [ "$(col "$XD/terminals.tsv" t_x_agent_sib verdict)" = CLOSE ]'
check "R11 x_rev_ok / x_rev_moved / x_rev_stale_rec are BACKUP_RM W19 in the dry-run" '[ "$(for c in x_rev_ok x_rev_moved x_rev_stale_rec; do col "$XD/worktrees.tsv" $c verdict; col "$XD/worktrees.tsv" $c rule; done | tr "\n" ,)" = "BACKUP_RM,W19,BACKUP_RM,W19,BACKUP_RM,W19," ]'
check "E0 x_bk / x_rmfail / x_sha are BACKUP_RM, terminals t_x_close / t_late / t_late_tab are CLOSE" '[ "$(col "$XD/worktrees.tsv" x_bk verdict)$(col "$XD/worktrees.tsv" x_rmfail verdict)$(col "$XD/worktrees.tsv" x_sha verdict)" = BACKUP_RMBACKUP_RMBACKUP_RM ] && [ "$(col "$XD/terminals.tsv" t_x_close verdict)$(col "$XD/terminals.tsv" t_late verdict)$(col "$XD/terminals.tsv" t_late_tab verdict)" = CLOSECLOSECLOSE ]'
python3 -I -c 'import sys; L=open(sys.argv[1]).read().splitlines(); open(sys.argv[1],"w").write("\n".join(l for l in L if "/x_notlisted\t" not in l)+"\n")' "$XD/worktrees.tsv"
mkdir -p "$T/wt/x_listchanged/.orca-task"; printf 'late\n' >"$T/wt/x_listchanged/.orca-task/new.md"
printf '%s\n' "id:r-x::$T/wt/x_rmfail" >"$F/fail-rm"
cat >"$F/on-rm.sh" <<SH
#!/bin/bash
[ -f "$F/on-rm.done" ] && exit 0; touch "$F/on-rm.done"
python3 -I - "$F/wps.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
next(x for x in d["result"]["worktrees"] if x["worktreeId"].endswith("/x_q10"))["agents"] = [{"agentType": "pi", "state": "working"}]
json.dump(d, open(sys.argv[1], "w"))
PY
SH
chmod +x "$F/on-rm.sh"
touch "$F/fail-stream-t_x_arcfail"
( while :; do echo grow >>"$T/wt/x_sha/.orca-task/grow.log"; sleep 0.01; done ) & APPENDER=$!
: >"$F/orca-calls.log"
XE=$T/xe; ( WS_PAUSE_FILE=$T/go "$B" "$S" --execute --only-from "$XD/worktrees.tsv" --close-terminals --repo r-x --no-issue-reviews "$RV" --out "$XE" >"$T/xlog" 2>&1; echo $? >"$T/xrc" ) &
XPID=$!
for _ in $(seq 1 600); do [ -f "$T/go.ready" ] && break; sleep 0.1; done
check "E4 execute stops at the pause point" '[ -f "$T/go.ready" ]'
printf 'n\n' >"$T/wt/x_late/new.txt"                                                     # E4a
touch "$(git -C "$T/wt/x_late_lock" rev-parse --absolute-git-dir)/index.lock"            # G10
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); next(x for x in d["result"]["worktrees"] if x["path"].endswith("/x_late_nolin"))["linkedLinearIssue"]=None; json.dump(d,open(sys.argv[1],"w"))' "$F/wt.json"   # N6
git -C "$X" fetch -q "$T/origin.git" "+refs/heads/br/c_head_unmerged:refs/remotes/origin/br/c_head_unmerged"           # R9
git -C "$T/wt/x_rev_moved" checkout -q --detach origin/br/c_head_unmerged
rec x_proj/x_rev_stale_rec "$T/wt/x_rev_stale_rec" "$MERGED_SHA" DELETE_OK                                               # R10
printf 'c\n' >"$T/wt/x_late2/c"; git -C "$T/wt/x_late2" add c; git -C "$T/wt/x_late2" commit -qm late     # E4b
python3 -I - "$F" "$T" <<'PY'
import json, os, sys
F, T = sys.argv[1:]
d = json.load(open(F + "/wps.json"))                                                  # E4c: agent shows up in x_late3
next(x for x in d["result"]["worktrees"] if x["worktreeId"].endswith("/x_late3"))["agents"] = [{"agentType": "claude", "state": "working"}]
json.dump(d, open(F + "/wps.json", "w"))
p = json.load(open(F + "/pr-zz__x.json"))                                             # E4d: PR opened for x_late4
p.append({"number": 9, "state": "OPEN", "headRefName": "br/x_late4", "headRepositoryOwner": {"login": "zz"}, "headRefOid": "0" * 40, "baseRefName": "main"})
json.dump(p, open(F + "/pr-zz__x.json", "w"))
json.dump({"result": {"issues": [{"identifier": "XXX-1", "state": {"type": "started", "name": "started"}}]}}, open(F + "/lin-XXX.json", "w"))  # E4d Linear; XXX-2 gone
os.remove(F + "/lin-YYY.json")                                                         # Zack 03:37: Linear query fails at delete time
open(F + "/ps.txt", "a").write(" 1299  1212 /usr/bin/sleep\n")                     # E6: t_late runs something
t = json.load(open(F + "/term.json"))                                                  # E7: new pane in t_late_tab's tab
base = next(x for x in t["result"]["terminals"] if x["handle"] == "t_late_tab")
t["result"]["terminals"].append(dict(base, handle="t_newpane", ptyId="pty-t_newpane"))
json.dump(t, open(F + "/term.json", "w"))
PY
touch "$T/go"; wait $XPID; kill $APPENDER 2>/dev/null; wait $APPENDER 2>/dev/null; APPENDER=
xrc=$(cat "$T/xrc"); cp "$T/xlog" "$T/log"
XW=$XE/worktrees.tsv; XT=$XE/terminals.tsv
res(){ col "$XW" "$1" result; }
check "E2 exit code 3 (x_rmfail failed)" '[ "$xrc" = 3 ]'
check "E0 x_ok removed" '[ "$(res x_ok)" = "已 rm" ]'
check "E3 x_bk backed up then removed" 'res x_bk | grep -q "^已备份到 .*；已 rm$"'
BK=$(ls -d "$T/archive"/*/x_proj/x_bk 2>/dev/null | head -1)
check "E3 backup dir 700, .dev.vars 600, MANIFEST present (L4: repo name x/proj -> x_proj)" '[ -n "$BK" ] && [ "$(stat -f %Lp "$BK" 2>/dev/null || stat -c %a "$BK")" = 700 ] && [ "$(stat -f %Lp "$BK/.dev.vars" 2>/dev/null || stat -c %a "$BK/.dev.vars")" = 600 ] && [ -s "$BK/MANIFEST.sha256" ]'
check "E3/L3 original .dev.vars left in place" '[ -f "$T/wt/x_bk/.dev.vars" ] && [ -f "$T/wt/x_rmfail/.dev.vars" ]'
check "E1 x_sha: BACKUP_FAIL on sha mismatch and no rm call" 'res x_sha | grep -q "^BACKUP_FAIL：sha 对不上" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q "/x_sha"'
check "E2 x_rmfail: failure text recorded, rm called exactly once, never --force" 'res x_rmfail | grep -q "rm 失败（不重试、不加 --force）：error: worktree is locked" && [ "$(grep "worktree rm" "$F/orca-calls.log" | grep -c "/x_rmfail")" = 1 ] && ! grep -q -- "--force" "$F/orca-calls.log"'
check "E8 x_e8a_noperm: ERROR, x_e8b_after still removed, outputs written" 'res x_e8a_noperm | grep -q "^ERROR：PermissionError" && [ "$(res x_e8b_after)" = "已 rm" ] && [ -s "$XE/summary.md" ] && [ -s "$XT" ]'
check "E4a x_late skipped (W7)" 'res x_late | grep -q "跳过：重新判定变成 SKIP W7"'
check "E4b x_late2 skipped (W8)" 'res x_late2 | grep -q "跳过：重新判定变成 SKIP W8"'
check "E4c x_late3 skipped (W5)" 'res x_late3 | grep -q "跳过：重新判定变成 SKIP W5"'
check "E4d x_late4 skipped (W9, PR opened)" 'res x_late4 | grep -q "跳过：重新判定变成 SKIP W9"'
check "E4d x_late5 skipped (W10, Linear reopened)" 'res x_late5 | grep -q "跳过：重新判定变成 SKIP W10"'
check "L37 x_lin_fail: Linear query fails at delete time -> not removed" 'res x_lin_fail | grep -q "跳过：重新判定变成 SKIP W10（Linear 查不到" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_lin_fail'
check "L37 x_lin_gone: issue missing at delete time -> not removed" 'res x_lin_gone | grep -q "跳过：重新判定变成 SKIP W10（Linear 查不到" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_lin_gone'
check "E5 x_q10 skipped after an agent showed up mid-run; x_q01-x_q09 removed" 'res x_q10 | grep -q "SKIP W5" && [ "$(for i in 01 02 03 04 05 06 07 08 09; do res x_q$i; done | sort -u)" = "已 rm" ]'
check "G10 x_late_lock locked after the dry-run: skipped as W18, no backup, no rm" 'res x_late_lock | grep -q "跳过：重新判定变成 SKIP W18（GIT_LOCKED" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_late_lock && ! grep -q "x_late_lock" "$XE/journal.tsv"'
check "N6 x_late_nolin: Linear unlinked after the dry-run -> skipped as W19, no rm" '[ "$(col "$XD/worktrees.tsv" x_late_nolin verdict)" = RM ] && res x_late_nolin | grep -q "跳过：重新判定变成 SKIP W19（NO_LINEAR_ISSUE" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_late_nolin'
check "R9 x_rev_moved: HEAD moved after the dry-run -> skipped as W19, no backup, no rm" 'res x_rev_moved | grep -q "^跳过：重新判定变成 SKIP W19（NO_LINEAR_ISSUE：记录里的 HEAD" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_rev_moved && ! grep -q "x_rev_moved" "$XE/journal.tsv"'
check "R10 x_rev_stale_rec: record changed after the dry-run -> skipped as W19, no rm" 'res x_rev_stale_rec | grep -q "^跳过：重新判定变成 SKIP W19（NO_LINEAR_ISSUE：记录里的 HEAD ${MERGED_SHA:0:7}" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_rev_stale_rec'
mode(){ stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
RB=$(ls -d "$T/archive"/*/x_proj/x_rev_ok 2>/dev/null | head -1)
check "R11 x_rev_ok backed up with NO-ISSUE-REVIEW.md (600, in MANIFEST, same bytes) and removed" 'res x_rev_ok | grep -q "^已备份到 .*；已 rm$" && [ -n "$RB" ] && [ "$(mode "$RB/NO-ISSUE-REVIEW.md")" = 600 ] && grep -q "  NO-ISSUE-REVIEW.md$" "$RB/MANIFEST.sha256" && cmp -s "$RB/NO-ISSUE-REVIEW.md" "$RV/x_proj/x_rev_ok.md"'
check "M4 journal / execute output: orca's email masked" '! grep -rqE "$EM" "$XE" "$T/xlog" && grep -qF "o***@example.com" "$XE/journal.tsv"'
check "E14 x_notlisted (not in --only-from) untouched" '[ "$(res x_notlisted)" = "没动：不在 --only-from 名单里" ] && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_notlisted'
check "E15 x_listchanged: backup list changed -> skipped" 'res x_listchanged | grep -q "^跳过：" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_listchanged'
check "E6 t_late got a process -> not closed" 'col "$XT" t_late result | grep -q "^跳过：重新判定变成 SKIP T6" && ! grep -q "terminal close --terminal t_late " "$F/orca-calls.log"'
check "E7 only t_late_tab, t_x_agent_sib, t_x_close closed, never --tab, t_newpane untouched" '[ "$(grep "^terminal close" "$F/orca-calls.log" | sed "s/ --json//" | sort | tr "\n" ,)" = "terminal close --terminal t_late_tab,terminal close --terminal t_x_agent_sib,terminal close --terminal t_x_close," ]'
TA=$(ls -d "$T/archive/terminals"/*/t_x_close 2>/dev/null | head -1)
check "B31 t_x_close archived before close: dir 700, scrollback / meta (with cwd) / README 600" '[ -n "$TA" ] && [ "$(mode "$TA")" = 700 ] && (for f in scrollback.txt meta.json README.txt; do [ "$(mode "$TA/$f")" = 600 ] || exit 1; done) && grep -q "/fake/cwd/" "$TA/meta.json" && col "$XT" t_x_close result | grep -q "^已存档到 .*t_x_close；已关$"'
check "B31 t_x_agent_sib (companion shell) archived and closed" 'col "$XT" t_x_agent_sib result | grep -q "^已存档到 .*；已关$"'
check "B32 t_x_arcfail: archive failed -> not closed, counted as a failure" 'col "$XT" t_x_arcfail result | grep -q "^没关：存档失败" && ! grep -q "terminal close --terminal t_x_arcfail" "$F/orca-calls.log"'
check "B30 t_x_agent never closed" '! grep -q "terminal close --terminal t_x_agent " "$F/orca-calls.log" && ! grep -q "terminal close --terminal t_x_agent$" "$F/orca-calls.log"'
check "B31 dry-run never ran lsof" '[ "$(grep -c . "$F/lsof-calls.log")" = 3 ]'
check "E16 journal has rm-start / rm-end for x_ok" 'grep -q "rm-start	r-x::.*/x_ok" "$XE/journal.tsv" && grep -q "rm-end	r-x::.*/x_ok	0" "$XE/journal.tsv"'
check "E3 fake secrets not in execute output or stdout" '! grep -rq -e "$SECRET" "$XE" "$T/xlog"'
check "D3 x_sha / x_e8a_noperm: half-copied backup set aside as .failed-*, nothing left under the real name" '[ -z "$(ls -d "$T/archive"/*/*/x_sha "$T/archive"/*/*/x_e8a_noperm 2>/dev/null)" ] && ls -d "$T/archive"/*/*/x_sha.failed-* >/dev/null 2>&1 && ls -d "$T/archive"/*/*/x_e8a_noperm.failed-* >/dev/null 2>&1 && res x_sha | grep -q "拷了一半的移到 .*x_sha.failed-"'
: >"$F/orca-calls.log"
{ cat "$XD/worktrees.tsv"; awk -F'\t' -v OFS='\t' 'NR > 1 && $7 == "RM" { $2 = "r-x::/gone/x_ghost"; print; exit }' "$XD/worktrees.tsv"; } >"$T/xe2-list.tsv"
rc=$(run "$T/xe2" --execute --only-from "$T/xe2-list.tsv" --repo r-x)
check "E12 same-day rerun: x_rmfail BACKUP_FAIL 备份目录已存在, no rm for it" 'col "$T/xe2/worktrees.tsv" x_rmfail result | grep -q "备份目录已存在" && ! grep "worktree rm" "$F/orca-calls.log" | grep -q /x_rmfail'
check "D3 same-day rerun: x_sha not blocked by the failed first attempt" '! col "$T/xe2/worktrees.tsv" x_sha result | grep -q "备份目录已存在"'
check "D1 listed RM that is SKIP when --execute starts: result says so" 'col "$T/xe2/worktrees.tsv" x_late result | grep -q "^跳过：名单里是 RM，这次判定 SKIP W7"'
check "D1 listed id no longer in Orca: journal not-found line" 'grep -q "not-found	r-x::/gone/x_ghost" "$T/xe2/journal.tsv"'
check "E19 without --close-terminals no terminal is closed" '! grep -q "^terminal close" "$F/orca-calls.log" && col "$T/xe2/terminals.tsv" t_x_close result | grep -q "没带 --close-terminals"'
: >"$F/orca-calls.log"
rc=$(WS_GH=$T/bin/nogh run "$T/xe3" --execute --only-from "$XD/worktrees.tsv" --repo r-x)
check "E10 no gh -> exit 5, nothing removed, summary says why" '[ "$rc" = 5 ] && ! grep -q "worktree rm" "$F/orca-calls.log" && head -1 "$T/xe3/summary.md" | grep -q "环境不对"'
mkdir -p "$T/archive/.lock"; echo $$ >"$T/archive/.lock/pid"; : >"$F/orca-calls.log"
rc=$(run "$T/xe4" --execute --only-from "$XD/worktrees.tsv" --repo r-x)
check "E11 lock held by a live pid -> exit 6, nothing removed" '[ "$rc" = 6 ] && ! grep -q "worktree rm" "$F/orca-calls.log"'
echo 999999 >"$T/archive/.lock/pid"
rc=$(run "$T/xe5" --execute --only-from "$XD/worktrees.tsv" --repo r-x)
check "E11 stale lock (dead pid) is taken over and the run goes on" '[ "$rc" = 3 ] || [ "$rc" = 0 ]; [ -s "$T/xe5/worktrees.tsv" ] && grep -q "worktree rm" "$F/orca-calls.log" && [ ! -e "$T/archive/.lock" ]'
python3 -I -c 'import sys; L=open(sys.argv[1]).read().splitlines(); rm=[l for l in L if "\tRM\t" in l][0]; open(sys.argv[2],"w").write("\n".join(L+[rm.replace("r-x::","r-proj::",1)])+"\n")' "$XD/worktrees.tsv" "$T/outside.tsv"
cp "$XD/terminals.tsv" "$T/terminals.tsv"; : >"$F/orca-calls.log"
rc=$(run "$T/xe10" --execute --only-from "$T/outside.tsv" --repo r-x)
check "W40 --repo whitelist: one listed candidate outside r-x -> exit 2, nothing removed" '[ "$rc" = 2 ] && ! grep -q "worktree rm" "$F/orca-calls.log"'
rc=$(run "$T/xe6" --execute --repo r-x)
check "E14 --execute without --only-from -> exit 2" '[ "$rc" = 2 ]'
rc=$(WS_HOST=MBA run "$T/xe7" --execute --only-from "$XD/worktrees.tsv"); rc2=$(WS_HOST=imac-old run "$T/xe8" --execute --only-from "$XD/worktrees.tsv")
check "E17 --execute refused on MBA and on a host not named exactly iMac (exit 2)" '[ "$rc" = 2 ] && [ "$rc2" = 2 ]'
rc=$(WS_ORCA=$T/bin/missing-orca run "$T/xe9")
check "E18 WS_ORCA set but missing -> exit 2, no fallback" '[ "$rc" = 2 ] && [ ! -e "$T/xe9" ]'

echo "not run: E13 (needs the real Orca; see scripts/tests/ws-cleanup-drill.sh)"
echo "$((n-fails))/$n passed"; [ $fails = 0 ]
