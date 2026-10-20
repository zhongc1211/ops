#!/bin/bash
# run-drill.sh OUT_DIR [pre|post|both] [SCENARIO...]
# Scratch drill for watchdog.sh (FAILURE-MODES.md). Runs in a throwaway Debian container on any Docker host, never on box,
# touches no real tunnel, webhook or secret. pre = watchdog.sh at PRE_REF (default 10b4975 = the script live on box since
# 2026-10-18, sha256 5845f11b...) made runnable by prefix-shim.sh (a newer PRE_REF runs as is); post = orca-remote/watchdog.sh in this checkout.
# pre and post run in parallel, one container each. Output: OUT_DIR/{pre,post}/results.tsv, raw logs per scenario, summary.md.
# Exit 0 = every requested variant produced results and post has no FAIL.
set -euo pipefail
OUT=${1:?usage: run-drill.sh OUT_DIR [pre|post|both] [SCENARIO...]}; WHICH=${2:-both}; shift $(( $# >= 2 ? 2 : 1 )); SCEN="$*"
D=$(cd "$(dirname "$0")" && pwd); REPO=$(git -C "$D" rev-parse --show-toplevel); PRE_REF=${PRE_REF:-10b4975}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
IMG=ops-watchdog-drill; docker build -q -t $IMG "$D" >/dev/null
git -C "$REPO" show "$PRE_REF:orca-remote/watchdog.sh" >"$OUT/base-watchdog.sh"
# a base that already reads the WATCHDOG_* overrides (rev 2026-10-19 and later, e.g. PRE_REF=origin/main) runs unshimmed
if grep -q 'WATCHDOG_LOG:-' "$OUT/base-watchdog.sh"; then cp "$OUT/base-watchdog.sh" "$OUT/pre-watchdog.sh"
else bash "$D/prefix-shim.sh" "$OUT/base-watchdog.sh" >"$OUT/pre-watchdog.sh"; fi
diff "$OUT/base-watchdog.sh" "$OUT/pre-watchdog.sh" >"$OUT/pre-shim.diff" || true
cp "$REPO/orca-remote/watchdog.sh" "$OUT/post-watchdog.sh"
{ echo "date: $(date '+%F %T %Z')"; echo "host: $(hostname) $(uname -sm), docker $(docker version -f '{{.Server.Version}}')"
  echo "repo HEAD: $(git -C "$REPO" rev-parse HEAD)$(git -C "$REPO" diff --quiet HEAD -- orca-remote || echo ' (orca-remote has uncommitted changes)')"
  echo "pre: $PRE_REF ($(git -C "$REPO" rev-parse --short "$PRE_REF")):orca-remote/watchdog.sh sha256 $(shasum -a 256 "$OUT/base-watchdog.sh" | cut -c1-64) (shimmed: pre-shim.diff)"
  echo "post: orca-remote/watchdog.sh sha256 $(shasum -a 256 "$OUT/post-watchdog.sh" | cut -c1-64)"
  echo "command: $0 $OUT $WHICH $SCEN"; } >"$OUT/run-info.txt"
run(){ docker run --rm --init -e TZ=SGT-8 --name "drill-$1-$$" -v "$REPO/orca-remote:/drill-src:ro" -v "$OUT:/out" $IMG \
         bash /drill-src/drill/in-container.sh "$1" "/out/$1-watchdog.sh" "/out/$1" $SCEN >"$OUT/$1.console.log" 2>&1; }
pids=(); for v in pre post; do { [ "$WHICH" = both ] || [ "$WHICH" = $v ]; } && { run $v & pids+=($!); }; done
for p in "${pids[@]}"; do wait "$p" || true; done
{ echo "# watchdog drill results"; echo; sed 's/^/    /' "$OUT/run-info.txt"; echo
  echo "| scenario | check | pre | post | pre detail | post detail |"; echo "|---|---|---|---|---|---|"
  python3 - "$OUT" <<'PY'
import csv, sys, os
out = sys.argv[1]; rows = {}; order = []
for v in ("pre", "post"):
    p = os.path.join(out, v, "results.tsv")
    if not os.path.exists(p): continue
    for lab, sc, chk, res, det in csv.reader(open(p), delimiter="\t"):
        k = (sc, chk)
        if k not in rows: rows[k] = {}; order.append(k)
        rows[k][v] = (res, det)
for k in order:
    r = rows[k]; g = lambda v, i: r.get(v, ("not run", ""))[i].replace("|", "/")
    print(f"| {k[0]} | {k[1]} | {g('pre',0)} | {g('post',0)} | {g('pre',1)} | {g('post',1)} |")
PY
  echo; for v in pre post; do [ -f "$OUT/$v/results.tsv" ] && echo "$v: $(grep -c $'\tPASS\t' "$OUT/$v/results.tsv") PASS, $(grep -c $'\tFAIL\t' "$OUT/$v/results.tsv") FAIL"; done
} >"$OUT/summary.md"
cat "$OUT/summary.md"
# exit 1 when a requested variant produced no results or post has a FAIL (pre is expected to fail: that is the revert check)
rc=0; for v in pre post; do { [ "$WHICH" = both ] || [ "$WHICH" = $v ]; } || continue
  [ -s "$OUT/$v/results.tsv" ] || { echo "ERROR: $v produced no results.tsv (see $OUT/$v.console.log)" >&2; rc=1; }; done
[ -f "$OUT/post/results.tsv" ] && grep -q $'\tFAIL\t' "$OUT/post/results.tsv" && { echo "post has FAIL rows" >&2; rc=1; }
exit $rc
