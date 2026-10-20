#!/bin/bash
# sync-bot-rules-test.sh: run scripts/sync-bot-rules against a throwaway git repo and fake target dirs under mktemp -d.
# Covers same / drift / missing / extra, --check writing nothing (find + sha256 before/after), --apply backup + second run
# with 0 writes, missing target dir, bad ref, and that no file content is printed. Touches nothing outside its temp dir.
# SYNC_BOT_RULES=<path> runs another implementation (e.g. an empty stub, which must make this test fail).
S=${SYNC_BOT_RULES:-$(cd "$(dirname "$0")/.." && pwd)/sync-bot-rules}
W=$(mktemp -d "${TMPDIR:-/tmp}/sync-bot-rules-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
B=$W/sandbox; R=$B/repo; T1=$B/t1/dev-bot-rules; T2=$B/t2/absent; fails=0; n=0
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
ok(){ n=$((n+1)); echo "ok   $n $1"; }
bad(){ n=$((n+1)); fails=$((fails+1)); echo "FAIL $n $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; echo "     output:"; sed 's/^/     | /' "$W/out"; fi; }
snap(){ (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r p; do
  if [ -f "$p" ]; then echo "$p $(sha <"$p")"; else echo "$p dir"; fi; done) | sha; }
run(){ "$S" --repo "$R" --ref HEAD --no-fetch "$@" >"$W/out" 2>&1; echo $?; }

mkdir -p "$R/docs/bot-rules/dev-bot-rules/appendix" "$T1" "$B/t2"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf 'core rules SECRET-MARKER-%s\n' $$ >"$R/docs/bot-rules/dev-bot-rules/SKILL.md"
printf 'appendix A\n' >"$R/docs/bot-rules/dev-bot-rules/appendix/A.md"
printf '# m\thost\tsrc\tdst\nt1\tno-such-host-*\tdocs/bot-rules/dev-bot-rules/\t%s/\nt2\tno-such-host-*\tdocs/bot-rules/dev-bot-rules\t%s\n' \
  "$T1" "$T2" >"$R/docs/bot-rules/targets.tsv"
git -C "$R" add -A; git -C "$R" commit -qm init
SKILL_SHA=$(sha <"$R/docs/bot-rules/dev-bot-rules/SKILL.md")
cp "$R/docs/bot-rules/dev-bot-rules/SKILL.md" "$T1/"; mkdir -p "$T1/appendix"; cp "$R/docs/bot-rules/dev-bot-rules/appendix/A.md" "$T1/appendix/"
printf 'old backup\n' >"$T1/SKILL.md.bak-20261014-watchdog"

rc=$(run --check --machine t1)
check "same: exit 0" '[ "$rc" = 0 ]'
check "same: two files reported same, sha256 shown" '[ "$(grep -c " | same$" "$W/out")" = 2 ] && grep -q "$SKILL_SHA" "$W/out"'
check "same: *.bak* in target is not reported as extra" '! grep -q "bak-20261014" "$W/out"'
check "no file content printed" '! grep -q SECRET-MARKER "$W/out"'

printf 'edited on box, not in git\n' >"$T1/SKILL.md"; rm "$T1/appendix/A.md"; printf 'stray\n' >"$T1/NOTES.md"
before=$(snap "$B"); rc=$(run --check --machine t1); after=$(snap "$B")
check "drift/missing/extra: exit 1" '[ "$rc" = 1 ]'
check "drift reported" 'grep -q "$T1/SKILL.md | $SKILL_SHA | .* | drift$" "$W/out"'
check "missing reported" 'grep -q "$T1/appendix/A.md | .* | - | missing$" "$W/out"'
check "extra reported" 'grep -q "$T1/NOTES.md | - | .* | extra$" "$W/out"'
check "--check writes nothing (find + sha256 of repo and targets before/after)" '[ "$before" = "$after" ]'
check "--check is the default mode" '[ "$(run --machine t1)" = 1 ] && [ "$(snap "$B")" = "$before" ]'

rc=$(run --apply --machine t1)
check "--apply with extra left: exit 1, extra kept" '[ "$rc" = 1 ] && [ -f "$T1/NOTES.md" ]'
check "--apply: drifted file backed up with old content" 'b=$(ls "$T1"/SKILL.md.bak-2* 2>/dev/null | grep -v 20261014); [ -n "$b" ] && grep -qx "edited on box, not in git" "$b"'
check "--apply: SKILL.md and appendix/A.md now match git" '[ "$(sha <"$T1/SKILL.md")" = "$SKILL_SHA" ] && cmp -s "$T1/appendix/A.md" "$R/docs/bot-rules/dev-bot-rules/appendix/A.md"'
check "--apply: sha256 printed after write" '[ "$(grep -c "写入 " "$W/out")" = 2 ]'
rm "$T1/NOTES.md"; before=$(snap "$B"); rc=$(run --apply --machine t1); after=$(snap "$B")
check "--apply second run: exit 0, 0 writes, tree unchanged" '[ "$rc" = 0 ] && ! grep -q "写入 \|备份 " "$W/out" && [ "$before" = "$after" ]'

for mode in --check --apply; do
  rc=$(run $mode --machine t2)
  check "target dir missing ($mode): exit 2, dir not created" '[ "$rc" = 2 ] && [ ! -e "$T2" ] && grep -q "target dir missing" "$W/out"'
done
rc=$(run --check --machine t1 --ref no-such-ref)
check "bad ref: exit 2" '[ "$rc" = 2 ]'
rc=$(run --check)
check "host matches no row: exit 0, says no targets" '[ "$rc" = 0 ] && grep -q "没有目标" "$W/out"'

echo "$((n-fails))/$n passed"; [ $fails = 0 ]
