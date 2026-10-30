#!/bin/bash
# reports/97/rerun.sh：PR 97 的 E2E 和演练。约定见 docs/rerun-convention.md。
#   e2e_*     对本次 checkout 跑全量 verify.sh run（真脚本 + verify-ops 的沙箱，替身清单在 summary.json 的 stand_ins）
#   drill_*   演练：构造输入，改坏的东西都在 $WORK 的副本里
#   revert_*  回退测试：放回 main（#93 之后）的 verify.sh 或去掉本 PR 的改动，演练里的断言必须挂
# 产物：${RERUN_OUT:-$HOME/.orca-state/e2e/pr97-<head 前 12 位>}/（results.tsv、e2e.log、drills/、revert/）
# 退出码：0 全部 PASS；1 有 FAIL；3 用例数 0。bash 3.2 兼容。
set -u

PR_NUMBER=97
BASE_SHA=e2252d21e10c0787058c7eebdb34b175fc11ced5   # 本 PR 的 base

if [ -n "${RERUN_OUT:-}" ]; then
  case "$RERUN_OUT" in /*) ;; *) RERUN_OUT="$PWD/$RERUN_OUT";; esac
fi
ROOT=$(CDPATH= cd "$(dirname "$0")" && git rev-parse --show-toplevel 2>/dev/null) || ROOT=
[ -n "$ROOT" ] && CDPATH= cd "$ROOT" || { echo "rerun: 找不到仓库根" >&2; exit 2; }
HEAD_SHA=$(git rev-parse --verify -q HEAD) || { echo "rerun: 仓库还没有提交" >&2; exit 2; }
OUT=${RERUN_OUT:-$HOME/.orca-state/e2e/pr${PR_NUMBER}-$(printf %.12s "$HEAD_SHA")}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rerun-pr${PR_NUMBER}.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT/drills" "$OUT/revert" && printf 'case\tstatus\tdetail\n' > "$OUT/results.tsv" || exit 2
PASS=0; TOTAL=0

_row(){
  printf '%s\t%s\t%s\n' "$(printf '%s' "$1" | tr '\t\n' '  ')" "$2" "$(printf '%s' "$3" | tr '\t\n' '  ')" >> "$OUT/results.tsv"
  echo "$2 $1${3:+ — $3}"
}
case_pass(){ _row "$1" PASS "${2:-}"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
case_fail(){ _row "$1" FAIL "${2:-}"; TOTAL=$((TOTAL + 1)); }

V=.claude/skills/verify-ops/verify.sh
VO=.claude/skills/verify-ops/helpers/vo.py
PIN=bootstrap/claude-plugins/pin-claude-plugins.sh
MARKER=$(sed -n "s/^MARKER_PREFIX='\([^']*\)'.*/\1/p" wake/bin/orca-agent-launch)
mkdir -p "$WORK/empty"

