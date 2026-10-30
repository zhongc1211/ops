#!/bin/bash
# PR #92（rerun.sh 约定：模板和说明）的复跑脚本，从 scripts/rerun-template.sh 复制改出来。
# 用例全是演练：把模板复制进沙箱仓库、填入构造好的用例，用 /bin/bash 跑，核对退出码、最后一行、results.tsv、
# 启动目录、产物位置和清理。约定见 docs/rerun-convention.md。
# 退出码：0 = 全部 PASS 且用例数 > 0；1 = 有 FAIL；3 = 用例数 0；2 = PR_NUMBER 没改或找不到仓库根。
# 最后一行：RERUN pr=<N> head=<40 位 sha> pass=<p> total=<t>
# bash 3.2 兼容（macOS /bin/bash）。
set -u

PR_NUMBER=92

case "$PR_NUMBER" in ''|*[!0-9]*) echo "rerun: 先把 PR_NUMBER 改成 PR 号" >&2; exit 2;; esac
if [ -n "${RERUN_OUT:-}" ]; then
  case "$RERUN_OUT" in /*) ;; *) RERUN_OUT="$PWD/$RERUN_OUT";; esac   # 相对路径按启动目录算，不落进仓库
fi
CDPATH= cd "$(dirname "$0")" && CDPATH= cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "rerun: 找不到仓库根" >&2; exit 2; }
HEAD_SHA=$(git rev-parse HEAD)
OUT=${RERUN_OUT:-$HOME/.orca-state/e2e/pr${PR_NUMBER}-$(printf %.12s "$HEAD_SHA")}
mkdir -p "$OUT" || exit 2
printf 'case\tstatus\tdetail\n' > "$OUT/results.tsv"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rerun-pr${PR_NUMBER}.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; TOTAL=0

_row(){   # 名字和说明里的 TAB、换行换成空格，保证一行三列
  printf '%s\t%s\t%s\n' "$(printf '%s' "$1" | tr '\t\n' '  ')" "$2" "$(printf '%s' "$3" | tr '\t\n' '  ')" >> "$OUT/results.tsv"
  echo "$2 $1${3:+ — $3}"
}
case_pass(){ _row "$1" PASS "${2:-}"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
case_fail(){ _row "$1" FAIL "${2:-}"; TOTAL=$((TOTAL + 1)); }

# ==== 在这里写你的 E2E 步骤 ↓ ====
# 本 PR 的用例全是演练（构造输入）：把模板复制进沙箱仓库、填入构造好的用例、用 /bin/bash 跑，看退出码、最后一行和 results.tsv。
# 被测的模板默认是 scripts/rerun-template.sh；RERUN_TEMPLATE 只在留失败证据时指向别的版本。
TPL=${RERUN_TEMPLATE:-scripts/rerun-template.sh}
case "$TPL" in /*) ;; *) TPL="$PWD/$TPL";; esac
REAL_REPORTS_BEFORE=$(git status --porcelain --untracked-files=all -- reports; git ls-files -s reports | git hash-object --stdin)

SB="$WORK/sb"; R="$SB/repo"; mkdir -p "$SB/home" "$SB/elsewhere" "$SB/tmp" "$SB/out" "$R"
G(){ HOME="$SB/home" git -C "$R" -c user.name=drill -c user.email=drill@example.invalid "$@"; }
G init -q
mkdir -p "$R/reports/9000"; printf '#!/bin/bash\necho old-report\n' > "$R/reports/9000/rerun.sh"
fill(){   # fill <PR 号> <步骤文件>：把模板复制成沙箱仓库里的 reports/<PR 号>/rerun.sh，换掉 PR_NUMBER 和步骤段落
  mkdir -p "$R/reports/$1"
  sed "s/^PR_NUMBER=__PR_NUMBER__\$/PR_NUMBER=$1/" "$TPL" | awk -v f="$2" '
    /^# ==== 在这里写你的 E2E 步骤 ↓/ { while ((getline l < f) > 0) print l; skip = 1; next }
    /^# ==== 在这里写你的 E2E 步骤 ↑/ { skip = 0; next }
    !skip' > "$R/reports/$1/rerun.sh"
  chmod 755 "$R/reports/$1/rerun.sh"
}
printf 'case_pass first "第一个"\ncase_pass second\n' > "$SB/s2pass"
printf 'false || case_fail broken "false 返回非 0"\n' > "$SB/s1fail"
: > "$SB/s0"
printf 'case_pass "a\tb" "x\ty\nz"\n' > "$SB/stab"
printf 'case_pass root "$(pwd -P)"\n' > "$SB/sroot"
fill 9001 "$SB/s2pass"; fill 9002 "$SB/s1fail"; fill 9003 "$SB/s0"; fill 9004 "$SB/stab"; fill 9005 "$SB/sroot"
mkdir -p "$R/reports/9009"; cp "$TPL" "$R/reports/9009/rerun.sh"   # 原样复制，PR_NUMBER 没改
G add -A && G commit -q -m drill || case_fail sandbox_repo "沙箱仓库提交失败"
RH=$(G rev-parse HEAD); RROOT=$(cd "$R" && pwd -P)
SB_REPORTS_BEFORE=$(G ls-files -s reports)

run(){   # run <PR 号> <启动目录> <RERUN_OUT，空 = 不设> [脚本路径]：结果在 ${rc}、${last}、$tsv
  local o=$3 p=${4:-$R/reports/$1/rerun.sh}
  if [ -n "$o" ]; then
    (cd "$2" && HOME="$SB/home" TMPDIR="$SB/tmp" RERUN_OUT="$o" /bin/bash "$p") > "$SB/log.$1" 2>&1
  else
    (cd "$2" && unset RERUN_OUT && HOME="$SB/home" TMPDIR="$SB/tmp" /bin/bash "$p") > "$SB/log.$1" 2>&1
  fi
  rc=$?; last=$(tail -n 1 "$SB/log.$1"); tsv=${o:-$SB/home/.orca-state/e2e/pr$1-${RH:0:12}}/results.tsv
}
want(){ [ "$last" = "RERUN pr=$1 head=$RH pass=$2 total=$3" ]; }
rows(){ [ -f "$tsv" ] && awk -F '\t' -v s="$1" 'NR > 1 && NF == 3 && $2 == s' "$tsv" | wc -l | tr -d ' ' || echo 0; }
header_ok(){ [ -f "$tsv" ] && [ "$(head -n 1 "$tsv")" = "$(printf 'case\tstatus\tdetail')" ]; }

if /bin/bash -n "$TPL" 2>"$SB/bash-n.err"; then case_pass bash_n_template "bash -n 通过"; else case_fail bash_n_template "$(head -n 1 "$SB/bash-n.err")"; fi
if LC_ALL=C grep -n '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$TPL" > "$SB/bare-var.txt"; then case_fail no_bare_var_before_cjk "$(head -n 1 "$SB/bare-var.txt")"; else case_pass no_bare_var_before_cjk "没有 \$变量 紧跟非 ASCII 字符（bash 3.2 会把它读进变量名）"; fi

run 9001 "$SB/elsewhere" "$SB/out/9001"
if [ "$rc" -eq 0 ]; then case_pass two_pass_exit "退出码 0"; else case_fail two_pass_exit "退出码 ${rc}，应为 0"; fi
if want 9001 2 2; then case_pass two_pass_lastline "$last"; else case_fail two_pass_lastline "最后一行：$last"; fi
if header_ok && [ "$(rows PASS)" = 2 ] && [ "$(wc -l < "$tsv" | tr -d ' ')" = 3 ]; then case_pass two_pass_tsv "表头 + 2 行 PASS"; else case_fail two_pass_tsv "results.tsv 不对：$(tr '\t\n' ' |' < "$tsv" 2>/dev/null)"; fi

run 9001 "$SB/elsewhere" "$SB/out/9001"
if [ "$(wc -l < "$tsv" | tr -d ' ')" = 3 ]; then case_pass rerun_same_out_no_stale "同目录跑第二次仍是 3 行"; else case_fail rerun_same_out_no_stale "第二次后 $(wc -l < "$tsv" | tr -d ' ') 行"; fi

run 9001 "$SB/elsewhere" ""
if [ "$rc" -eq 0 ] && header_ok && [ "$(rows PASS)" = 2 ]; then case_pass default_out_path "落在 \$HOME/.orca-state/e2e/pr9001-${RH:0:12}"; else case_fail default_out_path "rc=${rc}，默认目录下没有正确的 results.tsv：$(ls -R "$SB/home" 2>/dev/null | tr '\n' ' ')"; fi

run 9002 "$SB/elsewhere" "$SB/out/9002"
if [ "$rc" -eq 1 ]; then case_pass one_fail_exit "退出码 1"; else case_fail one_fail_exit "退出码 ${rc}，应为 1"; fi
if want 9002 0 1; then case_pass one_fail_lastline "$last"; else case_fail one_fail_lastline "最后一行：$last"; fi
if header_ok && [ "$(rows FAIL)" = 1 ]; then case_pass one_fail_tsv "表头 + 1 行 FAIL"; else case_fail one_fail_tsv "results.tsv 不对"; fi

run 9003 "$SB/elsewhere" "$SB/out/9003"
if [ "$rc" -eq 3 ]; then case_pass zero_cases_exit "退出码 3"; else case_fail zero_cases_exit "退出码 ${rc}，应为 3"; fi
if want 9003 0 0; then case_pass zero_cases_lastline "$last"; else case_fail zero_cases_lastline "最后一行：$last"; fi

run 9004 "$SB/elsewhere" "$SB/out/9004"
if [ "$rc" -eq 0 ] && [ -f "$tsv" ] && [ "$(wc -l < "$tsv" | tr -d ' ')" = 2 ] && [ "$(awk -F '\t' 'NR == 2 { print NF }' "$tsv")" = 3 ]; then
  case_pass tab_newline_sanitized "TAB 和换行被换成空格，仍是一行三列"
else
  case_fail tab_newline_sanitized "rc=${rc}，results.tsv：$(tr '\t\n' '>|' < "$tsv" 2>/dev/null)"
fi

run 9005 "$SB/elsewhere" "$SB/out/9005a"
if [ "$rc" -eq 0 ] && [ "$(awk -F '\t' 'NR == 2 { print $3 }' "$tsv")" = "$RROOT" ]; then case_pass other_cwd_root "从沙箱里别的目录启动，cd 到 $RROOT"; else case_fail other_cwd_root "rc=${rc}，当前目录：$(awk -F '\t' 'NR == 2 { print $3 }' "$tsv" 2>/dev/null)"; fi
run 9005 / "$SB/out/9005b"
if [ "$rc" -eq 0 ] && [ "$(awk -F '\t' 'NR == 2 { print $3 }' "$tsv")" = "$RROOT" ]; then case_pass run_from_slash "从 / 启动也 cd 到仓库根"; else case_fail run_from_slash "rc=${rc}，当前目录：$(awk -F '\t' 'NR == 2 { print $3 }' "$tsv" 2>/dev/null)"; fi
run 9005 "$R/reports" "$SB/out/9005c" 9005/rerun.sh
if [ "$rc" -eq 0 ] && [ "$(awk -F '\t' 'NR == 2 { print $3 }' "$tsv")" = "$RROOT" ]; then case_pass relative_path_from_subdir "在 reports/ 下用相对路径 9005/rerun.sh 启动也对"; else case_fail relative_path_from_subdir "rc=${rc}，当前目录：$(awk -F '\t' 'NR == 2 { print $3 }' "$tsv" 2>/dev/null)"; fi

run 9009 "$SB/elsewhere" ""
if [ "$rc" -eq 2 ] && [ ! -e "$SB/home/.orca-state/e2e/pr__PR_NUMBER__-${RH:0:12}" ]; then case_pass placeholder_refused "PR_NUMBER 没改：退出码 2，不写产物"; else case_fail placeholder_refused "rc=${rc}，$(ls "$SB/home/.orca-state/e2e" 2>/dev/null | tr '\n' ' ')"; fi

if [ -z "$(G status --porcelain --untracked-files=all)" ]; then case_pass repo_tree_clean "跑完沙箱仓库工作树干净"; else case_fail repo_tree_clean "$(G status --porcelain --untracked-files=all | head -n 3 | tr '\n' ' ')"; fi
REAL_REPORTS_AFTER=$(git status --porcelain --untracked-files=all -- reports; git ls-files -s reports | git hash-object --stdin)
if [ "$(G ls-files -s reports)" = "$SB_REPORTS_BEFORE" ] && [ -z "$(G status --porcelain --untracked-files=all -- reports)" ] && [ "$REAL_REPORTS_AFTER" = "$REAL_REPORTS_BEFORE" ]; then
  case_pass other_reports_untouched "沙箱 reports/9000 和本仓库 reports/ 都没变"
else
  case_fail other_reports_untouched "reports/ 有变化：$(G status --porcelain --untracked-files=all -- reports | head -n 3 | tr '\n' ' ')"
fi
if [ -z "$(ls -A "$SB/tmp")" ]; then case_pass sandbox_removed "每次跑完 TMPDIR 下没有残留"; else case_fail sandbox_removed "残留：$(ls -A "$SB/tmp" | tr '\n' ' ')"; fi
# ==== 在这里写你的 E2E 步骤 ↑ ====

rm -rf "$WORK"; trap - EXIT
if [ "$TOTAL" -eq 0 ]; then rc=3; elif [ "$PASS" -eq "$TOTAL" ]; then rc=0; else rc=1; fi
echo "产物: $OUT/results.tsv"
echo "RERUN pr=${PR_NUMBER} head=${HEAD_SHA} pass=${PASS} total=${TOTAL}"
exit "$rc"
