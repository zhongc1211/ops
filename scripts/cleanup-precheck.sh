#!/bin/bash
# cleanup-precheck.sh ws|mem: prechecks for the two cleanups that stay on box (PER-79, automations/migration-1020):
#   ws   「ops · 11 Orca 工作区夜间清理 box」 1191c819 (sonnet). Work = an unarchived completed workspace (not a main worktree)
#        idle for more than CLEANUP_WS_DAYS (default 1) days, or a terminal that is disconnected / orphaned, that was not
#        already a candidate at the last run that wrote its report (~/.orca-state/workspace-cleanup/<date>.md). Box keeps
#        dozens of completed workspaces the run rightly skips (unpushed changes...), so "any candidate" would pass every
#        night; still passes at least every CLEANUP_WS_FORCE_DAYS (default 7) days.
#   mem  「ops · 10 内存与 CPU 日常清理 box」 8c40fa83 (sonnet). Work = box-cleanup.sh --count finds a process it would end,
#        or load pressure (box-cleanup.sh --pressure-check: 5-min load > 8 and > 3 h since the last cleanup). Same way of
#        deciding as the iMac pressure-cleanup-precheck.sh, with box's own check (mem-cpu-cleanup.sh is macOS-only).
# No work -> exit 1 (no model, nothing recorded). Work -> heavy-lock.sh acquire <name> (busy -> exit 1, the next trigger in
# the 120-min window retries), then orca-due.sh <name> so orca-fallback.sh can tell a run that did not report ok, exit 0.
# Names: orca-ws-cleanup, box-mem-cpu-cleanup (the second matches the orca-ok.sh call at the end of the 8c40fa83 prompt).
# Overrides (drills): CLEANUP_WT_JSON / CLEANUP_TERM_JSON (files instead of orca worktree / terminal list --json),
# CLEANUP_STATE (~/.orca-state/workspace-cleanup), CLEANUP_COUNT (instead of box-cleanup.sh --count), CLEANUP_NOW (epoch).
set -u
S=$(cd "$(dirname "$0")" && pwd); export PATH=$HOME/.local/bin:$PATH
case "${1:-}" in
ws)
  name=orca-ws-cleanup; st=${CLEANUP_STATE:-$HOME/.orca-state/workspace-cleanup}; mkdir -p "$st"
  wt=${CLEANUP_WT_JSON:-}; tm=${CLEANUP_TERM_JSON:-}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  [ -n "$wt" ] || { wt=$tmp/wt.json; orca worktree list --json > "$wt" || { echo "cleanup-precheck: orca worktree list failed" >&2; exit 1; }; }
  [ -n "$tm" ] || { tm=$tmp/term.json; orca terminal list --json > "$tm" || { echo "cleanup-precheck: orca terminal list failed" >&2; exit 1; }; }
  python3 -I - "$wt" "$tm" "$st" "${CLEANUP_WS_DAYS:-1}" "${CLEANUP_WS_FORCE_DAYS:-7}" "${CLEANUP_NOW:-}" <<'PY' || exit 1
import json, os, sys, time, datetime as dt
wt, tm, st, days, force, now = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
now = float(now) if now else time.time()
cand = set()
for w in json.load(open(wt))["result"]["worktrees"]:
    if w.get("workspaceStatus") == "completed" and not w.get("isArchived") and not w.get("isMainWorktree") \
       and now - (w.get("lastActivityAt") or 0) / 1000 > days * 86400:
        cand.add("ws " + w["path"])
for t in json.load(open(tm))["result"]["terminals"]:
    if not t.get("connected") or t.get("orphaned"):
        cand.add("term " + t["handle"])
last = os.path.join(st, "precheck-last.json")    # candidates when the gate last passed, and that run's date
prev = json.load(open(last)) if os.path.exists(last) else {}
sgt = dt.timezone(dt.timedelta(hours=8))
ran = prev.get("date") and os.path.exists(os.path.join(st, prev["date"] + ".md"))   # that run wrote its report
new = sorted(cand - set(prev.get("candidates", []))) if ran else sorted(cand)
stale = now - prev.get("ts", 0) > force * 86400
print(f"cleanup-precheck ws: {len(cand)} candidate(s), {len(new)} new since the last run"
      + ("" if ran or not prev else f" (last pass {prev.get('date')} wrote no report, counted again)")
      + (", force run (last pass > %g days ago)" % force if stale and cand else ""))
for c in new[:20]:
    print("  new: " + c)
if not cand or not (new or stale):
    sys.exit(1)
json.dump({"ts": now, "date": dt.datetime.fromtimestamp(now, sgt).strftime("%Y-%m-%d"), "candidates": sorted(cand)}, open(last, "w"))
PY
  ;;
mem)
  name=box-mem-cpu-cleanup
  n=${CLEANUP_COUNT:-$(bash "$S/box-cleanup.sh" --count 2>/dev/null)}
  pressure=no; bash "$S/box-cleanup.sh" --pressure-check >/dev/null 2>&1 && pressure=yes
  echo "cleanup-precheck mem: box-cleanup would end ${n:-?} process(es), pressure=$pressure"
  [ "${n:-0}" -gt 0 ] 2>/dev/null || [ $pressure = yes ] || exit 1;;
*) echo "usage: cleanup-precheck.sh ws|mem" >&2; exit 2;;
esac
bash "$S/heavy-lock.sh" acquire "$name" || exit 1
bash "$S/orca-due.sh" "$name"; exit 0
