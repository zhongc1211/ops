#!/bin/bash
# PR 91（scripts/pr-gate）复跑：真 PR 上的 E2E + fixtures/ 构造输入的演练，一条命令跑完。
# 用法：reports/91/rerun.sh    （从哪里启动都行）
# 产物：${RERUN_OUT:-~/.orca-state/e2e/pr91-<HEAD 前 12 位>}/results.tsv，raw/ 里是每个用例的原始输出。
# 退出码：全 PASS 且用例数 > 0 → 0；有 FAIL → 1；用例数 0 → 3。最后一行：RERUN pr=91 head=<sha> pass=<p> total=<t>
# 真 PR 用例要 gh；artifact_mba_* 两个演练用例要能 ssh mba（只读）。不写仓库里的文件。
set -u
cd "$(dirname "$0")/../.." || exit 2
ROOT=$PWD; N=91
HEAD=$(git rev-parse HEAD) || exit 2
OUT=${RERUN_OUT:-$HOME/.orca-state/e2e/pr$N-${HEAD:0:12}}
GATE=$ROOT/scripts/pr-gate; FX=$ROOT/reports/$N/fixtures
FXHEAD=$(cat "$FX/base/head")
CHECKS="E2E_SHA ARTIFACT FIELDS NO_AI_ATTRIBUTION NO_COAUTHOR RERUN"
REAL_PRS="90 71 75 88 89"

mkdir -p "$OUT/raw" || exit 2
R=$OUT/results.tsv
printf 'case\tstatus\tdetail\n' > "$R"
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
{ echo "commit=$HEAD"; echo "date=$(date '+%F %T %z')"; echo "host=$(hostname -s)"
  echo "python3=$(python3 -I -c 'import sys; print(sys.version.split()[0])')"; echo "gh=$(gh --version | head -1)"
  echo "uncommitted=$(git status --porcelain | wc -l | tr -d ' ')"; } > "$OUT/META"

pass=0; total=0
rec(){ total=$((total+1)); [ "$2" = PASS ] && pass=$((pass+1))
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$R"; echo "$2 $1 $3"; }
# 某项检查在 gate 输出里的状态：PASS / FAIL / missing
status_of(){ awk -v c="$2" '($1=="PASS"||$1=="FAIL") && $2==c {print $1; f=1; exit} END{if(!f) print "missing"}' "$1"; }

# E2E：真 PR，只断言 gate 正常跑完（退出 0/1、六项都有、有 RESULT 行），各项结果记在 detail
for pr in $REAL_PRS; do
  o=$OUT/raw/real_pr$pr.txt
  python3 -I "$GATE" --repo zhongc1211/ops "$pr" > "$o" 2>&1; rc=$?
  ok=1; d="rc=$rc"
  case $rc in 0|1) ;; *) ok=0 ;; esac
  for c in $CHECKS; do
    s=$(status_of "$o" "$c"); [ "$s" = missing ] && ok=0; d="$d $c=$s"
  done
  grep -q '^RESULT: ' "$o" || { ok=0; d="$d no-RESULT-line"; }
  if [ $ok = 1 ]; then rec "real_pr$pr" PASS "$d"; else rec "real_pr$pr" FAIL "$d"; fi
done

# 演练：fixtures/base 叠上 fixtures/cases/<名字>，断言只有 expect 里列的检查 FAIL
for cdir in "$FX"/cases/*/; do
  name=$(basename "$cdir"); w=$TMP/$name; mkdir -p "$w/home"
  cp -Rp "$FX/base/." "$w/" && cp -Rp "$cdir." "$w/"
  if [ -f "$w/remove" ]; then
    while read -r p; do [ -n "$p" ] && rm -rf "${w:?}/$p"; done < "$w/remove"
  fi
  sed "s#@CASEDIR@#$w#g" "$w/body.md" > "$w/body.sub" && mv "$w/body.sub" "$w/body.md"
  if [ -f "$w/args" ]; then a=$(cat "$w/args")
  else a="7 --body-file $w/body.md --head-sha $FXHEAD --commits-file $w/commits.txt --tree-dir $w/tree"; fi
  [ -f "$w/args_extra" ] && a="$a $(cat "$w/args_extra")"
  a=$(printf '%s' "$a" | sed -e "s#@CASEDIR@#$w#g" -e "s#@HEAD@#$FXHEAD#g")
  expect=$(tr -d ' \n' < "$w/expect")
  o=$OUT/raw/drill_$name.txt
  # shellcheck disable=SC2086  # 参数里没有空格，按词拆开
  HOME=$w/home python3 -I "$GATE" $a > "$o" 2>&1; rc=$?
  ok=1; d="rc=$rc expect=$expect"
  if [ "$expect" = exit2 ]; then
    [ $rc = 2 ] || ok=0
    grep -q '^RESULT: PASS' "$o" && { ok=0; d="$d printed-RESULT-PASS"; }
  else
    want_rc=0; [ "$expect" = none ] || want_rc=1
    [ $rc = $want_rc ] || { ok=0; d="$d want-rc=$want_rc"; }
    for c in $CHECKS; do
      case ",$expect," in *",$c,"*) want=FAIL ;; *) want=PASS ;; esac
      s=$(status_of "$o" "$c")
      [ "$s" = "$want" ] || { ok=0; d="$d $c=$s(want $want)"; }
    done
  fi
  # want_text：每行一段必须出现在输出里的文字（证明 FAIL/PASS 的原因对，不只是状态对）
  if [ -f "$w/want_text" ]; then
    while IFS= read -r t; do
      [ -n "$t" ] && { grep -qF -- "$t" "$o" || { ok=0; d="$d missing-text:$t"; }; }
    done < "$w/want_text"
  fi
  if [ $ok = 1 ]; then rec "drill_$name" PASS "$d"; else rec "drill_$name" FAIL "$d"; fi
done

if command -v shasum >/dev/null; then shasum -a 256 "$R"; else sha256sum "$R"; fi > "$OUT/results.sha256"
echo "out=$OUT"
if [ $total = 0 ]; then code=3; elif [ $pass = $total ]; then code=0; else code=1; fi
echo "RERUN pr=$N head=$HEAD pass=$pass total=$total"
exit $code
