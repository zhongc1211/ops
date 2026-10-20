#!/bin/bash
# run-e2e.sh [post|pre|both]: PER-79 drill for the box -> MBA / iMac heavy-job move (FAILURE-MODES.md has the ids).
#   post  the scripts and prompts in this checkout
#   pre   the same checks against origin/main (git archive, nothing checked out) and the live box prompts in
#         ../box-baseline: the revert test, every check should FAIL there
#   both  pre, then post, then revert.tsv (one line per check: post result, pre result)
# Real: the MBA (this machine, /bin/bash 3.2), the iMac over ssh (watch / backup / finish / sync run there from a copy
# in /tmp/per79-e2e-*), box over ssh read-only (manifests, worktree / terminal lists, sha256 before and after the sync,
# box-cleanup.sh --count fed on stdin), EverOS read-only (--dry-run --skip-existing). Not real, so this is a dry-run
# drill and not an e2e of the live automations: webhooks go to mock_webhook.py on 127.0.0.1 (fake HOME with fake env
# files), box's nightly-review dir is a local folder (NR_BOX_HOST=local), dates are 2099-01-xx (NR_D) with fixed
# clock times (NR_NOW), pmset / ioreg output comes from files, `orca` is a recorder that does nothing.
# Output: $E2E_OUT (default ~/.orca-state/e2e/migration-1020/<time>-<mode>): results.tsv (id, PASS/FAIL, what, check),
# log, META (commit, hosts, versions), sha256 of the results. Exit 0 = all PASS (post) / all FAIL (pre).
set -u
mode=${1:-post}
E=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$E/../../.." && pwd); MIG=$E/..
case "$mode" in
both)
  base=${E2E_OUT:-$HOME/.orca-state/e2e/migration-1020/$(date +%Y%m%d-%H%M%S)}
  E2E_OUT=$base/pre /bin/bash "$0" pre; E2E_OUT=$base/post /bin/bash "$0" post; rc=$?
  python3 -I - "$base" <<'PY'
import sys, os
b = sys.argv[1]
rd = lambda m: {l.split("\t")[0]: l.split("\t")[1] for l in open(os.path.join(b, m, "results.tsv"), encoding="utf-8")}
pre, post = rd("pre"), rd("post")
bad = [i for i in post if post[i] == "PASS" and pre.get(i) == "PASS"]
with open(os.path.join(b, "revert.tsv"), "w", encoding="utf-8") as f:
    for i in post:
        f.write(f"{i}\tpost={post[i]}\tpre={pre.get(i, 'missing')}\n")
print(f"revert: {len(post)} checks, {sum(v == 'PASS' for v in post.values())} PASS on post, "
      f"{sum(pre.get(i) == 'FAIL' for i in post)} FAIL on pre; passing on pre too: {', '.join(bad) or 'none'}")
sys.exit(1 if bad else 0)
PY
  rv=$?; echo "artifacts: $base"; exit $(( rc | rv ));;
post) OPS=$REPO; PR=$MIG/prompts;;
pre) ;;
*) echo "usage: run-e2e.sh post|pre|both" >&2; exit 2;;
esac
T=${E2E_OUT:-$HOME/.orca-state/e2e/migration-1020/$(date +%Y%m%d-%H%M%S)-$mode}
mkdir -p "$T"; : > "$T/results.tsv"; : > "$T/log"
if [ "$mode" = pre ]; then
  OPS=$T/tree; mkdir -p "$OPS"; git -C "$REPO" archive origin/main | tar -x -C "$OPS"; PR=$T/baseline-prompts
  mkdir -p "$PR/mba" "$PR/imac"     # the live box prompts are what the MBA / iMac would get without this change
  for x in 75b324a4:night-review-xinyue 43c55a22:night-review-deepvision-site 9b5c20e7:night-review-deepvision-ads c392a743:night-review-vllm-omni; do
    for m in mba imac; do cp "$MIG/box-baseline/${x%%:*}.prompt.md" "$PR/$m/${x#*:}.prompt.md"; done; done
  cp "$MIG/box-baseline/bc9ee42b.prompt.md" "$PR/imac/linear-sync.prompt.md"; cp "$MIG/box-baseline/349967f6.prompt.md" "$PR/imac/vllm-upstream.prompt.md"
fi
S=$OPS/scripts; RMIG=$OPS/automations/migration-1020
{ echo "mode=$mode"; echo "commit=$(git -C "$REPO" rev-parse HEAD)"; echo "tree=$OPS"; echo "date=$(date '+%F %T %z')"
  echo "host=$(hostname -s) bash=$(/bin/bash -c 'echo $BASH_VERSION') $(sw_vers -productVersion 2>/dev/null)"
  echo "imac=$(ssh -o BatchMode=yes imac 'hostname -s; /bin/bash -c "echo \$BASH_VERSION"' 2>/dev/null | tr '\n' ' ')"
  echo "box=$(ssh -o BatchMode=yes box 'hostname; bash -c "echo \$BASH_VERSION"' 2>/dev/null | tr '\n' ' ')"; } > "$T/META"
