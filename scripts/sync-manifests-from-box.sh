#!/bin/bash
# sync-manifests-from-box.sh <project> <D> [mba|imac]: pull one night's session lists from the source host (box unless
# SYNC_SRC_HOST says otherwise) for a night review that runs on the MBA (or the iMac backup) instead of box (PER-79).
# Read-only on the source, deletes nothing on either side.
#   1. copy box:/var/lib/everos-ingest/<project>/<D>/ -> ~/everos-ingest/<project>/<D>/raw/ with tar over ssh (box has no
#      rsync, checked 2026-10-20; extracting overwrites same-named files and deletes nothing), leaving out the big mba/ and
#      imac/ transcript folders: box is reached over a DERP relay (~80 KB/s from the MBA on 10-20, deepvision-site 10-19
#      has 199 MB there). Each Mac's collector keeps the same files in ~/.orca-state/everos-ingest/<project>/<D>/<side>/,
#      so ours (3rd argument) are read locally and the other Mac's are pulled from it directly (ssh <side>, LAN, read-only).
#   2. whatever is still missing is pulled from box (ssh box tar, read-only) into <dst>/box-files/<same path>: box's own
#      sessions (box ~/.claude/projects/...) and any Mac transcript the peer did not have.
#   3. writes <dst>/sessions-<side>.jsonl (and .excluded.jsonl) with every transcript_path rewritten to the local copy,
#      original path kept in transcript_box_path. nightly_addflush.py / everos_readback.py read <dst> via --sessions-dir.
#   4. writes <dst>/SYNC-STATUS: "ok files=N transcripts=N" or "failed <step> <rc>"; the night review treats failed as
#      「清单缺失」 (alarm), the same as a missing list on box.
# Exit: 0 ok; 3 cannot reach the source or the directory is not there; 4 transcript pull failed; 5 rewrite failed; 2 usage.
# Source (configuration, B2a): SYNC_SRC_HOST (default box; local, or this machine's own short hostname, = read here
# without ssh) and SYNC_SRC_ROOT (default /var/lib/everos-ingest, an absolute path on the source host). Steps 1 and 2 read
# from it the same way whichever host it is.
# Overrides (drills): SYNC_DST_ROOT (~/everos-ingest), SYNC_STAGE_ROOT (~/.orca-state/everos-ingest),
# SYNC_PEERS (default "mba imac": ssh host = side name; "" = source only).
set -u
p=${1:-}; D=${2:-}; side=${3:-}
case "$p" in xinyue|deepvision-site|deepvision-ads|vllm-omni) ;; *) echo "usage: sync-manifests-from-box.sh <xinyue|deepvision-site|deepvision-ads|vllm-omni> <YYYY-MM-DD> [mba|imac]" >&2; exit 2;; esac
case "$D" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "sync-manifests-from-box.sh: bad date '$D'" >&2; exit 2;; esac
case "$side" in ""|mba|imac) ;; *) echo "sync-manifests-from-box.sh: side must be mba or imac" >&2; exit 2;; esac
H=${SYNC_SRC_HOST:-box}; SR=${SYNC_SRC_ROOT:-/var/lib/everos-ingest}; DR=${SYNC_DST_ROOT:-$HOME/everos-ingest}
[ "$(echo "$H" | tr 'A-Z' 'a-z')" = "$(hostname -s | tr 'A-Z' 'a-z')" ] && H=local   # no ssh to itself (fails on the iMac)
src=$SR/$p/$D; dst=$DR/$p/$D; stage=${SYNC_STAGE_ROOT:-$HOME/.orca-state/everos-ingest}/$p/$D
SSH="ssh -o BatchMode=yes -o ConnectTimeout=15"
umask 077; mkdir -p "$dst/raw" "$dst/box-files"
fail(){ echo "failed $1 $2" > "$dst/SYNC-STATUS"; echo "sync-manifests-from-box: $p $D failed at $1 (rc $2)" >&2; exit "$3"; }
onsrc(){ if [ "$H" = local ]; then /bin/bash -c "$1"; else $SSH "$H" "$1"; fi; }   # run one command on the source host
# 1 = no such directory, 255 = source unreachable. One retry: the first ssh over a cold DERP relay path can time out
# (iMac -> box and box -> iMac both did on 2026-10-20 18:42; the second try connected)
onsrc "test -d '$src'"; rc=$?; [ $rc -eq 255 ] && { sleep 5; onsrc "test -d '$src'"; rc=$?; }
[ $rc -eq 0 ] || fail reach $rc 3
onsrc "tar -C '$src' --exclude=./mba --exclude=./imac -czf - ." | tar -xzf - -C "$dst/raw"; rc=$(( ${PIPESTATUS[0]} | ${PIPESTATUS[1]} ))
[ $rc -eq 0 ] || fail copy $rc 3
for peer in ${SYNC_PEERS-mba imac}; do                          # the other Mac's staged transcripts, straight from it
  [ "$peer" = "$side" ] && continue; mkdir -p "$dst/peer/$peer"
  $SSH -o ConnectTimeout=10 "$peer" "cd ~/.orca-state/everos-ingest/$p/$D/$peer 2>/dev/null && tar -czf - ." 2>/dev/null | tar -xzf - -C "$dst/peer/$peer" 2>/dev/null \
    || echo "sync-manifests-from-box: $peer not reachable or has no stage for $p $D; its transcripts come from $H"