mask(){ VO_REAL_HOME="$HOME" VO_MASK_WORDS="$(hostname):$(hostname -s):$(id -un)" python3 -I "$VO" mask "$1" "$2"; }
# verify <产物路径> <环境赋值...> -- <verify.sh 路径> <run 的参数...>：在空目录里跑，结果写 $DIR，退出码放 $RC
verify(){
  local log=$1; shift
  local envs=() script
  while [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift; script=$1; shift
  DIR=$(mktemp -d "$WORK/arch.XXXXXX")
  ( cd "$WORK/empty" && env ${envs[@]+"${envs[@]}"} VERIFY_OPS_ARCHIVE="$DIR" /bin/bash "$script" run "$@" ) > "$WORK/verify.out" 2>&1
  RC=$?
  mask "$WORK/verify.out" "$log"
}
# cases <状态> <用例名片段>：本次运行里这个状态、名字含这个片段的条数
cases(){ awk -F'\t' -v s="$1" -v n="$2" '$2 == s && index($3, n) {c++} END {print c + 0}' "$DIR"/*/cases.tsv; }
detail(){ awk -F'\t' -v n="$1" 'index($3, n) {print $4; exit}' "$DIR"/*/cases.tsv; }
last(){ tail -1 "$1"; }
# want <用例> <实际> <期望> <说明>
want(){ if [ "$2" = "$3" ]; then case_pass "$1" "$4"; else case_fail "$1" "得到 ${2}，期望 ${3}；$4"; fi; }
fake_home(){ mkdir -p "$1"; echo "$1"; }
fake_pins(){  # $1=HOME：两个插件仓库都在，但没有钉的 commit
  local n
  for n in cursor-plugins compound-engineering-plugin; do
    git init -q "$1/.claude/pinned-marketplaces/$n"
    git -C "$1/.claude/pinned-marketplaces/$n" -c user.name=drill -c user.email=drill@invalid commit -q --allow-empty -m drill
  done
}
copy_git(){ git clone -q --local "$ROOT" "$1" 2>/dev/null; }   # drift-checks 要被测目录是 git 仓库
copy_tar(){ mkdir -p "$1" && git archive HEAD | tar -x -C "$1"; }

# ---------- E2E：全量 ----------
verify "$OUT/e2e.log" -- "$ROOT/$V"
python3 -I - "$DIR"/*/summary.json "$HEAD_SHA" > "$WORK/e2e.tsv" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for f in d["features"]:
    print("feature\t%s\t%d\t%d\t%d\t%d" % (f["name"], f["cases"], f["pass"], f["fail"], f["skipped"]))
ok = d["status"] == "PASS" and d["sha"] == sys.argv[2] and not d["dirty"] and d["sut_kind"] == "checkout" and d["guard_ok"]
print("total\t%s\t%d\t%d\t%d\t%d\t%s\t%s\t%s" % ("ok" if ok else "bad", d["cases_total"], d["cases_pass"], d["cases_fail"], d["cases_skipped"],
      d["run_dir"], d["status"], "；".join("%s/%s" % (c["feature"], c["name"]) for c in d["cases"] if c["status"] == "skipped")))
PY
while IFS="$(printf '\t')" read -r kind a b c d e f g h; do
  if [ "$kind" = feature ]; then
    [ "$b" -gt "$e" ] || continue   # 全是 skipped 的 feature 没跑过，不记 PASS，列在总计的 detail 里
    if [ "$d" = 0 ]; then case_pass "e2e_$a" "用例 ${b}：通过 ${c}，失败 ${d}，skipped ${e}"
    else case_fail "e2e_$a" "用例 ${b}：通过 ${c}，失败 ${d}，skipped ${e}"; fi
  else
    cp -R "$DIR/$f" "$OUT/verify-run" 2>/dev/null
    msg="总数 ${b}，通过 ${c}，失败 ${d}，skipped ${e}；verify.sh 退出码 ${RC}；运行目录 ${f}，拷在 verify-run/；skipped：${h:-无}"
    if [ "$a" = ok ] && [ "$RC" = 0 ]; then case_pass e2e_total "$msg"; else case_fail e2e_total "$msg"; fi
  fi
done < "$WORK/e2e.tsv"
grep -q '^total' "$WORK/e2e.tsv" || case_fail e2e_total "summary.json 读不出来，见 e2e.log"

# ---------- 演练：DC4 的 SKIP 口径 ----------
H=$(fake_home "$WORK/h-none")
verify "$OUT/drills/dc4-no-repos.log" HOME="$H" -- "$ROOT/$V" drift-checks
want drill_dc4_no_repos "$RC/$(cases skipped 'pin-claude-plugins --check')/$(cases pass pin-claude-plugins)/$(cases fail pin-claude-plugins)/$(last "$OUT/drills/dc4-no-repos.log")" "0/1/0/0/VERIFY-OPS PASS（skipped 1）" \
  "演练：沙箱造没有 pinned-marketplaces → DC4 记 SKIP，整体退出码 0。原因：$(detail 'pin-claude-plugins --check')"

H=$(fake_home "$WORK/h-nocommit"); fake_pins "$H"
verify "$OUT/drills/dc4-no-commit.log" HOME="$H" -- "$ROOT/$V" drift-checks
want drill_dc4_no_commit "$RC/$(cases skipped 'pin-claude-plugins --check')/$(cases fail pin-claude-plugins)" "0/1/0" \
  "演练：有插件仓库但缺钉的 commit → SKIP。原因：$(detail 'pin-claude-plugins --check')"

H=$(fake_home "$WORK/h-nopin"); copy_git "$WORK/m-nopin"
sed -i.orig 's/^PSTACK_SHA=/PSTACK_RENAMED=/' "$WORK/m-nopin/$PIN"
verify "$OUT/drills/dc4-pin-unreadable.log" HOME="$H" VERIFY_OPS_SUT="$WORK/m-nopin" -- "$ROOT/$V" drift-checks
want drill_dc4_pin_unreadable "$RC/$(cases fail '读不到钉的 commit')/$(cases skipped pin-claude-plugins)" "1/1/0" \
  "演练：副本里钉版本变量读不到 → FAIL，不当缺前置"

copy_git "$WORK/m-drift"
sed -i.orig '/^DENY=\[/s/"pstack:tdd",//' "$WORK/m-drift/$PIN"
verify "$OUT/drills/dc4-real-drift.log" VERIFY_OPS_SUT="$WORK/m-drift" -- "$ROOT/$V" drift-checks
want drill_dc4_precheck_ok_but_drift "$RC/$(cases fail 'pin-claude-plugins --check 干净')/$(cases skipped pin-claude-plugins)" "1/1/0" \
  "演练：本机预检通过、副本的安装脚本少写一条 deny → FAIL，不吞。要本机有两个插件仓库且含钉的 commit"

# ---------- 演练：#93 的启动前检查和全局 AGENTS ----------
verify "$OUT/drills/gate-other-cwd.log" -- "$ROOT/$V" agent-launch-gate
want drill_gate_any_cwd "$RC/$(cases pass '合法参数：进入 notify-run --tty')" "0/1" "演练：从空目录跑 agent-launch-gate 全过（main 上这样跑 7 条失败）"

copy_tar "$WORK/m-nomarker"
sed -i.orig "/$MARKER/d" "$WORK/m-nomarker/AGENTS.md"
verify "$OUT/drills/gate-sut-no-marker.log" VERIFY_OPS_SUT="$WORK/m-nomarker" -- "$ROOT/$V" agent-launch-gate
want drill_gate_sut_no_marker "$RC/$(cases fail '合法参数：进入 notify-run --tty')" "1/1" \
  "演练：被测 AGENTS.md 没有标记句 → 沙箱全局 AGENTS 也没有，门拒绝，合法用例挂"

copy_tar "$WORK/m-nogate"
sed -i.orig '/^\[ "\$lc_rc" -eq 0 \] || die/d' "$WORK/m-nogate/wake/bin/orca-agent-launch"
verify "$OUT/drills/gate-check-removed.log" VERIFY_OPS_SUT="$WORK/m-nogate" -- "$ROOT/$V" agent-launch-gate
want drill_gate_check_removed "$RC/$(cases fail '指令链文件没有标记句：退出码 2')/$(cases fail '指令链一个文件都没有：退出码 2')" "1/1/1" \
  "演练：副本里去掉 #93 的拒绝 → 新加的拒绝用例挂"

copy_git "$WORK/m-peers"
sed -i.orig '/全局 AGENTS 不一致：/s/; drift=1//' "$WORK/m-peers/wake/install.sh"
verify "$OUT/drills/install-peer-drift-ignored.log" VERIFY_OPS_SUT="$WORK/m-peers" -- "$ROOT/$V" drift-checks
want drill_install_peer_drift_ignored "$RC/$(cases fail '对端全局 AGENTS 不一致')" "1/1" \
  "演练：副本里不一致不再判 drift → 新加的对端用例挂"

# 去掉一台不是本机的对端（本机本来就不探测，去掉它什么也不变），台数断言才有东西可抓
case "$(hostname | cut -d. -f1 | tr '[:upper:]' '[:lower:]')" in box|grok-bot-vm-*) PEERS="imac box" ;; *) PEERS="imac mba" ;; esac
copy_git "$WORK/m-onepeer"
sed -i.orig "s/WAKE_CHECK_PEERS-imac mba box/WAKE_CHECK_PEERS-$PEERS/" "$WORK/m-onepeer/wake/install.sh"
verify "$OUT/drills/install-peer-dropped.log" VERIFY_OPS_SUT="$WORK/m-onepeer" -- "$ROOT/$V" drift-checks
want drill_install_peer_dropped "$RC/$(cases fail 'install.sh --check 干净')/$(cases fail '对端全局 AGENTS 不一致')/$(last "$OUT/drills/install-peer-dropped.log")" "1/1/0/VERIFY-OPS FAIL（skipped 0）" \
  "演练：副本的默认对端少一台 → 只有台数断言挂；FAIL 的最后一行带 skipped 数"

# ---------- 演练：最后一行的 skipped 数 ----------
PF=$WORK/precheck-flip; mkdir -p "$PF"; git archive HEAD .claude/skills/verify-ops | tar -x -C "$PF"
sed -i.orig 's/elif ! git -C "\$src" cat-file/elif git -C "$src" cat-file/' "$PF/$V"
verify "$OUT/drills/dc4-precheck-flipped.log" VERIFY_OPS_SUT="$ROOT" -- "$PF/$V" drift-checks
want drill_last_line_skipped "$RC/$(last "$OUT/drills/dc4-precheck-flipped.log")" "0/VERIFY-OPS PASS（skipped 1）" \
  "演练：副本 verify.sh 的 DC4 预检取反 → 退出码仍是 0，最后一行看得出 skipped 1"

verify "$OUT/drills/no-such-feature.log" -- "$ROOT/$V" no-such-feature
want drill_last_line_empty "$RC/$(last "$OUT/drills/no-such-feature.log")" "3/VERIFY-OPS EMPTY（0 个用例，skipped 0）" \
  "演练：feature 名写错 → 退出码 3，最后一行带 skipped 数"

# ---------- 回退测试 ----------
OLD=$WORK/old; mkdir -p "$OLD"
BASE_GIT=$ROOT
if ! git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then   # 只取了 PR head 的临时仓库里没有 base，拉到 $WORK，不进仓库
  BASE_GIT=$WORK/base.git
  git init -q --bare "$BASE_GIT" && git -C "$BASE_GIT" fetch -q --depth 1 https://github.com/zhongc1211/ops.git "$BASE_SHA"
fi
git -C "$BASE_GIT" archive "$BASE_SHA" .claude/skills/verify-ops | tar -x -C "$OLD"
OV=$OLD/$V
H=$(fake_home "$WORK/h-old1")
verify "$OUT/revert/old-dc4-no-repos.log" HOME="$H" WAKE_CHECK_PEERS= VERIFY_OPS_SUT="$ROOT" -- "$OV" drift-checks
want revert_dc4_no_repos "$RC/$(cases fail 'pin-claude-plugins：缺前置条件')/$(cases skipped pin-claude-plugins)" "1/1/0" \
  "回退：放回 main 的 verify.sh，没有 pinned-marketplaces 时报失败，drill_dc4_no_repos 的断言会挂"

H=$(fake_home "$WORK/h-old2"); fake_pins "$H"
verify "$OUT/revert/old-dc4-no-commit.log" HOME="$H" WAKE_CHECK_PEERS= VERIFY_OPS_SUT="$ROOT" -- "$OV" drift-checks
want revert_dc4_no_commit "$RC/$(cases skipped pin-claude-plugins)" "1/0" \
  "回退：放回 main 的 verify.sh，缺钉的 commit 时没有 SKIP，drill_dc4_no_commit 的断言会挂"

verify "$OUT/revert/old-gate-other-cwd.log" VERIFY_OPS_SUT="$ROOT" -- "$OV" agent-launch-gate
want revert_gate_other_cwd "$RC/$(cases fail '合法参数：进入 notify-run --tty')" "1/1" \
  "回退：放回 main 的 verify.sh，从空目录跑合法用例被拒，drill_gate_any_cwd 的断言会挂"

verify "$OUT/revert/old-install-check.log" WAKE_CHECK_PEERS= VERIFY_OPS_SUT="$ROOT" -- "$OV" drift-checks
want revert_install_check_clean "$RC/$(cases fail 'install.sh --check 干净：退出码 0')" "1/1" \
  "回退：放回 main 的 verify.sh，install.sh --check 干净用例挂（只看本机，不连对端）"

NF=$WORK/nofixture; mkdir -p "$NF"; git archive HEAD .claude/skills/verify-ops | tar -x -C "$NF"
sed -i.orig '/cp "\$SUT\/AGENTS.md" "\$h\/.pi\/agent\/AGENTS.md"/d' "$NF/$V"
verify "$OUT/revert/no-agents-fixture.log" VERIFY_OPS_SUT="$ROOT" -- "$NF/$V" agent-launch-gate drift-checks
want revert_no_agents_fixture "$RC/$(cases fail '放行的 3 次标记句都在沙箱')/$(cases fail 'install.sh --check 干净')" "1/1/1" \
  "回退：去掉沙箱全局 AGENTS，放行方向和 install.sh --check 干净用例都挂"

rm -rf "$WORK"; trap - EXIT
if [ "$TOTAL" -eq 0 ]; then rc=3; elif [ "$PASS" -eq "$TOTAL" ]; then rc=0; else rc=1; fi
echo "产物: $OUT/results.tsv"
echo "RERUN pr=${PR_NUMBER} head=${HEAD_SHA} pass=${PASS} total=${TOTAL}"
exit "$rc"