n=0
ck(){ local id=$1 what=$2; shift 2; n=$((n+1))
  if eval "$*" >>"$T/log" 2>&1; then r=PASS; else r=FAIL; fi
  printf '%s\t%s\t%s\t%s\n' "$id" "$r" "$what" "$(echo "$*" | tr '\n\t' '  ')" >> "$T/results.tsv"; echo "$r $id $what"; }
run(){ echo "+ $*" >> "$T/log"; "$@" >> "$T/log" 2>&1; }
out(){ echo "+ $*" >> "$T/log"; "$@" 2>>"$T/log" | tee -a "$T/log"; }
ep(){ python3 -I -c 'import sys,datetime as d; print(int(d.datetime.fromisoformat(sys.argv[1]+"+08:00").timestamp()))' "$1"; }
HL="/bin/bash $S/heavy-lock.sh"; G="/bin/bash $S/night-review-gate.sh"

# fake HOME with fake webhook env files -> local mock (KEY e2e-fake, never a real one)
FH=$T/home; mkdir -p "$FH/.config/grokbot/webhooks"
python3 -I "$E/mock_webhook.py" "$T/hooks.jsonl" "$T/port" 900 & MOCK=$!
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/port" ] && break; sleep 0.3; done; PORT=$(cat "$T/port")
for b in ops-system coding-assistant; do printf 'URL=http://127.0.0.1:%s/%s\nKEY=e2e-fake\n' "$PORT" "$b" > "$FH/.config/grokbot/webhooks/$b.env"; done
hooks(){ python3 -I -c 'import json,sys; p,k=sys.argv[2],sys.argv[3:]
n=0
for l in open(sys.argv[1]) if __import__("os").path.exists(sys.argv[1]) else []:
    o=json.loads(l); s=json.dumps(o,ensure_ascii=False)
    n+=o["path"]=="/"+p and all(x in s for x in k)
print(n)' "$1" "$2" "${@:3}"; }

# ---- L: heavy-lock (MBA, /bin/bash 3.2) ----
export HEAVY_LOCK_DIR=$T/l1/lock
run $HL acquire night-review-vllm-omni; run $HL acquire vllm-upstream; rc=$?
ck L1 "锁被占时第二个 acquire 退出 1，status 显示持有者" '[ $rc -eq 1 ] && $HL status | grep -q name=night-review-vllm-omni'
export HEAVY_LOCK_DIR=$T/l2/lock; mkdir -p "$T/l2"
pids=""; for i in 1 2 3 4 5 6 7 8; do ( $HL acquire job$i >/dev/null 2>&1; echo $? > "$T/l2/rc$i" ) & pids="$pids $!"; done; wait $pids
ck L2 "8 个并发 acquire 恰好 1 个拿到" '[ $(cat $T/l2/rc* | grep -c "^0$") -eq 1 ]'
export HEAVY_LOCK_DIR=$T/l3/lock; now=$(date +%s)
run $HL acquire dead-job; sed -i '' "s/since=[0-9]*/since=$((now-41*60))/" "$HEAVY_LOCK_DIR/owner" 2>/dev/null
run $HL acquire fresh-job; rc=$?
ck L3a "超过 40 分钟的锁被收回" '[ $rc -eq 0 ] && $HL status | grep -q name=fresh-job'
sed -i '' "s/since=[0-9]*/since=$((now-39*60))/" "$HEAVY_LOCK_DIR/owner" 2>/dev/null; run $HL acquire other-job; rc=$?
ck L3b "39 分钟的锁不收回" '[ $rc -eq 1 ] && $HL status | grep -q name=fresh-job'
run $HL release other-job; rc=$?
ck L4a "名字不对的 release 退出 1，锁还在" '[ $rc -eq 1 ] && $HL status | grep -q name=fresh-job'
run $HL refresh fresh-job
ck L5 "refresh 后重新计时" '[ $(( $(date +%s) - $($HL status | sed -n "s/.*since=\([0-9]*\).*/\1/p") )) -lt 60 ]'
run $HL release fresh-job
ck L4b "本人 release 后锁空" '[ -f $HEAVY_LOCK_DIR.log ] && ! $HL status'
unset HEAVY_LOCK_DIR

# ---- D: dates under /bin/bash 3.2 (macOS date has no -d) ----
rd(){ REVIEW_NOW=$(ep "$1") /bin/bash "$S/review-date.sh" ago "$2" 2>>"$T/log"; }
ck D1a "00:30 往回 13 小时 = 昨天" '[ "$(rd 2026-10-21T00:30:00 13)" = 2026-10-20 ]'
ck D1b "23:40 往回 6 小时 = 当天" '[ "$(rd 2026-10-20T23:40:00 6)" = 2026-10-20 ]'
ck D1c "跨月、跨年、闰年" '[ "$(rd 2026-11-01T01:20:00 13)" = 2026-10-31 ] && [ "$(rd 2027-01-01T00:55:00 13)" = 2026-12-31 ] && [ "$(rd 2028-03-01T00:30:00 13)" = 2028-02-29 ]'
ck D1d "next：闰年、跨年" '[ "$(/bin/bash $S/review-date.sh next 2028-02-28)" = 2028-02-29 ] && [ "$(/bin/bash $S/review-date.sh next 2026-12-31)" = 2027-01-01 ]'
ck D2 "MBA / iMac 提示词不含 date -d，日期用 review-date.sh" '! grep -l "date -d" $PR/*/night-review-*.md && [ $(grep -l "review-date.sh ago" $PR/*/night-review-*.md | wc -l) -eq 8 ]'
dcmd(){ python3 -I -c 'import re,sys; print(re.search(r"D=\$\(([^)]*)\)", open(sys.argv[1]).read()).group(1))' "$1"; }
d3(){ local f c d ok=0; for f in $PR/$2/night-review-*.md; do c=$(dcmd "$f" | sed "s|~/orca/workspaces/ops|$1|g")
  if [ "$2" = imac ]; then d=$(ssh -o BatchMode=yes imac "/bin/bash -c $(printf %q "$c")" 2>>"$T/log"); else d=$(/bin/bash -c "$c" 2>>"$T/log"); fi; echo "D3 $(basename $f) [$c] -> '$d'" >> "$T/log"; echo "$d" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || ok=1; done; return $ok; }
ck D3a "4 个夜审提示词里算 D 的命令在 MBA /bin/bash 3.2 上实跑出日期" 'd3 $OPS mba'

# ---- M: manifest sync, real box (read-only), real peers ----
P=vllm-omni; MD=2026-10-19; M=$T/m1
boxsum(){ ssh -o BatchMode=yes box "cd /var/lib/everos-ingest/$P/$MD && find . -type f | sort | xargs -d '\n' sha256sum | sha256sum" 2>>"$T/log"; }
b0=$(boxsum); mkdir -p "$M/dst/$P/$MD/raw"; echo keep > "$M/dst/$P/$MD/raw/local-extra.txt"
t0=$(date +%s); SYNC_DST_ROOT=$M/dst run /bin/bash "$S/sync-manifests-from-box.sh" $P $MD mba; rc=$?; rcM1=$rc; echo "M1 sync ${rc} in $(( $(date +%s) - t0 ))s" >> "$T/log"
b1=$(boxsum)
ck M1a "MBA 同步成功，SYNC-STATUS=ok" '[ $rc -eq 0 ] && grep -q "^ok " $M/dst/$P/$MD/SYNC-STATUS'
ck M1b "同步后每个 transcript_path 都是本机可读文件" 'python3 -I -c "
import json,glob,os,sys
n=0
for f in glob.glob(sys.argv[1]+\"/sessions-*.jsonl\"):
    if f.endswith(\".excluded.jsonl\"): continue
    for l in open(f):
        o=json.loads(l); tp=o.get(\"transcript_path\")
        if tp: n+=1; assert os.access(tp,os.R_OK) and not tp.startswith(\"/var/lib\") and not tp.startswith(\"/home/box\"), tp
assert n>0
print(n,\"transcripts readable\")" $M/dst/$P/$MD'
ck M3a "同步成功，box 源目录 sha256 同步前后一致" '[ $rcM1 -eq 0 ] && [ -n "$b0" ] && [ "$b0" = "$b1" ]'
ck M3b "同步成功，本地多余文件保留" '[ $rcM1 -eq 0 ] && [ -f $M/dst/$P/$MD/raw/local-extra.txt ]'
SYNC_DST_ROOT=$T/m2/dst SYNC_SRC_HOST=nosuchhost.invalid run /bin/bash "$S/sync-manifests-from-box.sh" $P $MD mba; rc=$?
ck M2a "box 连不上：退出 3，SYNC-STATUS=failed" '[ $rc -eq 3 ] && grep -q "^failed reach" $T/m2/dst/$P/$MD/SYNC-STATUS'
SYNC_DST_ROOT=$T/m2/dst run /bin/bash "$S/sync-manifests-from-box.sh" $P 2001-01-01 mba; rc=$?
ck M2b "box 上没有这天：退出 3，SYNC-STATUS=failed" '[ $rc -eq 3 ] && grep -q "^failed" $T/m2/dst/$P/2001-01-01/SYNC-STATUS'

# ---- iMac: a copy of the scripts in /tmp, fake HOME, its own mock ----
RT=/tmp/per79-e2e-$(basename "$T"); IH=$RT/home
ssh -o BatchMode=yes imac "mkdir -p $RT/ops/scripts $RT/ops/everos-ingest $IH/.config/grokbot/webhooks" 2>>"$T/log"
for f in night-review-gate.sh heavy-lock.sh review-date.sh sync-manifests-from-box.sh orca-due.sh; do [ -f "$S/$f" ] && scp -q "$S/$f" "imac:$RT/ops/scripts/" 2>>"$T/log"; done
scp -q "$E/mock_webhook.py" "imac:$RT/" 2>>"$T/log"
ssh -o BatchMode=yes imac "nohup python3 -I $RT/mock_webhook.py $RT/hooks.jsonl $RT/port 900 >/dev/null 2>&1 & for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s $RT/port ] && break; sleep 0.5; done; p=\$(cat $RT/port)
  for b in ops-system coding-assistant; do printf 'URL=http://127.0.0.1:%s/%s\nKEY=e2e-fake\n' \$p \$b > $IH/.config/grokbot/webhooks/\$b.env; done" 2>>"$T/log"
NR=~/.local/bin/notify-run; INR=$(ssh -o BatchMode=yes imac 'echo ~/.local/bin/notify-run')
IENV="HOME=$IH NR_BOX_HOST=local NR_BOX_DIR=$RT/box NR_STATE=$RT/state HEAVY_LOCK_DIR=$RT/lock NR_CAFFEINATE_T=5 NR_SYNC=/usr/bin/true NR_DIR=$RT/nr NR_MBA_HOST=mba NR_MBA_STATE=$T/state-mba"
gi(){ echo "+ imac: $*" >> "$T/log"; ssh -o BatchMode=yes imac "cd $RT && env $IENV $*" 2>>"$T/log" | tee -a "$T/log"; return ${PIPESTATUS[0]}; }
GI="/bin/bash ops/scripts/night-review-gate.sh"
istat(){ ssh -o BatchMode=yes imac "cat $RT/state/vllm-omni/$1.${2:-status}" 2>/dev/null; }
ck D3b "同样的命令在 iMac（没有 gdate）实跑出日期" 'd3 $RT/ops imac'
M1i=$RT/m1i
gi SYNC_DST_ROOT=$M1i /bin/bash ops/scripts/sync-manifests-from-box.sh $P $MD imac >/dev/null; rc=$?
ck M1i "iMac 实机同步（box 只读、MBA 对等拉取）成功" '[ $rc -eq 0 ] && ssh -o BatchMode=yes imac "grep -q \"^ok \" $M1i/$P/$MD/SYNC-STATUS"'

# ---- W: who runs the night (MBA primary here, iMac watch / backup over ssh) ----
# vllm-omni: MBA 01:20, iMac watch 01:50, backup from 01:50, box watch 03:50 (night of 2026-10-21 SGT clock times)
tM=$(ep 2026-10-21T01:21:00); tW=$(ep 2026-10-21T01:50:00); tB=$(ep 2026-10-21T02:00:00); tX=$(ep 2026-10-21T03:50:00)
BOXD=$T/box-nr; mkdir -p "$BOXD" "$T/nr"
printf '#!/bin/bash\necho "$@" >> %s/sync-calls\n' "$T" > "$T/fake-sync.sh"
MENV="HOME=$FH NR_BOX_HOST=local NR_BOX_DIR=$BOXD NR_STATE=$T/state-mba HEAVY_LOCK_DIR=$T/lock-mba NR_CAFFEINATE_T=5 NR_SYNC=$T/fake-sync.sh NR_DIR=$T/nr"
AC=$T/pm-ac; echo "Now drawing from 'AC Power'" > "$AC"; BAT=$T/pm-bat; echo "Now drawing from 'Battery Power'" > "$BAT"
OPEN=$T/io-open; echo '    "AppleClamshellState" = No' > "$OPEN"; SHUT=$T/io-shut; echo '    "AppleClamshellState" = Yes' > "$SHUT"
PMN=$T/pm-nosd; echo ' sleep 1' > "$PMN"; PMS=$T/pm-sd; printf ' SleepDisabled\t\t1\n sleep 0\n' > "$PMS"
DSP=$T/displays; printf '  Resolution: 2560 x 1664\n  Connection Type: Internal\n' > "$DSP"
gm(){ echo "+ mba: $*" >> "$T/log"; env $MENV NR_PMSET_BATT=${BATT:-$AC} NR_PMSET_G=${PMG:-$PMS} NR_IOREG=${IO:-$OPEN} NR_DISPLAYS=$DSP "$@" 2>>"$T/log" | tee -a "$T/log"; return ${PIPESTATUS[0]}; }
mstat(){ cat "$T/state-mba/vllm-omni/$1.status" 2>/dev/null; }

# W1 MBA offline -> iMac watcher marks takeover, backup takes the iMac lock, finish wakes ops-system with machine=imac
D=2099-01-01
gi NR_D=$D NR_NOW=$tW NR_MBA_HOST=nosuchhost.invalid $GI watch vllm-omni >/dev/null; rc=$?
ck W1a "MBA 离线：看守退出 1、写接替标记 reason=offline" '[ $rc -eq 1 ] && istat $D takeover | grep -q reason=offline'
gi NR_D=$D NR_NOW=$tB $GI backup vllm-omni >/dev/null; rc=$?
ck W1b "iMac 备用拿 iMac 锁放行" '[ $rc -eq 0 ] && istat $D | tail -1 | grep -q "state=started machine=imac reason=offline" && gi /bin/bash ops/scripts/heavy-lock.sh status | grep -q night-review-vllm-omni'
ssh -o BatchMode=yes imac "mkdir -p $RT/nr && printf '# vllm-omni %s\n状态：完成\n' $D > $RT/nr/$D-vllm-omni.md"
R=$(gi $GI reason vllm-omni $D)
gi NR_D=$D NR_NOW=$tB $INR --bot ops-system --no-tty --task "\"vllm-omni夜审 $D machine=imac reason=$R\"" -- $GI finish vllm-omni $D imac "$R" >/dev/null; rc=$?
ck W1c "收尾：拷回 box 目录、记 done、放锁，ops-system 收到 task 含 machine=imac reason=offline" '[ $rc -eq 0 ] && istat $D | grep -q "state=done machine=imac reason=offline" && ! gi /bin/bash ops/scripts/heavy-lock.sh status && [ $(ssh imac cat $RT/hooks.jsonl | grep -c "machine=imac reason=offline") -eq 1 ] && ssh imac "grep -q 状态 $RT/box/$D-vllm-omni.md"'

# W2 MBA asleep: on battery; lid closed and would sleep; precheck never ran
D=2099-01-02; BATT=$BAT gm NR_D=$D NR_NOW=$tM $G primary vllm-omni >/dev/null; rc=$?
ck W2a "用电池：主预检退出 1，记 missed reason=asleep" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q "state=missed machine=mba reason=asleep detail=on_battery"'
gi NR_D=$D NR_NOW=$tW $GI watch vllm-omni >/dev/null
ck W2b "看守（iMac 经 ssh 读 MBA）判 asleep" 'istat $D takeover | grep -q reason=asleep'
D=2099-01-03; IO=$SHUT PMG=$PMN gm NR_D=$D NR_NOW=$tM $G primary vllm-omni >/dev/null; rc=$?
ck W2c "合盖、没禁睡、没外接屏：主预检退出 1，reason=asleep detail=lid_closed" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q "reason=asleep detail=lid_closed"'
D=2099-01-11; gi NR_D=$D NR_NOW=$tW $GI watch vllm-omni >/dev/null
ck W2d "MBA 能连上但当晚预检没跑：看守判 asleep" 'istat $D takeover | grep -q reason=asleep'
# W2b (A18) lid closed, on AC, SleepDisabled 1 = the MBA today -> runs; K1 caffeinate
D=2099-01-04; IO=$SHUT PMG=$PMS gm NR_D=$D NR_NOW=$tM $G primary vllm-omni >/dev/null; rc=$?
cpid=$(mstat $D | tail -1 | sed -n 's/.*caffeinate=\([0-9]*\).*/\1/p')
ck W2e "合盖但接电源、SleepDisabled=1：主预检放行，记 started" '[ $rc -eq 0 ] && mstat $D | tail -1 | grep -q "state=started machine=mba reason=ok"'
ck K1a "主预检起了带 -t 的 caffeinate" '[ -n "$cpid" ] && ps -o command= -p $cpid | grep -q "caffeinate -i -t 5"'
ck S1 "主预检先同步清单再拿锁（同步调用记录有 vllm-omni $D mba）" 'grep -q "vllm-omni $D mba" $T/sync-calls'
gm NR_D=$D NR_NOW=$((tM+600)) $G primary vllm-omni >/dev/null; rc=$?
ck W8a "补跑触发时当晚已 started：退出 1，不记 lock_busy" '[ $rc -eq 1 ] && [ "$(mstat $D | tail -1 | grep -c lock_busy)" = 0 ]'
gi NR_D=$D NR_NOW=$tW $GI watch vllm-omni >/dev/null
ck W8b "MBA 在跑（started < 60 分钟）：看守不写接替标记" '! istat $D takeover >/dev/null && istat $D | tail -1 | grep -q state=seen_running'
gm /bin/bash $S/heavy-lock.sh release night-review-vllm-omni >/dev/null
D=2099-01-12; gm NR_D=$D NR_NOW=$((tM+40*60)) $G primary vllm-omni >/dev/null; rc=$?
ck W8c "补跑在 MBA 时间 +25 分钟以后不起（交给 iMac）" '[ $rc -eq 1 ] && ! mstat $D | grep -q started'
gi NR_D=$D NR_NOW=$((tM+10*60)) $GI backup vllm-omni >/dev/null; rc=$?
ck W8d "MBA 时间 +30 分钟以前 iMac 备用不接替" '[ $rc -eq 1 ] && ! istat $D takeover >/dev/null'

# W3 MBA lock busy -> lock_busy, watcher hands to the iMac
D=2099-01-05; gm /bin/bash $S/heavy-lock.sh acquire vllm-upstream >/dev/null
gm NR_D=$D NR_NOW=$tM $G primary vllm-omni >/dev/null; rc=$?
ck W3a "MBA 锁被占：主预检记 lock_busy" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q "reason=lock_busy detail=vllm-upstream"'
gi NR_D=$D NR_NOW=$tW $GI watch vllm-omni >/dev/null
ck W3b "看守判 lock_busy 并交给 iMac" 'istat $D takeover | grep -q reason=lock_busy'
gm /bin/bash $S/heavy-lock.sh release vllm-upstream >/dev/null

# W4 iMac lock busy > 60 min after the takeover -> one stuck to ops-system (machine=box), only once
D=2099-01-06; ssh imac "mkdir -p $RT/state/vllm-omni && echo 'reason=offline since=$((tB-3700))' > $RT/state/vllm-omni/$D.takeover"
gi /bin/bash ops/scripts/heavy-lock.sh acquire linear-sync >/dev/null
gi NR_D=$D NR_NOW=$tB $GI backup vllm-omni >/dev/null; rc=$?
gi NR_D=$D NR_NOW=$((tB+600)) $GI backup vllm-omni >/dev/null
ck W4 "iMac 锁被占超过 60 分钟：ops-system 收到 1 条 stuck machine=box，只 1 条" '[ $rc -eq 1 ] && [ $(ssh imac cat $RT/hooks.jsonl | grep "\"status\": \"stuck\"" | grep -c "machine=box reason=lock_busy") -eq 1 ]'
gi /bin/bash ops/scripts/heavy-lock.sh release linear-sync >/dev/null

# W5 / W6 done on box -> nobody runs again
D=2099-01-07; printf '状态：完成\n' > "$BOXD/$D-vllm-omni.md"; ssh imac "mkdir -p $RT/box && printf '状态：完成\n' > $RT/box/$D-vllm-omni.md && echo 'reason=offline since=$tB' > $RT/state/vllm-omni/$D.takeover"
gm NR_D=$D NR_NOW=$tM $G primary vllm-omni >/dev/null; rc=$?
ck W5 "box 已有完成摘要：主预检退出 1" '[ $rc -eq 1 ] && mstat $D | tail -1 | grep -q already_done'
gi NR_D=$D NR_NOW=$tB $GI backup vllm-omni >/dev/null; rc=$?
ck W6 "box 已有完成摘要：备用预检退出 1，不拿锁" '[ $rc -eq 1 ] && ! gi /bin/bash ops/scripts/heavy-lock.sh status'

# W7 box watcher (run here with box's local paths faked; reads the iMac over ssh): iMac running -> quiet; nobody -> 1 stuck
D=2099-01-08; ssh imac "mkdir -p $RT/state/vllm-omni && echo 'state=started machine=imac reason=offline ts=$((tX-1800))' > $RT/state/vllm-omni/$D.status"
gm NR_D=$D NR_NOW=$tX NR_IMAC_HOST=imac NR_IMAC_STATE=$RT/state $G box-watch vllm-omni >/dev/null
D2=2099-01-09; gm NR_D=$D2 NR_NOW=$tX NR_IMAC_HOST=imac NR_IMAC_STATE=$RT/state $G box-watch vllm-omni >/dev/null; rc=$?
gm NR_D=$D2 NR_NOW=$((tX+600)) NR_IMAC_HOST=imac NR_IMAC_STATE=$RT/state $G box-watch vllm-omni >/dev/null
ck W7a "box 看守：iMac 接替在跑时不发" '[ $(hooks $T/hooks.jsonl ops-system 2099-01-08) -eq 0 ] && mstat $D | grep -q seen_imac_running'
ck W7b "box 看守：没人完成时 ops-system 收到 1 条 stuck machine=box reason=imac_missed，只 1 条" '[ $rc -eq 1 ] && [ $(hooks $T/hooks.jsonl ops-system "machine=box reason=imac_missed" 2099-01-09) -eq 1 ]'
ck W7c "两台机器的叫醒都到了 ops-system（各至少 1 条），Coding助手 的假地址收到 0 条，KEY 对" '[ $(hooks $T/hooks.jsonl ops-system) -ge 1 ] && [ $(ssh imac cat $RT/hooks.jsonl | grep -c /ops-system) -ge 1 ] && [ $(hooks $T/hooks.jsonl coding-assistant) -eq 0 ] && [ $(ssh imac cat $RT/hooks.jsonl | grep -c /coding-assistant) -eq 0 ] && ! grep -q "\"auth_ok\": false" $T/hooks.jsonl'

# finish failure paths (MBA)
D=2099-01-10; gm /bin/bash $S/heavy-lock.sh acquire night-review-vllm-omni >/dev/null; printf '状态：进行中\n' > "$T/nr/$D-vllm-omni.md"
gm NR_D=$D $G finish vllm-omni $D mba ok >/dev/null; rc=$?
ck F1 "摘要没有「状态：完成」：finish 退出 3，放锁" '[ $rc -eq 3 ] && ! gm /bin/bash $S/heavy-lock.sh status'
gm /bin/bash $S/heavy-lock.sh acquire night-review-vllm-omni >/dev/null; printf '状态：完成\n' > "$T/nr/$D-vllm-omni.md"
gm NR_D=$D NR_BOX_HOST=nosuchhost.invalid $G finish vllm-omni $D mba ok >/dev/null; rc=$?
ck F2 "拷不回 box：finish 退出 4，记 rsync_failed，放锁" '[ $rc -eq 4 ] && mstat $D | tail -1 | grep -q detail=rsync_failed && ! gm /bin/bash $S/heavy-lock.sh status'

# K1 keepawake task
o=$(NR_CAFFEINATE_T=3 /bin/bash "$S/night-review-gate.sh" keepawake 2>>"$T/log"); rc=$?; kp=$(echo "$o" | sed -n 's/.*pid \([0-9]*\).*/\1/p'); echo "$o" >> "$T/log"
ck K1b "防睡任务起 caffeinate -i -t 后退出 1（不起模型）" '[ $rc -eq 1 ] && [ -n "$kp" ] && ps -o command= -p $kp | grep -q "caffeinate -i -t 3"'

# ---- C: box cleanup prechecks on real box snapshots (read-only) ----
C=$T/c1; mkdir -p "$C"
ssh -o BatchMode=yes box 'export PATH=$HOME/.local/bin:$PATH; orca worktree list --json' > "$C/wt.json" 2>>"$T/log"
ssh -o BatchMode=yes box 'export PATH=$HOME/.local/bin:$PATH; orca terminal list --json' > "$C/term.json" 2>>"$T/log"
cw(){ env HOME=$FH HEAVY_LOCK_DIR=$C/lock CLEANUP_STATE=$C/state CLEANUP_WT_JSON=${WT:-$C/wt.json} CLEANUP_TERM_JSON=${TM:-$C/term.json} "$@" /bin/bash $S/cleanup-precheck.sh ws >>"$T/log" 2>&1; }
cw; rc=$?
ck C1a "真 box 快照首轮放行，拿 box 重活锁、记 due" '[ $rc -eq 0 ] && HEAVY_LOCK_DIR=$C/lock $HL status | grep -q orca-ws-cleanup && [ -f $FH/.orca-state/runs/orca-ws-cleanup.due ]'
HEAVY_LOCK_DIR=$C/lock run $HL release orca-ws-cleanup; mkdir -p "$C/state"; touch "$C/state/$(TZ=Asia/Singapore date +%F).md"; rm -f "$FH/.orca-state/runs/orca-ws-cleanup.due"
cw; rc=$?
ck C1b "上轮跑过、快照没变：退出 1，不拿锁、不记 due" '[ $rc -eq 1 ] && ! HEAVY_LOCK_DIR=$C/lock $HL status && [ ! -f $FH/.orca-state/runs/orca-ws-cleanup.due ]'
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["result"]["worktrees"].append({"path":"/workspace/e2e-new-ws","workspaceStatus":"completed","isArchived":False,"isMainWorktree":False,"lastActivityAt":1}); json.dump(d,open(sys.argv[2],"w"))' "$C/wt.json" "$C/wt-new.json" 2>>"$T/log"
WT=$C/wt-new.json cw; rc=$?
ck C1c "多一个新 completed 工作区：放行" '[ $rc -eq 0 ]'
HEAVY_LOCK_DIR=$C/lock run $HL release orca-ws-cleanup
echo '{"result":{"worktrees":[]}}' > "$C/wt-empty.json"; echo '{"result":{"terminals":[]}}' > "$C/term-empty.json"
WT=$C/wt-empty.json TM=$C/term-empty.json cw CLEANUP_STATE=$C/state-empty; rc=$?
ck C1d "空快照：退出 1" '[ $rc -eq 1 ]'
HEAVY_LOCK_DIR=$C/lock run $HL acquire night-review-xinyue; WT=$C/wt-new.json cw CLEANUP_STATE=$C/state-busy; rc=$?
ck C1e "有活但锁被占：退出 1" '[ $rc -eq 1 ] && HEAVY_LOCK_DIR=$C/lock $HL status | grep -q night-review-xinyue'
HEAVY_LOCK_DIR=$C/lock run $HL release night-review-xinyue
cm(){ env HOME=$FH HEAVY_LOCK_DIR=$C/mlock "$@" /bin/bash $S/cleanup-precheck.sh mem >>"$T/log" 2>&1; }
cm CLEANUP_COUNT=0; rc0=$?; cm CLEANUP_COUNT=3; rc3=$?
ck C2a "内存清理：没可结束的进程、没压力退出 1；有就放行并拿锁" '[ $rc0 -eq 1 ] && [ $rc3 -eq 0 ] && HEAVY_LOCK_DIR=$C/mlock $HL status | grep -q box-mem-cpu-cleanup'
if [ "$mode" = post ]; then   # never feed origin/main's box-cleanup.sh to box: without --count it would run a real cleanup
  cnt=$(ssh -o BatchMode=yes box 'test -d ~/.orca-state/cleanup && bash -s -- --count' < "$S/box-cleanup.sh" 2>>"$T/log"); echo "box --count: $cnt" >> "$T/log"
else cnt=""; echo "C2b pre: not run on box (origin/main box-cleanup.sh has no --count and would clean for real)" >> "$T/log"; fi
ck C2b "真 box：box-cleanup.sh --count（stdin 喂入，不发信号）打印一个整数" 'echo "$cnt" | grep -Eq "^[0-9]+$"'

# ---- R: register.sh never calls orca by default ----
mkdir -p "$T/fakebin"; printf '#!/bin/bash\necho "$@" >> %s/orca-calls\n' "$T" > "$T/fakebin/orca"; chmod +x "$T/fakebin/orca"
for m in mba imac box; do PATH=$T/fakebin:$PATH /bin/bash "$RMIG/register.sh" $m > "$T/register-$m.out" 2>>"$T/log"; done
ck R1a "register 默认 dry-run：orca 调用 0 次" '[ -f $RMIG/register.sh ] && [ ! -e $T/orca-calls ]'
ck R1b "每条 create 都带 --missed-run-grace-minutes 120 和 --disabled；MBA 9 / iMac 10 / box 4 条" 'c=$(cat $T/register-*.out | grep -c "^orca automations create"); [ $c -eq 23 ] && [ $(cat $T/register-*.out | grep "^orca automations create" | grep -- "--missed-run-grace-minutes 120" | grep -c -- "--disabled") -eq $c ] && [ $(grep -c "^orca automations create" $T/register-mba.out) -eq 9 ] && [ $(grep -c "^orca automations create" $T/register-imac.out) -eq 10 ]'
ck R1c "box 旧任务的 grace 全改 120，两个清理加预检，兜底改 01:00" '[ $(grep -c "^orca automations edit .* --missed-run-grace-minutes 120" $T/register-box.out) -eq 8 ] && grep -q "cleanup-precheck.sh ws" $T/register-box.out && grep -q "cleanup-precheck.sh mem" $T/register-box.out && grep -q "edit 27383c07 --trigger .0 1 \* \* \*." $T/register-box.out'

# ---- P: prompts ----
ck P1a "MBA / iMac 提示词不含 /workspace/repos、/var/lib/everos-ingest、load>8、coding-assistant" '! grep -El "/workspace/repos|/var/lib/everos-ingest|load *> *8|coding-assistant" $PR/*/*.md'
ck P1b "8 个夜审提示词都有 caffeinate、heavy-lock refresh、SYNC-STATUS、finish、状态：完成、首行运行环境" 'for f in $PR/*/night-review-*.md; do grep -q "caffeinate -dimsu -w" $f && grep -q "heavy-lock.sh refresh" $f && grep -q SYNC-STATUS $f && grep -q "night-review-gate.sh finish" $f && grep -q "状态：完成" $f && head -1 $f | grep -q "运行环境：" || exit 1; done'
ck P1c "make-prompts.py --check：提交的提示词和生成结果一致" 'python3 -I $RMIG/make-prompts.py --check'
ck P1d "iMac 接替提示词写明读回去重；MBA 版没有" '[ $(grep -l "接替运行" $PR/imac/night-review-*.md | wc -l) -eq 4 ] && ! grep -l "接替运行" $PR/mba/*.md'

# ---- E: real EverOS, read-only: takeover dedupe on the synced vllm-omni 2026-10-19 (box already wrote it) ----
mkdir -p "$T/e1"
run python3 -I "$OPS/everos-ingest/nightly_addflush.py" --project vllm-omni --date $MD --dry-run --skip-existing \
  --sessions-dir "$M/dst/$P/$MD" --log "$T/e1/log.json" --ledger "$T/e1/ledger.jsonl"; rc=$?
ck E1 "--skip-existing：box 已写过的会话 result=ALREADY、不写（真 EverOS 只读 dry-run）" '[ $rc -eq 0 ] && python3 -I -c "
import json,sys,collections
L=json.load(open(sys.argv[1])); c=collections.Counter(r.get(\"result\") for r in L); print(dict(c))
assert c[\"ALREADY\"]>0 and c[\"FAIL\"]==0 and not c[\"OK\"]" $T/e1/log.json'

# ---- K1: the caffeinate started by the precheck ends by itself ----
sleep 6
ck K1c "主预检和防睡任务起的 caffeinate 到时自己退出" '! ps -p ${cpid:-999999} >/dev/null && ! ps -p ${kp:-999999} >/dev/null'

# cleanup: mocks, iMac copy
kill $MOCK 2>/dev/null; wait $MOCK 2>/dev/null; ssh -o BatchMode=yes imac "pkill -f '$RT/mock_webhook.py'; cat $RT/hooks.jsonl 2>/dev/null" > "$T/imac-hooks.jsonl" 2>>"$T/log"
ssh -o BatchMode=yes imac "tar -C $RT -czf - state box nr home/.orca-state 2>/dev/null" > "$T/imac-artifacts.tgz" 2>>"$T/log"
ssh -o BatchMode=yes imac "rm -rf $RT" 2>>"$T/log"
pass=$(grep -c "	PASS	" "$T/results.tsv"); fail=$(grep -c "	FAIL	" "$T/results.tsv")
shasum -a 256 "$T/results.tsv" > "$T/results.sha256"
echo "e2e $mode: $pass PASS, $fail FAIL of $n -> $T"
if [ "$mode" = post ]; then [ "$fail" -eq 0 ]; else [ "$pass" -eq 0 ]; fi
