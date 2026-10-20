#!/bin/bash
# run-serve-e2e.sh OUT_DIR [new|old|both]
# Runs e2e-serve-display.sh --real in a throwaway linux/amd64 container (Dockerfile.serve) on any Docker host, never on box.
# new = orca-remote/orca-remote in this checkout; old = OLD_REF:orca-remote/orca-remote (default origin/main = the script live
# on box, pinned to :4) = the revert check: its B-loop must fail. The variants run one after the other (Electron is heavy).
# Needs ORCA_DEB_DIR = a directory with orca-ide_1.4.224_amd64.deb (sha256 f03a25ca..., from box /workspace/ops/orca-app/).
# Output: OUT_DIR/{new,old}.console.log, OUT_DIR/{new,old}/ (b0.log, b1.log, bloop-serve.log), run-info.txt.
# Exit 0 = new passed everything and old failed its B-loop (or was not requested). The old script also fails A and B-start
# (it knows none of the test variables and logs no display=), so only a B-loop FAIL counts as the revert check.
set -euo pipefail
OUT=${1:?usage: run-serve-e2e.sh OUT_DIR [new|old|both]}; WHICH=${2:-both}
D=$(cd "$(dirname "$0")" && pwd); REPO=$(git -C "$D" rev-parse --show-toplevel); OLD_REF=${OLD_REF:-origin/main}
DEBD=${ORCA_DEB_DIR:?set ORCA_DEB_DIR to the directory holding orca-ide_1.4.224_amd64.deb}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
IMG=ops-orca-serve-e2e; docker build -q --platform linux/amd64 -t $IMG -f "$D/Dockerfile.serve" "$DEBD" >/dev/null
cp "$REPO/orca-remote/orca-remote" "$OUT/new-orca-remote"; git -C "$REPO" show "$OLD_REF:orca-remote/orca-remote" >"$OUT/old-orca-remote"
cp "$D/e2e-serve-display.sh" "$OUT/"; chmod +x "$OUT"/*-orca-remote "$OUT/e2e-serve-display.sh"
{ echo "date: $(date '+%F %T %Z')"; echo "host: $(hostname) $(uname -sm), docker $(docker version -f '{{.Server.Version}}'), container linux/amd64 (emulated on $(uname -m))"
  echo "repo HEAD: $(git -C "$REPO" rev-parse HEAD)$(git -C "$REPO" diff --quiet HEAD -- orca-remote || echo ' (orca-remote has uncommitted changes)')"
  echo "deb: $(shasum -a 256 "$DEBD/orca-ide_1.4.224_amd64.deb" | cut -c1-64)"
  echo "new: orca-remote/orca-remote sha256 $(shasum -a 256 "$OUT/new-orca-remote" | cut -c1-64)"
  echo "old: $OLD_REF ($(git -C "$REPO" rev-parse --short "$OLD_REF")):orca-remote/orca-remote sha256 $(shasum -a 256 "$OUT/old-orca-remote" | cut -c1-64)"
  echo "command: $0 $OUT $WHICH"; } >"$OUT/run-info.txt"
run(){ mkdir -p "$OUT/$1"; chmod 777 "$OUT/$1"
  docker run --rm --init --platform linux/amd64 --shm-size=1g -e TZ=SGT-8 --name "serve-e2e-$1-$$" -v "$OUT:/out" $IMG \
    runuser -u box -- env E2E_ARTIFACTS=/out/$1 bash /out/e2e-serve-display.sh /out/$1-orca-remote --real >"$OUT/$1.console.log" 2>&1; }
rc=0
for v in new old; do { [ "$WHICH" = both ] || [ "$WHICH" = $v ]; } || continue
  if run $v; then echo "$v: all PASS"; else echo "$v: has FAIL"; fi
  if [ $v = new ]; then grep -q '^RESULT pass=[0-9]* fail=0$' "$OUT/new.console.log" || rc=1
  elif grep -q '^FAIL B-loop' "$OUT/old.console.log" && ! grep -q '^PASS B-loop: serve-loop' "$OUT/old.console.log"; then
    echo "old: B-loop failed (revert check ok)"
  else echo "ERROR: old orca-remote did not fail B-loop, revert check did not fail" >&2; rc=1; fi
  grep -E '^(PASS|FAIL|RESULT|B1 local|B-loop local|B-loop leftovers|note)' "$OUT/$v.console.log" | sed "s/^/  [$v] /"; done
exit $rc
