#!/bin/bash
# Precheck of the one-shot Orca automation「ops · FDV-68 采集首跑核查」(2026-10-17 00:30 SGT).
# Runs the read-only check under notify-run (webhook to deepvision-ops: done = all PASS, failed = any FAIL),
# then disables this automation, then exits 1 so the model is never started.
set -u
NAME="ops · FDV-68 采集首跑核查"
OUT=/home/box/orca/workspaces/deepvision-site/dv运维-FDV-68-EverOS接入/evidence/FDV-68-everos/firstrun-check-2026-10-17.md
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
notify-run --bot deepvision-ops --task "FDV-68 采集首跑核查（D=2026-10-16）报告 $OUT" --no-tty -- \
  python3 /workspace/ops/everos-ingest/fdv68_firstrun_check.py --out "$OUT"
rc=$?
id=$(orca automations list --json | jq -r --arg n "$NAME" '.. | objects | select(has("id") and .name == $n) | .id' | head -1)
if [ -n "$id" ] && orca automations edit "$id" --disabled --json >/dev/null; then echo "self-disabled $id"; else echo "self-disable FAILED (id=$id)" >&2; fi
echo "check exit=$rc"
exit 1
