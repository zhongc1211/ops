#!/bin/bash
# box-load-gate.sh [--est-mb N] [--quiet]: before dispatching a heavy job (build, test suite, playwright, TLC) to box, check
# whether box can take it without tipping into memory thrash. Only reads /proc and one `ps`; safe to run any time.
# Exit 0 = ALLOW, 1 = DENY (dispatch elsewhere: MBA first, then iMac, per dev-bot-rules「派到哪台电脑」), 2 = cannot read.
#
# Why these numbers (ops reports/orca-bot-tunnel-1019, 10-19 SGT): box is 8 cores / 16 GB / no swap. Each of the 4 outages
# began when a batch of parallel tests/builds (+2-4 GB) met sand-host at its 6 GB peak; MemAvailable fell to ~1-2 GB, PSI memory
# full hit 58-70 %, and the whole guest froze 8-29 min. So:
# - MemAvailable after the job (MemAvailable - est) must stay >= MIN_LEFT_MB (default 3584 = 1.5 GB floor + the ~2 GB that
#   sand-host swings within minutes); est defaults to 3072 MB. Replayed over the 10-19 mem-log, 1536 would have allowed a job
#   at 09:35 and 11:45, one minute before two of the freezes; 3584 denies every sample before each freeze (and allows 82 of 711).
# - PSI memory full avg60 < 5 %, memory some avg60 < 20 %, io some avg60 < 30 %: pressure already there = box is reclaiming.
# - load1 < 1.5 x cores.
# - heavy jobs already running < 2 (dev-bot-rules: box takes at most 2 heavy jobs). A heavy job = a workspace (process cwd)
#   with a process matching HEAVY_RE.
# Overrides (tests / tuning): GATE_PROC (default /proc), GATE_EST_MB, GATE_MIN_LEFT_MB, GATE_MAX_HEAVY, GATE_MFULL_MAX,
# GATE_MSOME_MAX, GATE_IO_MAX, GATE_LOAD_X.
P=${GATE_PROC:-/proc}; EST=${GATE_EST_MB:-3072}; MIN_LEFT=${GATE_MIN_LEFT_MB:-3584}; MAX_HEAVY=${GATE_MAX_HEAVY:-2}; QUIET=0
MFULL_MAX=${GATE_MFULL_MAX:-5}; MSOME_MAX=${GATE_MSOME_MAX:-20}; IO_MAX=${GATE_IO_MAX:-30}; LOAD_X=${GATE_LOAD_X:-1.5}
while [ $# -gt 0 ]; do case $1 in --est-mb) EST=$2; shift 2;; --quiet) QUIET=1; shift;; *) echo "usage: $0 [--est-mb N] [--quiet]" >&2; exit 2;; esac; done
HEAVY_RE='playwright|chrom(e|ium).*--headless|node .*(--test|tests/.*\.test\.m?js)|workerd serve|next build|next-build|vitest|jest|tlc2|java .*tla|cargo build|rustc|tsc( |$)|webpack|esbuild|pytest'
avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' "$P/meminfo" 2>/dev/null); swap=$(awk '/^SwapTotal:/ {print int($2/1024)}' "$P/meminfo" 2>/dev/null)
[ -n "$avail" ] || { echo "box-load-gate: cannot read $P/meminfo" >&2; exit 2; }
psi(){ sed -n "s/^$2 .*avg60=\([0-9]*\)\..*/\1/p" "$P/pressure/$1" 2>/dev/null; }
mfull=$(psi memory full); msome=$(psi memory some); iosome=$(psi io some)
read -r l1 l5 l15 _ <"$P/loadavg"; cores=$(grep -c ^processor "$P/cpuinfo" 2>/dev/null); [ "${cores:-0}" -gt 0 ] || cores=$(nproc)
claude=$(pgrep -xc claude 2>/dev/null); claude=${claude:-0}
heavy=$(ps -eo pid=,args= 2>/dev/null | grep -E "$HEAVY_RE" | grep -v -E 'grep|box-load-gate' | while read -r pid _; do
  readlink "$P/$pid/cwd" 2>/dev/null; done | sed -E 's#^(.*/orca/workspaces/[^/]+/[^/]+).*#\1#; s#^(/tmp/claude-[0-9]+/[^/]+).*#\1#' | sort -u)
nheavy=$(printf '%s' "$heavy" | grep -c .)
why=()
[ $((avail-EST)) -lt "$MIN_LEFT" ] && why+=("MemAvailable ${avail}MB - job ${EST}MB < ${MIN_LEFT}MB left")
[ "${mfull:-0}" -ge "$MFULL_MAX" ] && why+=("PSI memory full avg60 ${mfull}% >= ${MFULL_MAX}%")
[ "${msome:-0}" -ge "$MSOME_MAX" ] && why+=("PSI memory some avg60 ${msome}% >= ${MSOME_MAX}%")
[ "${iosome:-0}" -ge "$IO_MAX" ] && why+=("PSI io some avg60 ${iosome}% >= ${IO_MAX}%")
awk -v l="$l1" -v c="$cores" -v x="$LOAD_X" 'BEGIN{exit !(l >= x*c)}' && why+=("load1 $l1 >= $LOAD_X x $cores cores")
[ "$nheavy" -ge "$MAX_HEAVY" ] && why+=("$nheavy heavy jobs running (max $MAX_HEAVY)")
if [ $QUIET = 0 ]; then
  echo "box: MemAvailable ${avail}MB, swap ${swap}MB, PSI mem full/some avg60 ${mfull:-?}/${msome:-?}%, io some ${iosome:-?}%, load $l1/$l5/$l15 on $cores cores, claude sessions $claude"
  echo "heavy jobs ($nheavy):"; printf '%s\n' "$heavy" | sed '/^$/d; s/^/  /'
fi
if [ ${#why[@]} -eq 0 ]; then echo "ALLOW: box can take a ~${EST}MB heavy job"; exit 0; fi
echo "DENY: $(printf '%s; ' "${why[@]}" | sed 's/; $//')"
echo "-> dispatch to MBA (first choice); MBA busy or down -> iMac; box only after the above clears (dev-bot-rules「派到哪台电脑」)"
exit 1
