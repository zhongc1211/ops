#!/bin/bash
# Precheck of Orca automation「心月夜审兜底」(box, daily 00:30 SGT). Read-only check of last night's
# 心月夜审 75b324a4 (23:30):
#   - ~/xinyue-deploy/nightly-review/$D.md exists and has the line「状态：完成」
#   - ~/xinyue-deploy/nightly-review/$D-ledger.jsonl has count_before and count_after (http 200, not dry-run)
#     from the same nightly_addflush.py run
# Anything missing -> one POST status=stuck to the coding-assistant webhook (~/.config/grokbot/webhooks/coding-assistant.env).
# Always exits 1 so the model is never started. Writes no files.
# D defaults to the SGT date 12 hours ago (00:30 -> yesterday; a late run before noon still checks the right night).
# DRY_RUN=1: print the payload instead of POSTing.
set -u
export TZ=Asia/Singapore
D=${D:-$(date -d '12 hours ago' +%F 2>/dev/null || date -v-12H +%F)}
DIR=${NIGHTLY_REVIEW_DIR:-$HOME/xinyue-deploy/nightly-review}
SUMMARY=$DIR/$D.md
LEDGER=$DIR/$D-ledger.jsonl
HOOK_ENV=$HOME/.config/grokbot/webhooks/coding-assistant.env

problems=()
if [ ! -f "$SUMMARY" ]; then
  problems+=("没有摘要 $D.md")
elif ! grep -Eq '^状态(：|:)[[:space:]]*完成' "$SUMMARY"; then
  st=$(grep -Em1 '^状态(：|:)' "$SUMMARY" | sed -E 's/^状态(：|:)[[:space:]]*//')
  step=$(grep -Em1 '^当前步骤(：|:)' "$SUMMARY" | sed -E 's/^当前步骤(：|:)[[:space:]]*//')
  problems+=("摘要状态=${st:-无状态行}${step:+（当前步骤：${step}）}")
fi
ledger_msg=$(python3 -I - "$LEDGER" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except OSError:
    print("没有台账 " + path.rsplit("/", 1)[-1]); sys.exit()
runs = {}
for ln in lines:
    try:
        o = json.loads(ln)
    except ValueError:
        continue
    if o.get("dry_run") or o.get("kind") not in ("count_before", "count_after"):
        continue
    runs.setdefault(o.get("run"), {})[o["kind"]] = o
if any(all(r.get(k, {}).get("http") == 200 for k in ("count_before", "count_after")) for r in runs.values()):
    sys.exit()
seen = {k for r in runs.values() for k, o in r.items() if o.get("http") == 200}
miss = [n for k, n in (("count_before", "写前计数"), ("count_after", "写后计数")) if k not in seen]
print("台账缺" + "、".join(miss) if miss else "台账写前、写后计数不在同一次运行里")
PYEOF
)
[ -n "$ledger_msg" ] && problems+=("$ledger_msg")

if [ ${#problems[@]} -eq 0 ]; then
  echo "night-review-guard $D: 摘要状态=完成，台账写前写后计数都在，不发 webhook"
  exit 1
fi
joined=""
for p in "${problems[@]}"; do joined="${joined:+${joined}；}${p}"; done
note="心月夜审 ${D} 没有正常收尾：${joined}"
payload=$(python3 -I -c 'import json,sys; print(json.dumps({"bot":"coding-assistant","task":"心月夜审兜底 "+sys.argv[1],"worktree":"/workspace/repos/ops","status":"stuck","note":sys.argv[2]}, ensure_ascii=False))' "$D" "$note")
echo "night-review-guard $D: $note"
if [ "${DRY_RUN:-}" = 1 ]; then
  echo "dry-run, would POST: $payload"
  exit 1
fi
if [ ! -f "$HOOK_ENV" ]; then
  echo "webhook 未配置（$HOOK_ENV 不存在），没有发送" >&2
  exit 1
fi
( set -a; . "$HOOK_ENV"; set +a
  curl -fsS -m 20 -o /dev/null -w 'webhook http=%{http_code}\n' -X POST "$URL" \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' --data-binary "$payload" ) \
  || echo "webhook 发送失败" >&2
exit 1