done
# map every listed transcript to a local file; "pull" prints the box paths still missing, "final" rewrites the lists
plan(){ python3 -I - "$dst" "$src" "$stage" "$side" "$1" <<'PY'
import json, os, sys
dst, src, stage, side, final = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3], sys.argv[4], sys.argv[5] == "final"
raw = os.path.join(dst, "raw"); nfile = ntx = 0; pull, missing = [], []
def local(tp):
    if tp.startswith(src + "/"):
        rel = tp[len(src) + 1:]
        top = rel.split("/", 1)[0]
        for cand in ([os.path.join(stage, rel)] if side and top == side else []) + \
                    [os.path.join(dst, "peer", rel), os.path.join(raw, rel)]:
            if os.access(cand, os.R_OK):
                return cand
    return os.path.join(dst, "box-files", tp.lstrip("/"))
for f in sorted(os.listdir(raw)):
    if not (f.startswith("sessions-") and f.endswith(".jsonl")):
        continue
    excluded, out = f.endswith(".excluded.jsonl"), []
    for ln in open(os.path.join(raw, f), encoding="utf-8"):
        if not ln.strip():
            continue
        o = json.loads(ln); tp = o.get("transcript_path")
        if tp and tp.startswith("/") and not excluded:      # excluded rows are only counted, never read
            lp = local(tp); ntx += 1
            if not os.access(lp, os.R_OK):
                (missing if final else pull).append(tp)
            o["transcript_box_path"], o["transcript_path"] = tp, lp
        out.append(json.dumps(o, ensure_ascii=False))
    if final:
        tmp = os.path.join(dst, f + ".tmp")
        open(tmp, "w", encoding="utf-8").write("".join(x + "\n" for x in out)); os.replace(tmp, os.path.join(dst, f)); nfile += 1
if not final:
    print("\n".join(sorted(set(pull)))); sys.exit()
if missing:
    sys.exit("transcripts not readable after the pull: " + ", ".join(missing))
open(os.path.join(dst, "SYNC-STATUS"), "w").write(f"ok files={nfile} transcripts={ntx}\n")
print(f"sync-manifests-from-box: {os.path.basename(os.path.dirname(dst))} {os.path.basename(dst)} ok: {nfile} list file(s), {ntx} transcript(s) -> {dst}")
PY
}
need=$(plan pull) || fail plan $? 5
if [ -n "$need" ]; then
  # read-only on the source; GNU tar and bsdtar drop the leading / so the files land at box-files/<path without />
  printf '%s\n' "$need" | onsrc 'tar -czf - --files-from=- 2>/dev/null' | tar -xzf - -C "$dst/box-files"
  rc=$(( ${PIPESTATUS[1]} | ${PIPESTATUS[2]} )); [ $rc -eq 0 ] || fail transcripts $rc 4
fi
plan final || fail rewrite $? 5
