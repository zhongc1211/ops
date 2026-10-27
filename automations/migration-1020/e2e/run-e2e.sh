#!/bin/bash
# run-e2e.sh [post|pre|both]: B2a (PER-146) drill: the night reviews leave box and no new task runs there any more
# (FAILURE-MODES.md, section B2a, has the ids and the expected results).
#   post  the scripts, defs and prompts in this checkout
#   pre   the same checks against this branch's base (git merge-base HEAD origin/main, git archive, nothing checked out),
#         the revert test: new checks (N*, W0, M5a, M5b) must FAIL there, kept checks (PER-79 behaviour that needs no box)
#         and drill checks (X*, W7c, K1c) must PASS there too; G1a / G1b compare base with this checkout, SKIP on pre
#   both  pre, then post, then revert.tsv and SUMMARY.md (one line per check: class, post, pre, as expected or not)
# Runs on the iMac; the MBA is driven over ssh from a copy in /tmp/b2a-e2e-*, removed at the end.
# Real: /bin/bash 3.2 and the scripts on both Macs, ssh between them, notify-run on both. Not real, so this is a dry-run
# drill and not an e2e of the live automations: webhooks go to mock_webhook.py on 127.0.0.1 of each Mac (fake HOME with fake
# env files, KEY e2e-fake); the store is a local folder, or the iMac (W0, N9); dates are 2099-01-xx (NR_D) with fixed clock
# times (NR_NOW); pmset / ioreg output comes from files; `orca` is a recorder. box is never contacted: the ssh that the gate
# and the sync find first in PATH is ssh-spy (refuses box, logs every call), and the default store (box) is only played by
# fake-ssh.py, which connects nowhere (N8, G1a, G1b). No process gets a signal from the drill: the mocks stop on a stop
# file, caffeinate on its own -t.
# Output: $E2E_OUT (default ~/.orca-state/e2e/migration-1020-nobox/<time>-<mode>): results.tsv (id, result, class, what,
# check), log, META, register-*.out/.err/.rc, register-names.txt, rg-box.txt, make-prompts-check.txt, defs-table.tsv,
# ssh-spy-*.log, hooks.jsonl, mba-hooks.jsonl, g1/ (post), mba-artifacts.tgz, results.sha256.
# Exit 0 = every check as expected for the mode.
set -u
mode=${1:-post}
E=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$E/../../.." && pwd)
BASE=$(git -C "$REPO" merge-base HEAD origin/main)
case "$mode" in
both)
  base=${E2E_OUT:-$HOME/.orca-state/e2e/migration-1020-nobox/$(date +%Y%m%d-%H%M%S)}
  E2E_OUT=$base/pre /bin/bash "$0" pre; rp=$?; E2E_OUT=$base/post /bin/bash "$0" post; rq=$?
  python3 -I - "$base" <<'PY'
import os, sys
b = sys.argv[1]
def rd(m):
    p = os.path.join(b, m, "results.tsv")
    return {f[0]: f for f in (l.rstrip("\n").split("\t") for l in open(p, encoding="utf-8"))} if os.path.exists(p) else {}
def meta(m):
    p = os.path.join(b, m, "META")
    return open(p, encoding="utf-8").read().splitlines() if os.path.exists(p) else ["(no META)"]
pre, post = rd("pre"), rd("post")
want = {"new": ("PASS", "FAIL"), "kept": ("PASS", "PASS"), "drill": ("PASS", "PASS"), "post": ("PASS", "SKIP")}
rows, bad = [], []
for i in list(post) + [i for i in pre if i not in post]:
    f = post.get(i) or pre.get(i); cls, what = f[2], f[3]
    q, p = (post.get(i) or [i, "missing"])[1], (pre.get(i) or [i, "missing"])[1]
    ok = (q, p) == want.get(cls)
    rows.append((i, cls, q, p, ok, what))
    if not ok:
        bad.append(i)
with open(os.path.join(b, "revert.tsv"), "w", encoding="utf-8") as f:
    for i, cls, q, p, ok, what in rows:
        f.write(f"{i}\t{cls}\tpost={q}\tpre={p}\t{'as expected' if ok else 'NOT as expected'}\n")
cnt = {c: sum(1 for r in rows if r[1] == c) for c in want}
L = ["# B2a drill (run-e2e.sh both)", "", "post (this checkout):", ""] + [f"    {l}" for l in meta("post")] + \
    ["", "pre (base, the revert test):", ""] + [f"    {l}" for l in meta("pre")] + ["",
     f"{len(rows)} checks: new {cnt['new']} (post PASS, pre FAIL), kept {cnt['kept']} (PASS on both), "
     f"drill {cnt['drill']} (PASS on both), post-only {cnt['post']} (post PASS, pre SKIP).",
     f"Not as expected: {', '.join(bad) or 'none'}.", "",
     "| id | class | what | post | pre | as expected |", "|---|---|---|---|---|---|"]
L += [f"| {i} | {cls} | {what} | {q} | {p} | {'yes' if ok else 'NO'} |" for i, cls, q, p, ok, what in rows]
L += ["", "G1a / G1b scenario by scenario: post/g1/G1a/REPORT.md, post/g1/G1b/REPORT.md."]
open(os.path.join(b, "SUMMARY.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
print(f"revert: {len(rows)} checks; not as expected: {', '.join(bad) or 'none'}")
sys.exit(1 if bad else 0)
PY
  rv=$?; echo "artifacts: $base"; exit $(( rp | rq | rv ));;
post|pre) ;;
*) echo "usage: run-e2e.sh post|pre|both" >&2; exit 2;;
esac
[ "$(hostname -s | tr 'A-Z' 'a-z')" = imac ] || { echo "run-e2e.sh: run it on the iMac (the MBA is driven over ssh)" >&2; exit 2; }
sm(){ /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15 mba "$@"; }   # the drill's own ssh, only ever to the MBA
sm true 2>/dev/null || { echo "run-e2e.sh: cannot reach the MBA over ssh" >&2; exit 3; }
T=${E2E_OUT:-$HOME/.orca-state/e2e/migration-1020-nobox/$(date +%Y%m%d-%H%M%S)-$mode}
mkdir -p "$T"; : > "$T/results.tsv"; : > "$T/log"
if [ "$mode" = pre ]; then OPS=$T/tree; mkdir -p "$OPS"; git -C "$REPO" archive "$BASE" scripts automations/migration-1020 | tar -x -C "$OPS"
else OPS=$REPO; fi
S=$OPS/scripts; RMIG=$OPS/automations/migration-1020; PR=$RMIG/prompts
{ echo "mode=$mode"; echo "commit=$(git -C "$REPO" rev-parse HEAD)"; echo "base=$BASE"; echo "tree=$OPS"
  echo "uncommitted=$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ') (files in the checkout that differ from the commit)"
  echo "date=$(date '+%F %T %z')"
  echo "imac: $(hostname -s) bash=$(/bin/bash -c 'echo $BASH_VERSION') macOS=$(sw_vers -productVersion)"
  echo "mba: $(sm 'printf "%s bash=%s macOS=%s" "$(hostname -s)" "$(/bin/bash -c "echo \$BASH_VERSION")" "$(sw_vers -productVersion)"' 2>/dev/null)"
  echo "notify-run sha256: imac=$(shasum -a 256 "$HOME/.local/bin/notify-run" | cut -c1-16) mba=$(sm 'shasum -a 256 ~/.local/bin/notify-run' 2>/dev/null | cut -c1-16)"
  echo "box: not contacted (ssh-spy-imac.log, ssh-spy-mba.log)"; } > "$T/META"
