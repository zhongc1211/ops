#!/bin/bash
# reports/<PR 号>/rerun.sh 的模板。约定见 docs/rerun-convention.md。
# 起步：mkdir -p reports/<N> && cp scripts/rerun-template.sh reports/<N>/rerun.sh，
# 改下面的 PR_NUMBER，在「在这里写你的 E2E 步骤」段落里写用例。
# 从哪个目录启动都行；产物写到仓库外：${RERUN_OUT:-$HOME/.orca-state/e2e/pr<N>-<head 前 12 位>}/results.tsv。
# 退出码：0 = 全部 PASS 且用例数 > 0；1 = 有 FAIL；3 = 用例数 0；2 = PR_NUMBER 没改、找不到仓库根或仓库还没有提交（不写产物）。
# 最后一行：RERUN pr=<N> head=<40 位 sha> pass=<p> total=<t>
# bash 3.2 兼容（macOS /bin/bash）。
set -u

PR_NUMBER=__PR_NUMBER__

case "$PR_NUMBER" in ''|*[!0-9]*) echo "rerun: 先把 PR_NUMBER 改成 PR 号" >&2; exit 2;; esac
if [ -n "${RERUN_OUT:-}" ]; then
  case "$RERUN_OUT" in /*) ;; *) RERUN_OUT="$PWD/$RERUN_OUT";; esac   # 相对路径按启动目录算，不落进仓库
fi
ROOT=$(CDPATH= cd "$(dirname "$0")" && git rev-parse --show-toplevel 2>/dev/null) || ROOT=
[ -n "$ROOT" ] && CDPATH= cd "$ROOT" || { echo "rerun: 找不到仓库根" >&2; exit 2; }
HEAD_SHA=$(git rev-parse --verify -q HEAD) || { echo "rerun: 仓库还没有提交" >&2; exit 2; }
OUT=${RERUN_OUT:-$HOME/.orca-state/e2e/pr${PR_NUMBER}-$(printf %.12s "$HEAD_SHA")}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rerun-pr${PR_NUMBER}.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT" && printf 'case\tstatus\tdetail\n' > "$OUT/results.tsv" || exit 2
PASS=0; TOTAL=0

_row(){   # 名字和说明里的 TAB、换行换成空格，保证一行三列
  printf '%s\t%s\t%s\n' "$(printf '%s' "$1" | tr '\t\n' '  ')" "$2" "$(printf '%s' "$3" | tr '\t\n' '  ')" >> "$OUT/results.tsv"
  echo "$2 $1${3:+ — $3}"
}
case_pass(){ _row "$1" PASS "${2:-}"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
case_fail(){ _row "$1" FAIL "${2:-}"; TOTAL=$((TOTAL + 1)); }

# ==== 在这里写你的 E2E 步骤 ↓ ====
# 每个用例跑真实命令、看结果，再调 case_pass <名字> [说明] 或 case_fail <名字> [说明]。
# 当前目录是仓库根。临时文件放 "$WORK"（收尾自动删）；要沙箱 HOME 就写 HOME="$WORK/home" <命令>，不要 export。
# 不要在这里 exit：命令失败就记 case_fail，往下走到收尾。
if /bin/bash -n scripts/rerun-template.sh 2>"$WORK/bash-n.err"; then
  case_pass example_bash_n "scripts/rerun-template.sh 语法检查通过"
else
  case_fail example_bash_n "$(head -n 1 "$WORK/bash-n.err")"
fi
# ==== 在这里写你的 E2E 步骤 ↑ ====

rm -rf "$WORK"; trap - EXIT
if [ "$TOTAL" -eq 0 ]; then rc=3; elif [ "$PASS" -eq "$TOTAL" ]; then rc=0; else rc=1; fi
echo "产物: $OUT/results.tsv"
echo "RERUN pr=${PR_NUMBER} head=${HEAD_SHA} pass=${PASS} total=${TOTAL}"
exit "$rc"
