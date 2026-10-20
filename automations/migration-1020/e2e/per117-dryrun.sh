#!/bin/bash
# per117-dryrun.sh [<tree>]: PER-117 check that only the Linear sync moves to the iMac and vllm · 17 (349967f6) stays on box.
# Runs register.sh imac|box|mba as a dry-run from <tree> (default: this checkout) and from the base (git archive of
# $PER117_BASE, default the #49 head this was cut from), with a fake `orca` first in PATH that logs and exits 99.
# Failure modes it catches (written before the change):
#   F1 the iMac still gets the vllm · 17 create (defs.json not edited)
#   F2 the iMac Linear sync create is dropped or its arguments change
#   F3 box still edits 349967f6, or 349967f6 is still in the "later ... --disabled" list; bc9ee42b drops out of it
#   F4 the MBA output changes
#   F5 a create loses --disabled or --missed-run-grace-minutes 120
#   F6 register.sh fails (a prompt file removed while defs.json still points at it) or prints a partial list
#   F7 the dry-run calls orca
# Output: $PER117_OUT (default ~/.orca-state/e2e/per117/<time>): base-<m>.txt, new-<m>.txt, <m>.diff, orca-calls.log,
# results.tsv. Exit 0 = every check PASS.
set -u
E=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$E/../../.." && pwd)
NEW=${1:-$REPO}; BASE_SHA=${PER117_BASE:-a8a0a2156eadacd0d84d821335da3b4c8f3eefb0}
T=${PER117_OUT:-$HOME/.orca-state/e2e/per117/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$T/bin" "$T/base"; : > "$T/results.tsv"; : > "$T/orca-calls.log"
printf '#!/bin/sh\necho "orca $*" >> "%s"\nexit 99\n' "$T/orca-calls.log" > "$T/bin/orca"; chmod +x "$T/bin/orca"
git -C "$REPO" archive "$BASE_SHA" automations/migration-1020 | tar -x -C "$T/base"
{ echo "base=$BASE_SHA"; echo "new=$NEW"; echo "new_commit=$(git -C "$NEW" rev-parse HEAD 2>/dev/null || echo none)"
  echo "host=$(hostname -s) bash=$(/bin/bash -c 'echo $BASH_VERSION') date=$(date '+%F %T %z')"; } > "$T/META"
for m in imac box mba; do
  PATH="$T/bin:$PATH" /bin/bash "$T/base/automations/migration-1020/register.sh" $m > "$T/base-$m.txt" 2>&1; echo "base $m rc=$?" >> "$T/META"
  PATH="$T/bin:$PATH" /bin/bash "$NEW/automations/migration-1020/register.sh" $m > "$T/new-$m.txt" 2>&1; echo "new $m rc=$?" >> "$T/META"
  diff "$T/base-$m.txt" "$T/new-$m.txt" > "$T/$m.diff"
done
bad=0
ck(){ local id=$1 what=$2; shift 2
  if ( eval "$*" ) >/dev/null 2>&1; then r=PASS; else r=FAIL; bad=1; fi
  printf '%s\t%s\t%s\t%s\n' "$id" "$r" "$what" "$*" >> "$T/results.tsv"; echo "$r $id $what"; }
# the comment line and the command line that follow "# <key>"
block(){ grep -A1 "^# $2\( \|$\)" "$1"; }
N="$T/new"; B="$T/base"
ck R1 "imac/box/mba 三个 dry-run 都退出 0" '! grep -q "^new .* rc=[^0]" $T/META'
ck R2 "dry-run 没调用 orca（假 orca 日志为空）" '[ ! -s $T/orca-calls.log ]'
ck I1 "imac 没有 vllm 上游那条 create" '! grep -q "imac-vllm-upstream\|上游 PR 监控" $N-imac.txt'
ck I2 "imac 的 Linear 状态对齐还在，和 base 逐字一样" 'block $N-imac.txt imac-linear-sync | grep -q "ops · 12 Linear 状态对齐 iMac" && [ "$(block $N-imac.txt imac-linear-sync)" = "$(block $B-imac.txt imac-linear-sync)" ]'
# drop "# <key>" and the lines after it up to and including its command
skip(){ awk -v k="# $2" '$0 == k || index($0, k " ") == 1 {s = 1} !s {print} s && /^orca automations/ {s = 0}' "$1"; }
ck I3 "imac 只少了 vllm 那一条：9 条命令，其余行和 base 一样" 'head -1 $N-imac.txt | grep -q ": 9 command(s), dry-run" && [ "$(skip $B-imac.txt imac-vllm-upstream | grep -v "^# register.sh")" = "$(grep -v "^# register.sh" $N-imac.txt)" ]'
ck X1 "box 没有 edit 349967f6" '! grep -q "edit 349967f6" $N-box.txt'
ck X2 "box 末尾 later 清单没有 349967f6，bc9ee42b 还在" '! sed -n "/^# later/,\$p" $N-box.txt | grep -q 349967f6 && sed -n "/^# later/,\$p" $N-box.txt | grep -q "edit bc9ee42b --disabled"'
ck X3 "box 只少了 349967f6：12 条命令（4 create + 8 edit），其余行和 base 一样" 'head -1 $N-box.txt | grep -q ": 12 command(s), dry-run" && [ "$(skip $B-box.txt "edit 349967f6" | grep -v -e "^# register.sh" -e "edit 349967f6 --disabled")" = "$(grep -v "^# register.sh" $N-box.txt)" ]'
ck M1 "mba 输出和 base 完全一样" '[ ! -s $T/mba.diff ]'
ck C1 "每条 create 都带 --disabled 和 --missed-run-grace-minutes 120" 'for m in imac box mba; do grep "^orca automations create" $N-$m.txt > $T/creates-$m; [ -s $T/creates-$m ] || exit 1; ! grep -v -e "--disabled" $T/creates-$m | grep -q . || exit 1; ! grep -v -e "--missed-run-grace-minutes 120" $T/creates-$m | grep -q . || exit 1; done'
ck C2 "三台合计 22 条 create（MBA 9、iMac 9、box 4）" '[ $(cat $T/creates-imac $T/creates-box $T/creates-mba | wc -l) -eq 22 ] && [ $(wc -l < $T/creates-mba) -eq 9 ] && [ $(wc -l < $T/creates-imac) -eq 9 ] && [ $(wc -l < $T/creates-box) -eq 4 ]'
echo "artifacts: $T"
exit $bad
