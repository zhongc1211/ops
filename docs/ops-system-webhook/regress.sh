#!/bin/bash
# 用法: regress.sh <ops 仓库路径> <输出目录>。临时 HOME 里放假 env（值都是 FAKE*），逐项看脚本能否分辨。
set -u
REPO=$1 OUT=$2
T=$(mktemp -d "$OUT/fakehome.XXXX"); W=$T/.config/grokbot/webhooks; E=$T/.config/orca-wake/enabled-bots
mkdir -p "$W" "$T/.config/orca-wake"
mk(){ printf "$2" > "$W/$1.env"; chmod "${3:-600}" "$W/$1.env"; }
fails=0
run(){ # 名称 期望rc 期望出现的文本... -- 参数
  name=$1 want=$2; shift 2; pats=(); while [ "$1" != -- ]; do pats+=("$1"); shift; done; shift
  echo "--- $name"; HOME=$T /bin/bash "$REPO/scripts/check-bot-webhooks" "$@" > "$OUT/out.txt"; rc=$?
  cat "$OUT/out.txt"; v="rc=$rc(期望 $want)"
  [ "$rc" = "$want" ] || { v="$v 不符"; fails=$((fails+1)); }
  for p in ${pats[@]+"${pats[@]}"}; do grep -qF -- "$p" "$OUT/out.txt" || { v="$v 缺「${p}」"; fails=$((fails+1)); }; done
  grep -q FAKE "$OUT/out.txt" && { v="$v 泄露了值"; fails=$((fails+1)); }
  echo "判定: $v"
}
mk ops-system 'URL=https://example.invalid/FAKEURL\nKEY=FAKEKEY1\n'
mk good 'export URL="https://example.invalid/FAKEURL"\n  KEY=FAKEKEY1\n'
mk perm 'URL=https://example.invalid/FAKEURL\nKEY=FAKEKEY1\n' 644
mk nokey 'URL=https://example.invalid/FAKEURL\n'
mk emptykey 'URL=https://example.invalid/FAKEURL\nKEY=\n'
mk dup 'URL=https://example.invalid/FAKEURL\nURL=https://example.invalid/FAKE2\nKEY=FAKEKEY1\n'
mk unread 'URL=FAKEU\nKEY=FAKEK\n' 000
mk shadowbot 'URL=https://example.invalid/FAKEURL\nKEY=FAKEKEY1\n'
mk shadowbad 'URL=https://example.invalid/FAKEURL\n'
printf 'ops-system\ngood\n  perm  \nnokey\nemptykey\ndup\nunread\nmissing\n# comment\n\n' > "$E"
run "1-7 全套坏样本" 1 "ops-system               有    在    ok" "good                     有    在    ok" "权限644" "缺KEY" "KEY为空" "URL重复2行" "不可读" "missing                  无    在    错误：缺env" "影子：" "提示：缺KEY（不在名单里" -- --require ops-system
printf 'ops-system\ngood\n' > "$E"; rm "$W"/{perm,nokey,emptykey,dup,unread,shadowbad}.env
run "对照：清掉坏样本后正常" 0 "结论: 正常" -- --require ops-system
mv "$W/ops-system.env" "$OUT/ops-system.env.save"
run "回退：删掉 ops-system.env" 1 "ops-system               无    在    错误：缺env" "结论: 有问题" -- --require ops-system
printf 'good\n' > "$E"
run "回退：名单少 ops-system、--require" 1 "错误：缺env" -- --require ops-system
mv "$OUT/ops-system.env.save" "$W/ops-system.env"
run "env 在、名单少 ops-system、--require" 1 "错误：不在 enabled-bots 里" -- --require ops-system
printf '*\n' > "$E"
run "8 名单写 *" 0 "ops-system               有    在    ok" -- --require ops-system
rm "$E"
run "7 名单文件不存在" 1 "enabled-bots 不存在" -- 
run "用法错误" 2 -- --bogus
echo "== 总计不符: $fails"
rm -rf "$T"
exit $((fails>0))