n=0
ck(){ local id=$1 cls=$2 what=$3 r; shift 3; n=$((n+1)); echo "== $id: $*" >> "$T/log"
  if ( eval "$*" ) >>"$T/log" 2>&1; then r=PASS; else r=FAIL; fi   # subshell: a check that exits must not end the drill
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$r" "$cls" "$what" "$(echo "$*" | tr '\n\t' '  ')" >> "$T/results.tsv"; echo "$r $id $what"; }
skip(){ n=$((n+1)); printf '%s\tSKIP\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$T/results.tsv"; echo "SKIP $1 $3"; }
run(){ echo "+ $*" >> "$T/log"; "$@" >> "$T/log" 2>&1; }
ep(){ python3 -I -c 'import sys,datetime as d; print(int(d.datetime.fromisoformat(sys.argv[1]+"+08:00").timestamp()))' "$1"; }
HL="/bin/bash $S/heavy-lock.sh"; G="/bin/bash $S/night-review-gate.sh"
GPATH='export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH'   # the gate's own PATH line (X0 checks it is there)
hooks(){ python3 -I -c 'import json,os,sys; f,p,k=sys.argv[1],sys.argv[2],sys.argv[3:]
n=0
for l in (open(f, encoding="utf-8") if os.path.exists(f) else []):
    o=json.loads(l); s=json.dumps(o,ensure_ascii=False)
    n+=o["path"]=="/"+p and all(x in s for x in k)
print(n)' "$@"; }
stuck_imac(){ python3 -I -c 'import json,sys; f,d,r=sys.argv[1:4]
w=[o["body"] for o in map(json.loads, open(f, encoding="utf-8")) if o["path"]=="/ops-system" and isinstance(o["body"],dict)
   and o["body"].get("status")=="stuck" and d in o["body"].get("task","") and o["body"].get("reason")==r]
print(json.dumps(w, ensure_ascii=False))
assert len(w)==1 and w[0]["machine"]=="imac" and "box" not in w[0]["note"] and "iMac backup" in w[0]["note"]' "$@"; }
spycheck(){ python3 -I - "$@" <<'PY'
import sys
addrs = set(sys.argv[1].split()); n, bad = 0, []
for f in sys.argv[2:]:
    for l in open(f, encoding="utf-8"):
        w = l.split(); n += 1
        if len(w) < 3 or w[1] != "pass" or w[2].split("@")[-1] == "box" or (len(w) > 3 and (w[3] in addrs or w[3] == "box")):
            bad.append(f"{f}: {l.strip()}")
print(f"{n} ssh calls logged, {len(bad)} refused or to box"); print("\n".join(bad))
sys.exit(1 if bad or n == 0 else 0)
PY
}
nosignal(){ python3 -I - "$@" <<'PY'
import re, sys
w = "ki" + "ll"; pat = re.compile(r"(^|[^A-Za-z_])p?" + w + r"(all)?([^A-Za-z_]|$)")
bad = [f"{f}:{i}: {l.strip()}" for f in sys.argv[1:] for i, l in enumerate(open(f, encoding="utf-8"), 1) if pat.search(l)]
print("\n".join(bad) or "no command that ends a process in the drill files"); sys.exit(1 if bad else 0)
PY
}

# ---- set up: iMac (this machine) and the MBA copy, each with its ssh-spy and its own mock ----
RT=/tmp/b2a-e2e-$(date +%Y%m%d-%H%M%S)-$mode-$$
FH=$T/home; mkdir -p "$FH/.config/grokbot/webhooks" "$T/bin" "$T/nr" "$T/store" "$T/state/vllm-omni"
cp "$E/ssh-spy" "$T/bin/ssh"; chmod +x "$T/bin/ssh"
BA_I=$(/usr/bin/ssh -G box 2>/dev/null </dev/null | awk '$1 == "hostname" {print $2; exit}')   # box's address (ssh -G connects nowhere)
python3 -I "$E/mock_webhook.py" "$T/hooks.jsonl" "$T/port" 1800 "$T/mock-stop" & MOCK=$!
for i in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.2; done; PORT=$(cat "$T/port")
for b in ops-system coding-assistant; do printf 'URL=http://127.0.0.1:%s/%s\nKEY=e2e-fake\n' "$PORT" "$b" > "$FH/.config/grokbot/webhooks/$b.env"; done
printf '#!/bin/bash\necho "$@" >> %s/sync-calls\n' "$T" > "$T/fake-sync.sh"
NR=$HOME/.local/bin/notify-run
IENV="HOME=$FH NR_STATE=$T/state HEAVY_LOCK_DIR=$T/lock NR_CAFFEINATE_T=5 NR_SYNC=$T/fake-sync.sh NR_DIR=$T/nr NR_BOX_HOST=local NR_BOX_DIR=$T/store NR_MBA_HOST=mba NR_MBA_STATE=$RT/state-mba PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin SSH_SPY_LOG=$T/ssh-spy-imac.log SSH_SPY_BOX_ADDR=$BA_I GH_NO_UPDATE_NOTIFIER=1"
gi(){ echo "+ imac: $*" >> "$T/log"; env $IENV "$@" 2>>"$T/log" | tee -a "$T/log"; return ${PIPESTATUS[0]}; }
istat(){ cat "$T/state/vllm-omni/$1.${2:-status}" 2>/dev/null; }
PK=$T/mba-pkg; mkdir -p "$PK/ops/scripts" "$PK/bin" "$PK/home/.config/grokbot/webhooks" "$PK/nr" "$PK/store-mba" "$PK/state-mba"
for f in night-review-gate.sh heavy-lock.sh review-date.sh sync-manifests-from-box.sh; do cp "$S/$f" "$PK/ops/scripts/"; done
cp "$E/ssh-spy" "$PK/bin/ssh"; chmod +x "$PK/bin/ssh"; cp "$E/mock_webhook.py" "$PK/"
echo "Now drawing from 'AC Power'" > "$PK/pm-ac"; echo "Now drawing from 'Battery Power'" > "$PK/pm-bat"
echo '    "AppleClamshellState" = No' > "$PK/io-open"; echo '    "AppleClamshellState" = Yes' > "$PK/io-shut"
echo ' sleep 1' > "$PK/pm-nosd"; printf ' SleepDisabled\t\t1\n sleep 0\n' > "$PK/pm-sd"
printf '  Resolution: 2560 x 1664\n  Connection Type: Internal\n' > "$PK/displays"
printf '#!/bin/bash\necho "$@" >> %s/sync-calls\n' "$RT" > "$PK/fake-sync.sh"
cat > "$PK/synced-ok.py" <<'PY'
import json, glob, os, sys
d, n = sys.argv[1], 0
assert open(os.path.join(d, "SYNC-STATUS")).read().startswith("ok "), "SYNC-STATUS"
for f in glob.glob(d + "/sessions-*.jsonl"):
    if f.endswith(".excluded.jsonl"):
        continue
    for l in open(f, encoding="utf-8"):
        o = json.loads(l); tp = o.get("transcript_path")
        if tp:
            n += 1
            assert tp.startswith(d + "/") and os.access(tp, os.R_OK) and o["transcript_box_path"] != tp, tp
assert n == 3, n
print(n, "transcripts readable under", d)
PY
tar -C "$PK" -czf - . | sm "mkdir -p $RT && tar -xzf - -C $RT" 2>>"$T/log"
BA_M=$(sm "/usr/bin/ssh -G box 2>/dev/null </dev/null | awk '\$1 == \"hostname\" {print \$2; exit}'")
sm "cd $RT && (nohup python3 -I $RT/mock_webhook.py $RT/hooks.jsonl $RT/port 1800 $RT/mock-stop </dev/null >/dev/null 2>&1 & echo \$! > $RT/mock.pid)
  for i in \$(seq 1 50); do [ -s $RT/port ] && break; sleep 0.2; done; p=\$(cat $RT/port)
  for b in ops-system coding-assistant; do printf 'URL=http://127.0.0.1:%s/%s\nKEY=e2e-fake\n' \$p \$b > $RT/home/.config/grokbot/webhooks/\$b.env; done" 2>>"$T/log"
MNR=$(sm 'echo ~/.local/bin/notify-run')
MENV="HOME=$RT/home NR_STATE=$RT/state-mba HEAVY_LOCK_DIR=$RT/lock-mba NR_CAFFEINATE_T=5 NR_SYNC=$RT/fake-sync.sh NR_DIR=$RT/nr NR_BOX_HOST=local NR_BOX_DIR=$RT/store-mba NR_PMSET_BATT=$RT/pm-ac NR_PMSET_G=$RT/pm-sd NR_IOREG=$RT/io-open NR_DISPLAYS=$RT/displays PATH=$RT/bin:/usr/bin:/bin:/usr/sbin:/sbin SSH_SPY_LOG=$RT/ssh-spy-mba.log SSH_SPY_BOX_ADDR=$BA_M GH_NO_UPDATE_NOTIFIER=1"
gm(){ echo "+ mba: $1" >> "$T/log"; sm "cd $RT && env $MENV $1" 2>>"$T/log" | tee -a "$T/log"; return ${PIPESTATUS[0]}; }
GM="/bin/bash ops/scripts/night-review-gate.sh"; HM="/bin/bash ops/scripts/heavy-lock.sh"
mstat(){ sm "cat $RT/state-mba/vllm-omni/$1.${2:-status}" 2>/dev/null; }
mhooks(){ sm "cat $RT/hooks.jsonl 2>/dev/null" > "$T/mba-hooks.jsonl"; }
echo "rt=mba:$RT box-address imac=$BA_I mba=$BA_M" >> "$T/META"

# ---- X0: the ssh the gate and the sync find first is the spy, on both Macs ----
iw=$(env $IENV /bin/bash -c "$GPATH; command -v ssh"); iw2=$(env $IENV /bin/bash -c 'command -v ssh')
mw=$(gm "/bin/bash -c '$GPATH; command -v ssh'"); mw2=$(gm "/bin/bash -c 'command -v ssh'")
ck X0 drill "两台机器上，闸门（按它自己的 PATH 行）和同步脚本先找到的 ssh 都是演练的记录用 ssh" '[ "$iw" = "$T/bin/ssh" ] && [ "$iw2" = "$T/bin/ssh" ] && [ "$mw" = "$RT/bin/ssh" ] && [ "$mw2" = "$RT/bin/ssh" ] && grep -qF "$GPATH" $S/night-review-gate.sh'

# ---- L: heavy-lock (iMac, /bin/bash 3.2) ----
export HEAVY_LOCK_DIR=$T/l1/lock
run $HL acquire night-review-vllm-omni; run $HL acquire vllm-upstream; rc=$?
ck L1 kept "锁被占时第二个 acquire 退出 1，status 显示持有者" '[ $rc -eq 1 ] && $HL status | grep -q name=night-review-vllm-omni'
export HEAVY_LOCK_DIR=$T/l2/lock; mkdir -p "$T/l2"
pids=""; for i in 1 2 3 4 5 6 7 8; do ( $HL acquire job$i >/dev/null 2>&1; echo $? > "$T/l2/rc$i" ) & pids="$pids $!"; done; wait $pids
ck L2 kept "8 个并发 acquire 恰好 1 个拿到" '[ $(cat $T/l2/rc* | grep -c "^0$") -eq 1 ]'
export HEAVY_LOCK_DIR=$T/l3/lock; now=$(date +%s)
run $HL acquire dead-job; sed -i '' "s/since=[0-9]*/since=$((now-41*60))/" "$HEAVY_LOCK_DIR/owner" 2>/dev/null
run $HL acquire fresh-job; rc=$?
ck L3a kept "超过 40 分钟的锁被收回" '[ $rc -eq 0 ] && $HL status | grep -q name=fresh-job'
sed -i '' "s/since=[0-9]*/since=$((now-39*60))/" "$HEAVY_LOCK_DIR/owner" 2>/dev/null; run $HL acquire other-job; rc=$?
ck L3b kept "39 分钟的锁不收回" '[ $rc -eq 1 ] && $HL status | grep -q name=fresh-job'
run $HL release other-job; rc=$?
ck L4a kept "名字不对的 release 退出 1，锁还在" '[ $rc -eq 1 ] && $HL status | grep -q name=fresh-job'
run $HL refresh fresh-job
ck L5 kept "refresh 后重新计时" '[ $(( $(date +%s) - $($HL status | sed -n "s/.*since=\([0-9]*\).*/\1/p") )) -lt 60 ]'
run $HL release fresh-job
ck L4b kept "本人 release 后锁空" '[ -f $HEAVY_LOCK_DIR.log ] && ! $HL status'
unset HEAVY_LOCK_DIR

# ---- D: dates under /bin/bash 3.2 (macOS date has no -d) ----
rd(){ REVIEW_NOW=$(ep "$1") /bin/bash "$S/review-date.sh" ago "$2" 2>>"$T/log"; }
ck D1a kept "00:30 往回 13 小时 = 昨天" '[ "$(rd 2026-10-21T00:30:00 13)" = 2026-10-20 ]'
ck D1b kept "23:40 往回 6 小时 = 当天" '[ "$(rd 2026-10-20T23:40:00 6)" = 2026-10-20 ]'
ck D1c kept "跨月、跨年、闰年" '[ "$(rd 2026-11-01T01:20:00 13)" = 2026-10-31 ] && [ "$(rd 2027-01-01T00:55:00 13)" = 2026-12-31 ] && [ "$(rd 2028-03-01T00:30:00 13)" = 2028-02-29 ]'
ck D1d kept "next：闰年、跨年" '[ "$(/bin/bash $S/review-date.sh next 2028-02-28)" = 2028-02-29 ] && [ "$(/bin/bash $S/review-date.sh next 2026-12-31)" = 2027-01-01 ]'
ck D2 kept "MBA / iMac 提示词不含 date -d，日期用 review-date.sh" '! grep -l "date -d" $PR/*/night-review-*.md && [ $(grep -l "review-date.sh ago" $PR/*/night-review-*.md | wc -l) -eq 8 ]'
dcmd(){ python3 -I -c 'import re,sys; print(re.search(r"D=\$\(([^)]*)\)", open(sys.argv[1]).read()).group(1))' "$1"; }
d3(){ local f c d ok=0; for f in $PR/$2/night-review-*.md; do c=$(dcmd "$f" | sed "s|~/orca/workspaces/ops|$1|g")
  if [ "$2" = mba ]; then d=$(sm "/bin/bash -c $(printf %q "$c")" 2>>"$T/log"); else d=$(/bin/bash -c "$c" 2>>"$T/log"); fi
  echo "D3 $2 $(basename "$f") [$c] -> '$d'" >> "$T/log"; echo "$d" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || ok=1; done; return $ok; }
ck D3a kept "4 个夜审提示词里算 D 的命令在 MBA /bin/bash 3.2 上实跑出日期" 'd3 $RT/ops mba'
ck D3b kept "同样的命令在 iMac（没有 gdate）实跑出日期" 'd3 $OPS imac'

# ---- M: session-list sync, never from box: an unreachable host, the MBA, and a fixture on the iMac ----
FX=$T/fix; FD=$FX/vllm-omni/2099-01-20; mkdir -p "$FD/mba" "$FD/imac" "$T/fix-home/.claude/projects/e2e"
echo '{"m":1}' > "$FD/mba/s1.jsonl"; echo '{"m":3}' > "$FD/imac/s3.jsonl"; echo '{"m":2}' > "$T/fix-home/.claude/projects/e2e/s2.jsonl"; echo note > "$FD/notes.txt"
printf '{"session_id":"s1","transcript_path":"%s"}\n{"session_id":"s2","transcript_path":"%s"}\n' "$FD/mba/s1.jsonl" "$T/fix-home/.claude/projects/e2e/s2.jsonl" > "$FD/sessions-mba.jsonl"
printf '{"session_id":"s3","transcript_path":"%s"}\n' "$FD/imac/s3.jsonl" > "$FD/sessions-imac.jsonl"
printf '{"session_id":"s9","transcript_path":"%s"}\n' "$FD/mba/gone.jsonl" > "$FD/sessions-mba.excluded.jsonl"
SYN="/bin/bash $S/sync-manifests-from-box.sh"
gi SYNC_DST_ROOT=$T/m2/dst SYNC_SRC_HOST=nosuchhost.invalid SYNC_PEERS= $SYN vllm-omni 2026-10-19 imac >/dev/null; rc=$?
ck M2a kept "源主机连不上：退出 3，SYNC-STATUS=failed" '[ $rc -eq 3 ] && grep -q "^failed reach" $T/m2/dst/vllm-omni/2026-10-19/SYNC-STATUS'
gi SYNC_DST_ROOT=$T/m2/dst SYNC_SRC_HOST=mba SYNC_PEERS= $SYN vllm-omni 2001-01-01 imac >/dev/null; rc=$?
ck M2b kept "源主机（MBA）上没有这天：退出 3，SYNC-STATUS=failed" '[ $rc -eq 3 ] && grep -q "^failed" $T/m2/dst/vllm-omni/2001-01-01/SYNC-STATUS'
gi SYNC_SRC_HOST=local SYNC_SRC_ROOT=$FX SYNC_DST_ROOT=$T/m5a SYNC_STAGE_ROOT=$T/stage SYNC_PEERS= $SYN vllm-omni 2099-01-20 imac >/dev/null; rc=$?
ck M5a new "iMac 上 SYNC_SRC_HOST=local：同步成功，SYNC-STATUS=ok，3 个 transcript 都是本机可读副本" '[ $rc -eq 0 ] && python3 -I $PK/synced-ok.py $T/m5a/vllm-omni/2099-01-20'
s0=$(wc -l < "$T/ssh-spy-imac.log" 2>/dev/null || echo 0)
gi SYNC_SRC_HOST=imac SYNC_SRC_ROOT=$FX SYNC_DST_ROOT=$T/m5b SYNC_STAGE_ROOT=$T/stage SYNC_PEERS= $SYN vllm-omni 2099-01-20 imac >/dev/null; rc=$?
s1=$(wc -l < "$T/ssh-spy-imac.log" 2>/dev/null || echo 0)
ck M5b new "iMac 上 SYNC_SRC_HOST=imac（本机名）：不 ssh 自己，同步成功" '[ $rc -eq 0 ] && [ $s1 -eq $s0 ] && python3 -I $PK/synced-ok.py $T/m5b/vllm-omni/2099-01-20'
gm "SYNC_SRC_HOST=imac SYNC_SRC_ROOT=$FX SYNC_DST_ROOT=$RT/m6 SYNC_STAGE_ROOT=$RT/stage SYNC_PEERS= /bin/bash ops/scripts/sync-manifests-from-box.sh vllm-omni 2099-01-20 mba" >/dev/null; rc=$?
ck M6 kept "MBA 从 iMac 上的清单同步（ssh imac，只读）：成功，transcript 都是 MBA 本机可读副本" '[ $rc -eq 0 ] && sm "python3 -I $RT/synced-ok.py $RT/m6/vllm-omni/2099-01-20"'

# ---- W: who runs the night (MBA primary over ssh, iMac watch / backup here) ----
# vllm-omni: MBA 01:20, iMac watch 01:50, backup from 01:50 to 05:20, box-watch time 03:50 (clock of 2026-10-21 SGT)
tM=$(ep 2026-10-21T01:21:00); tW=$(ep 2026-10-21T01:50:00); tB=$(ep 2026-10-21T02:00:00); tX=$(ep 2026-10-21T03:50:00)
# W1 MBA offline -> iMac watcher marks takeover, backup takes the iMac lock, finish (through notify-run) wakes ops-system
D=2099-01-01
gi NR_D=$D NR_NOW=$tW NR_MBA_HOST=nosuchhost.invalid $G watch vllm-omni >/dev/null; rc=$?
ck W1a kept "MBA 离线：看守退出 1、写接替标记 reason=offline" '[ $rc -eq 1 ] && istat $D takeover | grep -q reason=offline'
gi NR_D=$D NR_NOW=$tB $G backup vllm-omni >/dev/null; rc=$?
ck W1b kept "iMac 备用拿 iMac 锁放行" '[ $rc -eq 0 ] && istat $D | tail -1 | grep -q "state=started machine=imac reason=offline" && HEAVY_LOCK_DIR=$T/lock $HL status | grep -q name=night-review-vllm-omni'
printf '# vllm-omni %s\n状态：完成\n' $D > "$T/nr/$D-vllm-omni.md"
R=$(gi $G reason vllm-omni $D)
gi NR_D=$D NR_NOW=$tB $NR --bot ops-system --no-tty --task "vllm-omni夜审 $D machine=imac reason=$R" -- $G finish vllm-omni $D imac "$R" >/dev/null; rc=$?
ck W1c kept "收尾经 notify-run：拷进存放目录、记 done、放锁，ops-system 收到 1 条 done，task 含 machine=imac reason=offline" '[ $rc -eq 0 ] && istat $D | grep -q "state=done machine=imac reason=offline" && ! HEAVY_LOCK_DIR=$T/lock $HL status && [ $(hooks $T/hooks.jsonl ops-system "machine=imac reason=offline" "\"status\": \"done\"" $D) -eq 1 ] && grep -q 状态 $T/store/$D-vllm-omni.md'

# W2 MBA asleep: on battery; lid closed and would sleep; precheck never ran
D=2099-01-02; gm "NR_PMSET_BATT=$RT/pm-bat NR_D=$D NR_NOW=$tM $GM primary vllm-omni" >/dev/null; rc=$?
ck W2a kept "用电池：MBA 主预检退出 1，记 missed reason=asleep" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q "state=missed machine=mba reason=asleep detail=on_battery"'
gi NR_D=$D NR_NOW=$tW $G watch vllm-omni >/dev/null
ck W2b kept "看守（iMac 经 ssh 读 MBA）判 asleep" 'istat $D takeover | grep -q reason=asleep'
D=2099-01-03; gm "NR_IOREG=$RT/io-shut NR_PMSET_G=$RT/pm-nosd NR_D=$D NR_NOW=$tM $GM primary vllm-omni" >/dev/null; rc=$?
ck W2c kept "合盖、没禁睡、没外接屏：主预检退出 1，reason=asleep detail=lid_closed" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q "reason=asleep detail=lid_closed"'
D=2099-01-11; gi NR_D=$D NR_NOW=$tW $G watch vllm-omni >/dev/null
ck W2d kept "MBA 能连上但当晚预检没跑：看守判 asleep" 'istat $D takeover | grep -q reason=asleep'
# lid closed, on AC, SleepDisabled 1 = the MBA today -> runs; K1 caffeinate
D=2099-01-04; gm "NR_CAFFEINATE_T=30 NR_IOREG=$RT/io-shut NR_PMSET_G=$RT/pm-sd NR_D=$D NR_NOW=$tM $GM primary vllm-omni" >/dev/null; rc=$?; ct=$(date +%s)
cpid=$(mstat $D | tail -1 | sed -n 's/.*caffeinate=\([0-9]*\).*/\1/p')
ck W2e kept "合盖但接电源、SleepDisabled=1：主预检放行，记 started" '[ $rc -eq 0 ] && mstat $D | tail -1 | grep -q "state=started machine=mba reason=ok"'
ck K1a kept "主预检起了 caffeinate（MBA 上按 pid 看进程名）" '[ -n "$cpid" ] && sm "ps -o pid,ppid,rss,etime,comm -p $cpid" | grep caffeinate'
ck S1 kept "主预检先同步清单再拿锁（同步调用记录有 vllm-omni $D mba）" 'sm "cat $RT/sync-calls" | grep -q "vllm-omni $D mba"'
gm "NR_D=$D NR_NOW=$((tM+600)) $GM primary vllm-omni" >/dev/null; rc=$?
ck W8a kept "补跑触发时当晚已 started：退出 1，不记 lock_busy" '[ $rc -eq 1 ] && [ "$(mstat $D | tail -1 | grep -c lock_busy)" = 0 ]'
gi NR_D=$D NR_NOW=$tW $G watch vllm-omni >/dev/null
ck W8b kept "MBA 在跑（started < 60 分钟）：看守不写接替标记" '! istat $D takeover >/dev/null && istat $D | tail -1 | grep -q state=seen_running'
gm "$HM release night-review-vllm-omni" >/dev/null
D=2099-01-12; gm "NR_D=$D NR_NOW=$((tM+40*60)) $GM primary vllm-omni" >/dev/null; rc=$?
ck W8c kept "补跑在 MBA 时间 +25 分钟以后不起（交给 iMac）" '[ $rc -eq 1 ] && ! mstat $D | grep -q started'
gi NR_D=$D NR_NOW=$((tM+10*60)) $G backup vllm-omni >/dev/null; rc=$?
ck W8d kept "MBA 时间 +30 分钟以前 iMac 备用不接替" '[ $rc -eq 1 ] && ! istat $D takeover >/dev/null'

# W3 MBA lock busy -> lock_busy, watcher hands to the iMac
D=2099-01-05; gm "$HM acquire vllm-upstream" >/dev/null
gm "NR_D=$D NR_NOW=$tM $GM primary vllm-omni" >/dev/null; rc=$?
ck W3a kept "MBA 锁被占：主预检记 lock_busy" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q "reason=lock_busy detail=vllm-upstream"'
gi NR_D=$D NR_NOW=$tW $G watch vllm-omni >/dev/null
ck W3b kept "看守判 lock_busy 并交给 iMac" 'istat $D takeover | grep -q reason=lock_busy'
gm "$HM release vllm-upstream" >/dev/null

# W4 iMac lock busy > 60 min after the takeover -> one stuck to ops-system, only once; N5 what it says
D=2099-01-06; echo "reason=offline since=$((tB-3700))" > "$T/state/vllm-omni/$D.takeover"
gi $HL acquire linear-sync >/dev/null
gi NR_D=$D NR_NOW=$tB $G backup vllm-omni >/dev/null; rc=$?
gi NR_D=$D NR_NOW=$((tB+600)) $G backup vllm-omni >/dev/null
ck W4 kept "iMac 锁被占超过 60 分钟：ops-system 收到 1 条 stuck reason=lock_busy，只 1 条" '[ $rc -eq 1 ] && [ $(hooks $T/hooks.jsonl ops-system "\"status\": \"stuck\"" lock_busy $D) -eq 1 ]'
ck N5 new "这条 stuck 写 machine=imac，提示按 iMac 备用接替，不提 box" 'stuck_imac $T/hooks.jsonl $D lock_busy'
gi $HL release linear-sync >/dev/null

# W5 / W6 done in the store -> nobody runs again
D=2099-01-07; sm "printf '状态：完成\n' > $RT/store-mba/$D-vllm-omni.md"; printf '状态：完成\n' > "$T/store/$D-vllm-omni.md"
echo "reason=offline since=$tB" > "$T/state/vllm-omni/$D.takeover"
gm "NR_D=$D NR_NOW=$tM $GM primary vllm-omni" >/dev/null; rc=$?
ck W5 kept "存放目录已有完成摘要：MBA 主预检退出 1" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q already_done'
gi NR_D=$D NR_NOW=$tB $G backup vllm-omni >/dev/null; rc=$?
ck W6 kept "存放目录已有完成摘要：iMac 备用预检退出 1，不拿锁" '[ $rc -eq 1 ] && ! HEAVY_LOCK_DIR=$T/lock $HL status'

# W7 box-watch: kept, no task uses it; run on the MBA here (it reads the iMac over ssh): iMac running -> quiet; nobody -> 1 stuck
D=2099-01-08; echo "state=started machine=imac reason=offline ts=$((tX-1800))" > "$T/state/vllm-omni/$D.status"
gm "NR_D=$D NR_NOW=$tX NR_IMAC_HOST=imac NR_IMAC_STATE=$T/state $GM box-watch vllm-omni" >/dev/null
D2=2099-01-09; gm "NR_D=$D2 NR_NOW=$tX NR_IMAC_HOST=imac NR_IMAC_STATE=$T/state $GM box-watch vllm-omni" >/dev/null; rc=$?
gm "NR_D=$D2 NR_NOW=$((tX+600)) NR_IMAC_HOST=imac NR_IMAC_STATE=$T/state $GM box-watch vllm-omni" >/dev/null
mhooks
ck W7a kept "box-watch（保留，没有任务用；这里在 MBA 上跑）：iMac 接替在跑时不发" '[ $(hooks $T/mba-hooks.jsonl ops-system $D) -eq 0 ] && mstat $D | grep -q seen_imac_running'
ck W7b kept "box-watch：没人完成时 ops-system 收到 1 条 stuck reason=imac_missed，只 1 条" '[ $rc -eq 1 ] && [ $(hooks $T/mba-hooks.jsonl ops-system "\"status\": \"stuck\"" imac_missed $D2) -eq 1 ]'
ck N7 new "box-watch 的 stuck 写 machine=imac，提示按 iMac 备用接替，不提 box" 'stuck_imac $T/mba-hooks.jsonl $D2 imac_missed'

# F finish failure paths (MBA)
D=2099-01-10; gm "$HM acquire night-review-vllm-omni" >/dev/null; sm "printf '状态：进行中\n' > $RT/nr/$D-vllm-omni.md"
gm "NR_D=$D $GM finish vllm-omni $D mba ok" >/dev/null; rc=$?
ck F1 kept "摘要没有「状态：完成」：finish 退出 3，放锁" '[ $rc -eq 3 ] && ! gm "$HM status"'
gm "$HM acquire night-review-vllm-omni" >/dev/null; sm "printf '状态：完成\n' > $RT/nr/$D-vllm-omni.md"
gm "NR_D=$D NR_BOX_HOST=nosuchhost.invalid $GM finish vllm-omni $D mba ok" >/dev/null; rc=$?
ck F2 kept "拷不到存放主机：finish 退出 4，记 rsync_failed，放锁" '[ $rc -eq 4 ] && mstat $D | tail -1 | grep -q detail=rsync_failed && ! gm "$HM status"'

# K1b keepawake task (MBA)
o=$(gm "NR_CAFFEINATE_T=3 $GM keepawake"); rc=$?; kt=$(date +%s); kp=$(echo "$o" | sed -n 's/.*pid \([0-9]*\).*/\1/p')
ck K1b kept "防睡任务起 caffeinate 后退出 1（不起模型）" '[ $rc -eq 1 ] && [ -n "$kp" ] && sm "ps -o pid,ppid,rss,etime,comm -p $kp" | grep caffeinate'

# ---- N4 / N9 / W0: the new store variables (NR_BOX_HOST points nowhere, so the base version fails without box) ----
D=2099-01-13; printf '# vllm-omni %s\n状态：完成\n' $D > "$T/nr/$D-vllm-omni.md"; gi $HL acquire night-review-vllm-omni >/dev/null
N4E="NR_BOX_HOST=nosuchhost.invalid NR_STORE_HOST=local NR_STORE_DIR=$T/store-n4"
gi $N4E NR_D=$D $G finish vllm-omni $D imac offline >/dev/null; rc=$?
echo "reason=offline since=$tB" > "$T/state/vllm-omni/$D.takeover"
gi $N4E NR_D=$D NR_NOW=$tB $G backup vllm-omni >/dev/null; rc2=$?
ck N4 new "NR_STORE_HOST=local、NR_STORE_DIR 生效（NR_BOX_HOST 指向连不上的主机）：收尾拷到 NR_STORE_DIR 退出 0；同晚备用按新位置看到完成，退出 1、不拿锁" '[ $rc -eq 0 ] && grep -q 状态 $T/store-n4/$D-vllm-omni.md && [ $rc2 -eq 1 ] && ! HEAVY_LOCK_DIR=$T/lock $HL status'
gi $HL release night-review-vllm-omni >/dev/null   # on pre the backup took it; the next checks need it free
D=2099-01-14; printf '# vllm-omni %s\n状态：完成\n' $D > "$T/nr/$D-vllm-omni.md"; gi $HL acquire night-review-vllm-omni >/dev/null
s0=$(wc -l < "$T/ssh-spy-imac.log" 2>/dev/null || echo 0)
gi NR_BOX_HOST=nosuchhost.invalid NR_STORE_HOST=imac NR_STORE_DIR=$T/store-n9 NR_D=$D $G finish vllm-omni $D imac offline >/dev/null; rc=$?
s1=$(wc -l < "$T/ssh-spy-imac.log" 2>/dev/null || echo 0)
ck N9 new "iMac 上 NR_STORE_HOST=imac（本机名）：收尾走本地拷贝，这一步没有 ssh，退出 0、放锁" '[ $rc -eq 0 ] && grep -q 状态 $T/store-n9/$D-vllm-omni.md && [ $s1 -eq $s0 ] && ! HEAVY_LOCK_DIR=$T/lock $HL status'
gi $HL release night-review-vllm-omni >/dev/null
D=2099-01-15; W0E="NR_BOX_HOST=nosuchhost.invalid NR_STORE_HOST=imac NR_STORE_DIR=$T/store-w0"
gm "$W0E NR_D=$D NR_NOW=$tM $GM primary vllm-omni" >/dev/null; rc0=$?
sm "printf '# vllm-omni %s\n状态：完成\n' $D > $RT/nr/$D-vllm-omni.md && echo '{}' > $RT/nr/$D-vllm-omni-ledger.jsonl"
gm "$W0E NR_D=$D NR_NOW=$tM $MNR --bot ops-system --no-tty --task 'vllm-omni夜审 $D machine=mba reason=ok' -- $GM finish vllm-omni $D mba ok" >/dev/null; rc1=$?
gi $W0E NR_D=$D NR_NOW=$tW $G watch vllm-omni >/dev/null
gi $W0E NR_D=$D NR_NOW=$tB $G backup vllm-omni >/dev/null; rc2=$?
mhooks
ck W0 new "存放位置设成 iMac（README「切换到 iMac 存放」）：MBA 主跑、收尾经 ssh 拷到 iMac，iMac 看守 seen_done，备用退出 1、不拿锁，ops-system 收到 MBA 的 done" '[ $rc0 -eq 0 ] && [ $rc1 -eq 0 ] && grep -q 状态 $T/store-w0/$D-vllm-omni.md && [ -f $T/store-w0/$D-vllm-omni-ledger.jsonl ] && mstat $D | tail -1 | grep -q "state=done machine=mba reason=ok" && istat $D | tail -1 | grep -q state=seen_done && [ $rc2 -eq 1 ] && [ ! -f $T/state/vllm-omni/$D.takeover ] && ! HEAVY_LOCK_DIR=$T/lock $HL status && [ $(hooks $T/mba-hooks.jsonl ops-system "machine=mba reason=ok" "\"status\": \"done\"" $D) -eq 1 ]'
gi $HL release night-review-vllm-omni >/dev/null; gm "$HM release night-review-vllm-omni" >/dev/null

# ---- N8: nothing store-related set; the store host (box) is played by fake-ssh.py, which connects nowhere ----
N8=$T/n8; mkdir -p "$N8/bin" "$N8/home" "$N8/nr"; cp "$E/fake-ssh.py" "$N8/bin/ssh"; chmod +x "$N8/bin/ssh"
D=2099-01-30; printf '# vllm-omni %s\n状态：完成\n' $D > "$N8/nr/$D-vllm-omni.md"
echo "+ n8: finish with defaults" >> "$T/log"
env -i HOME=$N8/home PATH=$N8/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 FAKE_SSH_LOG=$N8/ssh.jsonl FAKE_SSH_ROOT=$N8/fake \
  NR_STATE=$N8/state HEAVY_LOCK_DIR=$N8/lock NR_DIR=$N8/nr /bin/bash $S/night-review-gate.sh finish vllm-omni $D mba ok >>"$T/log" 2>&1; rc=$?
ck N8 new "什么都不设时，发给存放主机 box（这里是不联网的 fake-ssh）的 mkdir / tar 和 grep 里是字面 ~/xinyue-deploy/nightly-review/" '[ $rc -eq 0 ] && python3 -I -c "
import json,sys
c=[json.loads(l) for l in open(sys.argv[1])]; print(c)
assert {x[\"kind\"] for x in c}=={\"tar\",\"grep\"} and all(x[\"host\"]==\"box\" and x[\"path\"].startswith(\"~/xinyue-deploy/nightly-review\") for x in c)" $N8/ssh.jsonl'

# ---- R / N1–N3: defs.json and register.sh never touch orca or box ----
mkdir -p "$T/fakebin"; printf '#!/bin/bash\necho "$@" >> %s/orca-calls\n' "$T" > "$T/fakebin/orca"; chmod +x "$T/fakebin/orca"
for m in mba imac box; do PATH=$T/fakebin:$PATH /bin/bash "$RMIG/register.sh" $m > "$T/register-$m.out" 2> "$T/register-$m.err"; echo $? > "$T/register-$m.rc"; done
python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); print("key\tmachine\tname\trrule\tgrace\tprecheck\treplaces")
for c in d["create"]: print("\t".join(str(c.get(k,"")) for k in ("key","machine","name","rrule","grace","precheck","replaces")))
for e in d["edit"]: print("\t".join(["edit "+e["id"],e["machine"],e.get("why",""),json.dumps(e["set"],ensure_ascii=False),"","",""]))' "$RMIG/defs.json" > "$T/defs-table.tsv" 2>>"$T/log"
rgbox(){ local o rc; o=$(cd "$OPS" && rg -n 'machine": *"box"' automations/migration-1020/defs.json); rc=$?
  { echo "\$ rg -n 'machine\": *\"box\"' automations/migration-1020/defs.json    # in $OPS"; [ -n "$o" ] && echo "$o"; echo "rc=$rc"; } > "$T/rg-box.txt"
  [ -z "$o" ] && [ $rc -eq 1 ] && ! grep -q box-watch "$RMIG/defs.json" && ! grep -q /workspace/repos/ops "$RMIG/defs.json" \
    && python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["edit"]==[] else 1)' "$RMIG/defs.json"; }
names(){ python3 -I - "$RMIG/defs.json" "$T/register-mba.out" "$T/register-imac.out" > "$T/register-names.txt" <<'PY'
import json, shlex, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
want = {m: sorted(c["name"] for c in d["create"] if c["machine"] == m) for m in ("mba", "imac")}
every = sorted(c["name"] for c in d["create"])
got = {}
for m, f in (("mba", sys.argv[2]), ("imac", sys.argv[3])):
    got[m] = sorted(w[w.index("--name") + 1] for w in (shlex.split(l) for l in open(f, encoding="utf-8") if l.startswith("orca automations create")))
    print(f"{m}: register.sh printed {len(got[m])} create(s), defs.json has {len(want[m])} for {m}, same names: {got[m] == want[m]}")
    for x in got[m]:
        print(f"  {x}")
both = sorted(got["mba"] + got["imac"])
print(f"mba + imac: {len(both)}, every create in defs.json: {len(every)}, same: {both == every}")
left = sorted(set(every) - set(both))
if left:
    print("in defs.json but printed for neither Mac: " + ", ".join(left))
sys.exit(0 if got["mba"] == want["mba"] and got["imac"] == want["imac"] and both == every else 1)
PY
}
ck R1a kept "register 默认 dry-run：mba / imac / box 各跑一次，orca 调用 0 次" '[ ! -e $T/orca-calls ]'
ck R1b kept "MBA 9 条、iMac 10 条 create，每条都带 --missed-run-grace-minutes 120 和 --disabled" 'for m in mba:9 imac:10; do f=$T/register-${m%%:*}.out; c=$(grep -c "^orca automations create" $f); [ $c -eq ${m#*:} ] && [ $(grep "^orca automations create" $f | grep -- "--missed-run-grace-minutes 120" | grep -c -- "--disabled") -eq $c ] || exit 1; done'
ck N1 new "defs.json 里没有 box：rg 没有输出，没有 box-watch、/workspace/repos/ops，edit 为空" 'rgbox'
ck N2 new "register.sh box 退出 2：stderr 一行说明，stdout 为空，不调用 orca" '[ "$(cat $T/register-box.rc)" = 2 ] && [ ! -s $T/register-box.out ] && [ $(wc -l < $T/register-box.err) -eq 1 ] && [ ! -e $T/orca-calls ]'
ck N3 new "register.sh mba / imac 打印的任务名和 defs.json 里这台的一致，合起来是 defs.json 的全部 create" 'names; r=$?; cat $T/register-names.txt; [ $r -eq 0 ]'

# ---- P: prompts ----
ck P1a kept "MBA / iMac 提示词不含 /workspace/repos、/var/lib/everos-ingest、load>8、coding-assistant" '! grep -El "/workspace/repos|/var/lib/everos-ingest|load *> *8|coding-assistant" $PR/*/*.md'
ck P1b kept "8 个夜审提示词都有 caffeinate、heavy-lock refresh、SYNC-STATUS、finish、状态：完成、首行运行环境" 'for f in $PR/*/night-review-*.md; do grep -q "caffeinate -dimsu -w" $f && grep -q "heavy-lock.sh refresh" $f && grep -q SYNC-STATUS $f && grep -q "night-review-gate.sh finish" $f && grep -q "状态：完成" $f && head -1 $f | grep -q "运行环境：" || exit 1; done'
ck P1c kept "make-prompts.py --check：提交的提示词和生成结果一致" 'python3 -I $RMIG/make-prompts.py --check > $T/make-prompts-check.txt 2>&1; rc=$?; echo "rc=$rc" >> $T/make-prompts-check.txt; cat $T/make-prompts-check.txt; [ $rc -eq 0 ]'
ck P1d kept "iMac 接替提示词写明读回去重；MBA 版没有" '[ $(grep -l "接替运行" $PR/imac/night-review-*.md | wc -l) -eq 4 ] && ! grep -l "接替运行" $PR/mba/*.md'
ck N6 new "提示词和 noop 里没有 box 兜底（拷回 box、box 上 01:00 的兜底、Linear 连不上改用 box、box-watch）；8 个夜审收尾都写存放位置 NR_STORE_HOST" '! grep -l -e "拷回 box" -e "01:00 的兜底" -e "改用 \`ssh box" $PR/*/*.md $PR/noop.prompt.md && ! grep -q box-watch $PR/noop.prompt.md && [ $(grep -l NR_STORE_HOST $PR/*/night-review-*.md | wc -l) -eq 8 ]'

# ---- G1: old and new night-review-gate.sh decide the same way when the new variables are not set ----
if [ "$mode" = post ]; then
  mkdir -p "$T/base"; git -C "$REPO" archive "$BASE" scripts | tar -x -C "$T/base"
  ck G1a post "新旧 night-review-gate.sh 在什么都不设时判定一致（逐个场景见 g1/G1a/REPORT.md）" 'python3 -I $E/gate-equivalence.py --old $T/base/scripts --new $S --set G1a --out $T/g1'
  ck G1b post "只设旧变量名 NR_BOX_HOST / NR_BOX_DIR 时判定一致（g1/G1b/REPORT.md）" 'python3 -I $E/gate-equivalence.py --old $T/base/scripts --new $S --set G1b --out $T/g1'
else
  skip G1a post "新旧 night-review-gate.sh 在什么都不设时判定一致" "only on post: it compares base with this checkout"
  skip G1b post "只设旧变量名 NR_BOX_HOST / NR_BOX_DIR 时判定一致" "only on post: it compares base with this checkout"
fi

# ---- end: caffeinate ends by itself; the mocks stop on their stop files; then what the spies saw ----
w=$(( (kt + 6 > ct + 31 ? kt + 6 : ct + 31) - $(date +%s) )); [ $w -gt 0 ] && sleep $w   # K1b: -t 3, W2e: -t 30
ck K1c drill "MBA 主预检和防睡任务起的 caffeinate 到时自己退出" '[ -n "$cpid" ] && [ -n "$kp" ] && ! sm "ps -o pid,ppid,rss,etime,comm -p $cpid" | grep -q caffeinate && ! sm "ps -o pid,ppid,rss,etime,comm -p $kp" | grep -q caffeinate'
touch "$T/mock-stop"; sm "touch $RT/mock-stop"; wait $MOCK; mrc=$?
mpid=$(sm "cat $RT/mock.pid"); for i in $(seq 1 25); do sm "ps -o pid,ppid,rss,etime,comm -p $mpid" >/dev/null 2>&1 || break; sleep 0.2; done
mhooks; sm "cat $RT/ssh-spy-mba.log 2>/dev/null" > "$T/ssh-spy-mba.log"
ck X1 drill "两台机器的 ssh 记录里没有 box（名字或地址），没有被拒的调用；确有 iMac→MBA、MBA→iMac 的记录（闸门和同步确实经过它）" 'spycheck "$BA_I $BA_M" $T/ssh-spy-imac.log $T/ssh-spy-mba.log && grep -q " pass mba " $T/ssh-spy-imac.log && grep -q " pass imac " $T/ssh-spy-mba.log'
ck X2 drill "演练文件里没有结束进程的命令；两台机器的假 webhook 看到停止文件后自己退出" 'nosignal $E/run-e2e.sh $E/gate-equivalence.py $E/ssh-spy $E/fake-ssh.py $E/mock_webhook.py && [ $mrc -eq 0 ] && ! ps -o pid,ppid,rss,etime,comm -p $MOCK | grep -qi python && ! sm "ps -o pid,ppid,rss,etime,comm -p $mpid" | grep -qi python'
ck W7c drill "两台机器的叫醒只到 127.0.0.1 上的假 webhook：ops-system 各至少 1 条，coding-assistant 0 条，KEY 都是假的那个" '[ $(hooks $T/hooks.jsonl ops-system) -ge 1 ] && [ $(hooks $T/mba-hooks.jsonl ops-system) -ge 1 ] && [ $(hooks $T/hooks.jsonl coding-assistant) -eq 0 ] && [ $(hooks $T/mba-hooks.jsonl coding-assistant) -eq 0 ] && ! grep -q "\"auth_ok\": false" $T/hooks.jsonl $T/mba-hooks.jsonl'

sm "tar -C $RT -czf - state-mba store-mba nr m6 home/.orca-state hooks.jsonl ssh-spy-mba.log sync-calls 2>/dev/null" > "$T/mba-artifacts.tgz" 2>>"$T/log"
case "$RT" in /tmp/b2a-e2e-*) sm "rm -rf $RT" 2>>"$T/log";; esac
shasum -a 256 "$T/results.tsv" > "$T/results.sha256"
echo "e2e $mode: $(grep -c '	PASS	' "$T/results.tsv") PASS, $(grep -c '	FAIL	' "$T/results.tsv") FAIL, $(grep -c '	SKIP	' "$T/results.tsv") SKIP of $n -> $T"
python3 -I - "$T/results.tsv" "$mode" <<'PY'
import sys
want = {"post": {"new": "PASS", "kept": "PASS", "drill": "PASS", "post": "PASS"},
        "pre": {"new": "FAIL", "kept": "PASS", "drill": "PASS", "post": "SKIP"}}[sys.argv[2]]
bad = [f[0] for f in (l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8")) if f[1] != want[f[2]]]
print(f"not as expected for {sys.argv[2]}: {', '.join(bad) or 'none'}")
sys.exit(1 if bad else 0)
PY
