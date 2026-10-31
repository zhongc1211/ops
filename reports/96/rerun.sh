#!/bin/bash
# PR #96 的 E2E 和演练：在有 Java 17 和 tla2tools.jar 的机器（box）上跑。约定见 docs/rerun-convention.md。
# E2E：全量 wake/tla/check.sh（真跑 TLC），每个检查一行 results.tsv，名字 e2e_<检查>。
# 演练：仓库外的 git archive 副本里构造输入，名字 drill_<说明>：陈旧哈希、缺文件、格式不对、改被建模脚本、
#       还原后 check.sh w0 h0、旧 check.sh 回退、手工改坏模型。
# 产物：${RERUN_OUT:-$HOME/.orca-state/e2e/pr96-<head 前 12 位>}/results.tsv、tlc/（TLC 原文和 summary.tsv）、drill/（演练输出）。
# 退出码：0 全 PASS；1 有 FAIL；2 环境不满足（没有 Java，或 check.sh 报资源不够），不算通过；3 用例数 0。
set -u

PR_NUMBER=96
BASE_SHA=e2252d21e10c0787058c7eebdb34b175fc11ced5   # 这个 PR 的 base，旧 check.sh 从这里取

if [ -n "${RERUN_OUT:-}" ]; then
  case "$RERUN_OUT" in /*) ;; *) RERUN_OUT="$PWD/$RERUN_OUT";; esac
fi
ROOT=$(CDPATH= cd "$(dirname "$0")" && git rev-parse --show-toplevel 2>/dev/null) || ROOT=
[ -n "$ROOT" ] && CDPATH= cd "$ROOT" || { echo "rerun: 找不到仓库根" >&2; exit 2; }
HEAD_SHA=$(git rev-parse --verify -q HEAD) || { echo "rerun: 仓库还没有提交" >&2; exit 2; }

JAVA=${TLA_JAVA:-$HOME/.local/opt/jdk-17.0.12+7-jre/bin/java}
JAR=${TLA_JAR:-$HOME/.local/opt/tla/tla2tools.jar}
if [ ! -x "$JAVA" ] || [ ! -r "$JAR" ]; then
  echo "rerun: 缺 Java 或 tla2tools.jar，请在 box 上跑（这里不安装）" >&2
  echo "RERUN pr=${PR_NUMBER} head=${HEAD_SHA} pass=0 total=0"
  exit 2
fi

# 全量 check.sh 跑的是工作树，脏了结果就不是 HEAD 的
if [ -n "$(git status --porcelain)" ]; then
  echo "rerun: 工作树不干净，结果对不上 HEAD，请在 HEAD 的干净克隆里跑" >&2
  echo "RERUN pr=${PR_NUMBER} head=${HEAD_SHA} pass=0 total=0"
  exit 2
fi

OUT=${RERUN_OUT:-$HOME/.orca-state/e2e/pr${PR_NUMBER}-$(printf %.12s "$HEAD_SHA")}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rerun-pr${PR_NUMBER}.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT/drill" && printf 'case\tstatus\tdetail\n' > "$OUT/results.tsv" || exit 2
rm -rf "$OUT/tlc"
PASS=0; TOTAL=0

_row(){
  printf '%s\t%s\t%s\n' "$(printf '%s' "$1" | tr '\t\n' '  ')" "$2" "$(printf '%s' "$3" | tr '\t\n' '  ')" >> "$OUT/results.tsv"
  echo "$2 $1${3:+ — $3}"
}
case_pass(){ _row "$1" PASS "${2:-}"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
case_fail(){ _row "$1" FAIL "${2:-}"; TOTAL=$((TOTAL + 1)); }

# check.sh 退出 2 是环境或资源问题，如实退出 2，不记 PASS 也不记 FAIL；$1 退出码 $2 日志
env_bail(){
  [ "$1" = 2 ] || return 0
  echo "rerun: check.sh 退出 2（环境或资源问题），不算通过，见 $2" >&2
  echo "RERUN pr=${PR_NUMBER} head=${HEAD_SHA} pass=${PASS} total=${TOTAL}"
  exit 2
}

# 一份干净的副本；$1 = 目录名
copy_tree(){ mkdir -p "$WORK/$1" && git archive HEAD | tar -x -C "$WORK/$1"; }

# ---- E2E：全量 check.sh ----
wake/tla/check.sh --out "$OUT/tlc" > "$OUT/check-run.txt" 2>&1
check_rc=$?
echo "rc=$check_rc" >> "$OUT/check-run.txt"
env_bail "$check_rc" "$OUT/check-run.txt"
want=$(grep -cE '^  "[wlh][0-9]' wake/tla/check.sh)
have=$(($(wc -l < "$OUT/tlc/summary.tsv" 2>/dev/null || echo 1) - 1))
if [ "$check_rc" = 0 ] && [ "$have" = "$want" ]; then
  case_pass e2e_check_sh "退出码 0，${have}/${want} 个检查"
else
  case_fail e2e_check_sh "退出码 ${check_rc}，${have}/${want} 个检查"
fi
# 每个检查：summary 说一致，TLC 原文里也要有对应的那句
while IFS=$'\t' read -r name mod expect result match secs states note; do
  [ "$name" = name ] && continue
  raw="$OUT/tlc/$name.out"
  if [ "$expect" = pass ]; then
    line='Model checking completed. No error has been found.'
    grep -qF "$line" "$raw" 2>/dev/null; seen=$?
  else
    line=$(grep -m1 -E 'is violated|Temporal properties were violated' "$raw" 2>/dev/null)
    [ -n "$line" ]; seen=$?
  fi
  if [ "$match" = ok ] && [ "$seen" = 0 ]; then
    case_pass "e2e_$name" "期望 ${expect}，结果 ${result}，${states} 状态，${secs} 秒"
  else
    case_fail "e2e_$name" "期望 ${expect}，结果 ${result}，TLC 原文 $([ "$seen" = 0 ] && echo 有 || echo 没有)对应的行"
  fi
done < "$OUT/tlc/summary.tsv"

# ---- 演练：哈希不符一律失败，不跑 TLC ----
# $1 用例名 $2 副本目录；期望退出 1、有 FAIL、没有 .out；$3（可选）输出里要出现的文件名
expect_stale(){
  local d="$WORK/$2" out="$WORK/$2-out" log="$OUT/drill/$1.txt" rc
  "$d/wake/tla/check.sh" --out "$out" > "$log" 2>&1
  rc=$?
  echo "rc=$rc" >> "$log"
  env_bail "$rc" "$log"
  if [ "$rc" = 1 ] && grep -q FAIL "$log" && [ -z "$(ls "$out"/*.out 2>/dev/null)" ] && \
     ! grep -q '^commit ' "$log" && { [ -z "${3:-}" ] || grep -q "$3" "$log"; }; then
    case_pass "drill_$1" "退出码 1，有 FAIL，没有 TLC 输出"
  else
    case_fail "drill_$1" "退出码 ${rc}，见 $log"
  fi
}

copy_tree stale
first=$(head -c 1 "$WORK/stale/wake/tla/SOURCES.sha256")
case "$first" in 0) flip=1;; *) flip=0;; esac
sed "1s/^./$flip/" "$ROOT/wake/tla/SOURCES.sha256" > "$WORK/stale/wake/tla/SOURCES.sha256"
expect_stale stale_hash stale "$(sed -n '1s/^[0-9a-f]*  //p' "$ROOT/wake/tla/SOURCES.sha256")"

copy_tree script
printf '\n' >> "$WORK/script/scripts/heartbeat-watch.sh"
expect_stale script_changed script scripts/heartbeat-watch.sh

copy_tree missing
rm "$WORK/missing/wake/bin/agent-stop"
expect_stale file_missing missing wake/bin/agent-stop

copy_tree malformed
echo 'not a checksum line' >> "$WORK/malformed/wake/tla/SOURCES.sha256"
expect_stale sources_malformed malformed

copy_tree nosources
rm "$WORK/nosources/wake/tla/SOURCES.sha256"
expect_stale sources_missing nosources

copy_tree noline
sed -i.bak '/scripts\/agent-probe$/d' "$WORK/noline/wake/tla/SOURCES.sha256"
expect_stale sources_line_removed noline scripts/agent-probe

# 还原后 check.sh w0 h0 回到 0
cp "$ROOT/wake/tla/SOURCES.sha256" "$WORK/stale/wake/tla/SOURCES.sha256"
"$WORK/stale/wake/tla/check.sh" --out "$WORK/restored-out" w0 h0 > "$OUT/drill/restored.txt" 2>&1
rc=$?; echo "rc=$rc" >> "$OUT/drill/restored.txt"
env_bail "$rc" "$OUT/drill/restored.txt"
if [ "$rc" = 0 ] && [ -s "$WORK/restored-out/h01_p3_dead.out" ]; then case_pass drill_restored_w0_h0 "还原后退出码 0，跑了 TLC"
else case_fail drill_restored_w0_h0 "退出码 ${rc}，见 $OUT/drill/restored.txt"; fi

# 回退：旧 check.sh 放回去、哈希还是错的，只警告，退出码 0
copy_tree old
sed "1s/^./$flip/" "$ROOT/wake/tla/SOURCES.sha256" > "$WORK/old/wake/tla/SOURCES.sha256"
git show "$BASE_SHA:wake/tla/check.sh" > "$WORK/old/wake/tla/check.sh"
"$WORK/old/wake/tla/check.sh" --out "$WORK/old-out" w01 > "$OUT/drill/old-check-sh.txt" 2>&1
rc=$?; echo "rc=$rc" >> "$OUT/drill/old-check-sh.txt"
env_bail "$rc" "$OUT/drill/old-check-sh.txt"
if [ "$rc" = 0 ] && grep -q '注意：模型对应的代码' "$OUT/drill/old-check-sh.txt" && [ -s "$WORK/old-out/w01_p2_nr.out" ]; then
  case_pass drill_old_check_sh_warns "旧 check.sh 只警告、跑了 TLC、退出码 0：新演练挂得出来"
else
  case_fail drill_old_check_sh_warns "退出码 ${rc}，见 $OUT/drill/old-check-sh.txt"
fi

# 手工改坏模型：期望 pass 的检查要变成 violated，check.sh 退出 1
# $1 用例名 $2 文件 $3 sed 表达式 $4 检查名
expect_broken(){
  local d="$WORK/b-$1" out="$WORK/b-$1-out" log="$OUT/drill/$1.txt" rc
  copy_tree "b-$1"
  sed -i.bak "$3" "$d/wake/tla/$2" && rm -f "$d/wake/tla/$2.bak"
  if cmp -s "$d/wake/tla/$2" "$ROOT/wake/tla/$2"; then case_fail "drill_$1" "sed 没改到东西"; return; fi
  "$d/wake/tla/check.sh" --out "$out" "$4" > "$log" 2>&1
  rc=$?; echo "rc=$rc" >> "$log"
  env_bail "$rc" "$log"
  cp "$out/$4.out" "$OUT/drill/$1.out" 2>/dev/null
  if [ "$rc" = 1 ] && grep -qE 'Invariant P[0-9A-Z_]* is violated|Temporal properties were violated' "$out/$4.out" 2>/dev/null; then
    case_pass "drill_$1" "$4 变成 violated，check.sh 退出 1"
  else
    case_fail "drill_$1" "退出码 ${rc}，见 $log"
  fi
}
expect_broken break_scan_slow Heartbeat.tla 's/^nSlow == .*/nSlow == slowAlerted/' h07_p3_cut
expect_broken break_pre_reject Launch.tla 's/\\\/ st = "rejected_pre" \/\\ Mutant # "pre_silent"/\\\/ st = "rejected_pre" \/\\ FALSE/' l01_p6

rm -rf "$WORK"; trap - EXIT
if [ "$TOTAL" -eq 0 ]; then rc=3; elif [ "$PASS" -eq "$TOTAL" ]; then rc=0; else rc=1; fi
echo "产物: $OUT/results.tsv"
echo "RERUN pr=${PR_NUMBER} head=${HEAD_SHA} pass=${PASS} total=${TOTAL}"
exit "$rc"
