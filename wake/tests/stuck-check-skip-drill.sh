#!/bin/bash
# E2E：卡住检查跳过演练工作区（PER-119）。在 iMac 本机真 Orca 里建三个工作区，各起一个真 claude（不发 prompt），
# 跑真 stuck-check（不带参数 = 不经复核直接发），webhook 全指向本机假接收端（mock_webhook.py，假 key）。
#   per119-e2e-mark-<ts>   演练：工作区根目录有 .orca-drill
#   per119-e2e-prefix-<ts> 演练：显示名以「[演练]」开头
#   per119-e2e-drill-<ts>  普通工作区（名字和显示名里故意带 drill，证明不按名字认）
# 第一轮 claude 还活着 → 普通的 1 条 agent_unwrapped；第二轮杀掉 claude（终端留着）→ 普通的 1 条 agent_gone。
# 两个演练工作区两轮都 0 条，日志里有「skip drill iMac:<路径>」。
#
#   wake/tests/stuck-check-skip-drill.sh [--src <目录>] [--out <产物目录>]
#     --src  里面要有 scripts/stuck-check.sh、scripts/agent-probe、orca-projects.md（默认本仓库）；回退测试用
#            git archive 7d12370 解出来的目录，应当失败（演练工作区也被报）。
#     --out  产物目录（默认 mktemp）：requests.jsonl、stuck-check.log、run-*.txt、orca-*.json、assert.txt
# 退出码：0 断言全过；1 断言失败；9 离线上下次扫描太近不开跑（E2E_NEED_MIN，默认 10 分钟）。
#
# 线上卡住检查每分钟跑一次 precheck，距上次扫描满 15 分钟（~/.orca-state/stuck-check/gate.json 的 last）或 Orca 重启就扫，
# 线上的扫描不认演练标记（没装这个改动）也不认 per119-e2e，所以三个工作区都必须在两次线上扫描之间建完、跑完、清掉。
# 只读 gate.json，不碰线上状态目录。退出时（含出错）关终端、按 cwd 杀残留 claude、删这三个工作区和分支。
set -u
here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)
SRC=$ROOT OUT=
while [ $# -gt 0 ]; do
  case $1 in
    --src) SRC=$(cd "$2" && pwd); shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    *) echo "不认识的参数 $1" >&2; exit 2 ;;
  esac
done
[ -n "$OUT" ] || OUT=$(mktemp -d)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
PORT=${PORT:-18819}
TS=$(date +%m%d%H%M%S)
NEED=${E2E_NEED_MIN:-10}

# ---- 线上扫描窗口 ----
python3 - "$NEED" > "$OUT/window.txt" <<'EOF' || { cat "$OUT/window.txt"; exit 9; }
import json, os, sys, time
g = json.load(open(os.path.expanduser("~/.orca-state/stuck-check/gate.json")))
now, need = time.time(), float(sys.argv[1])
last, done = g.get("last", 0), g.get("done", 0)
left = (last + 15 * 60 - now) / 60
f = lambda t: time.strftime("%F %T", time.localtime(t))
print("线上上次扫描 %s 开始，%s 结束；下次约 %s，还有 %.1f 分钟（要 ≥ %.0f）" % (f(last), f(done), f(last + 900), left, need))
sys.exit(0 if done >= last and left >= need else 1)
EOF
cat "$OUT/window.txt"

REPO_ID=$(orca worktree list --json | python3 -c "
import json,sys;d=json.load(sys.stdin);r=d.get('result',d)
print(next(w['repoId'] for w in r['worktrees'] if w.get('isMainWorktree') and w['path'].rstrip('/').endswith('/orca/workspaces/ops')))")
: > "$OUT/ws.tsv"; : > "$OUT/handles.tsv"   # 名字 路径 分支 角色；角色 终端句柄
cleanup() {
  set +e
  while IFS=$'\t' read -r role handle; do
    orca terminal close --terminal "$handle" --json > "$OUT/orca-term-close-$role.json" 2>&1
  done < "$OUT/handles.tsv"
  sleep 2
  for p in $(e2e_pids); do kill "$p" 2>/dev/null; done
  while IFS=$'\t' read -r name path branch role; do
    orca worktree rm --worktree "path:$path" --force --json > "$OUT/orca-rm-$role.json" 2>&1
    echo "删工作区 $role rc=$?"
    [ -n "$branch" ] && git -C "$ROOT" branch -D "${branch#refs/heads/}" >/dev/null 2>&1
  done < "$OUT/ws.tsv"
  [ -n "${MOCK:-}" ] && kill "$MOCK" 2>/dev/null
  orca worktree list --json > "$OUT/orca-list-after.json" 2>&1
  echo "清场后 orca worktree list 里 per119-e2e：$(grep -c 'per119-e2e' "$OUT/orca-list-after.json") 处"
  echo "残留 claude：$(e2e_pids | wc -l | tr -d ' ') 个"
  date '+清场结束 %F %T'
}
e2e_pids() {  # cwd 在本次三个工作区里的进程（不按名字 pkill，免得碰到别人的）
  local p c
  for p in $(pgrep -f 'claude|sleep 3600'); do
    c=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    case "$c" in *per119-e2e-*-$TS*) echo "$p";; esac
  done
}
trap 'cleanup 2>&1 | tee "$OUT/cleanup.txt"' EXIT
date '+开始 %F %T'

# ---- 假接收端和假 webhook 目录（假 key，URL 只指向 127.0.0.1）----
H=$OUT/hooks; mkdir -p "$H/webhooks" "$H/runs" "$OUT/state"
for b in ops-system coding-assistant xinyue vllm-omni deepvision-marketing deepvision-ads deepvision-ops; do
  printf 'URL=http://127.0.0.1:%s/e2e/%s\nKEY=e2e-key\n' "$PORT" "$b" > "$H/webhooks/$b.env"
done
printf 'URL=http://127.0.0.1:%s/e2e/stuck-default\nKEY=e2e-key\n' "$PORT" > "$H/stuck.env"
: > "$OUT/requests.jsonl"
python3 "$here/mock_webhook.py" --port "$PORT" --out "$OUT/requests.jsonl" --key e2e-key > "$OUT/receiver.log" 2>&1 &
MOCK=$!

# ---- 三个工作区 ----
mk() { # 角色 名字 显示名 标记文件(1/0)
  local role=$1 name=$2 disp=$3 mark=$4 j path branch h
  j=$(orca worktree create --repo "id:$REPO_ID" --no-parent --setup skip --name "$name" --json 2>&1)
  echo "$j" > "$OUT/orca-create-$role.json"
  path=$(echo "$j" | python3 -c "import json,sys;d=json.load(sys.stdin);r=d.get('result',d);w=r.get('worktree',r);print(w.get('path',''))" 2>/dev/null)
  branch=$(echo "$j" | python3 -c "import json,sys;d=json.load(sys.stdin);r=d.get('result',d);w=r.get('worktree',r);print(w.get('branch',''))" 2>/dev/null)
  [ -n "$path" ] || { echo "建 $role 失败：$(echo "$j" | head -c 300)"; return 1; }
  [ "$mark" = 1 ] && : > "$path/.orca-drill"
  printf '%s\t%s\t%s\t%s\n' "$name" "$path" "$branch" "$role" >> "$OUT/ws.tsv"   # 先记下，失败也能清
  orca worktree set --worktree "path:$path" --display-name "$disp" --workspace-status in-progress --json > "$OUT/orca-set-$role.json" 2>&1
  h=$(orca terminal create --worktree "path:$path" --title "per119 e2e $role" --command "claude; sleep 3600" --json 2>&1 | tee "$OUT/orca-term-$role.json" |
      python3 -c "import json,sys;d=json.load(sys.stdin);r=d.get('result',d);print(r['terminal']['handle'])" 2>/dev/null)
  [ -n "$h" ] || { echo "起 $role 终端失败"; return 1; }
  printf '%s\t%s\n' "$role" "$h" >> "$OUT/handles.tsv"
  echo "建好 $role $path 终端 $h"
}
mk mark "per119-e2e-mark-$TS" "ops · per119-e2e 演练（标记文件）" 1 || exit 1
mk prefix "per119-e2e-prefix-$TS" "[演练] ops · per119-e2e 显示名" 0 || exit 1
mk real "per119-e2e-drill-$TS" "ops · per119-e2e drill 普通工作区" 0 || exit 1
path_of() { awk -F'\t' -v r="$1" '$4==r{print $2}' "$OUT/ws.tsv"; }

# 等三个 claude 都起来
for _ in $(seq 1 30); do [ "$(e2e_pids | xargs -n1 ps -o comm= -p 2>/dev/null | grep -c claude)" -ge 3 ] && break; sleep 2; done
echo "claude 进程：$(for p in $(e2e_pids); do ps -o pid=,comm= -p "$p"; done | grep -c claude) 个"

run_check() { # 轮次
  ( env STUCK_STATE_DIR="$OUT/state" STUCK_WEBHOOK_DIR="$H/webhooks" STUCK_ENV_FILE="$H/stuck.env" STUCK_RUNS_DIR="$H/runs" \
      STUCK_ONLY="per119-e2e-[a-z]+-$TS" STUCK_BOX_ENV=per119-e2e-none STUCK_BOX_RETRY_WAIT=0 STUCK_MBA_ENV= \
      STUCK_ORCA_WAKE=/usr/bin/false STUCK_GONE_MIN=0 STUCK_POST_GAP=1 STUCK_BACKOFF=1 \
      STUCK_MAPPING="$SRC/orca-projects.md" STUCK_PROBE="$SRC/scripts/agent-probe" \
      bash "$SRC/scripts/stuck-check.sh"; echo "rc=$?" ) > "$OUT/run-$1.txt" 2>&1
  tail -1 "$OUT/run-$1.txt"
}
date '+第一轮（claude 活着）%T'; run_check 1-alive
for p in $(e2e_pids); do [ "$(ps -o comm= -p "$p")" = claude ] && kill "$p"; done
sleep 5
echo "杀掉 claude 后剩 $(for p in $(e2e_pids); do ps -o comm= -p "$p"; done | grep -c claude) 个，终端：$(orca terminal list --json | grep -c "per119-e2e-.*-$TS")"
date '+第二轮（claude 没了）%T'; run_check 2-gone
sleep 2
cp "$OUT/state/stuck-check.log" "$OUT/stuck-check.log" 2>/dev/null

python3 - "$OUT" "$(path_of mark)" "$(path_of prefix)" "$(path_of real)" > "$OUT/assert.txt" <<'EOF'
import json, sys
out, mark, prefix, real = sys.argv[1:5]
reqs = [json.loads(l) for l in open(out + "/requests.jsonl", encoding="utf-8") if l.strip()]
log = open(out + "/stuck-check.log", encoding="utf-8").read() if __import__("os").path.exists(out + "/stuck-check.log") else ""
def hits(path, kind=None):
    return [r for r in reqs if path in json.dumps(r["body"], ensure_ascii=False) and (kind is None or r["body"].get("kind") == kind)]
ok = True
def check(name, cond, detail):
    global ok
    ok &= bool(cond)
    print("%s %s（%s）" % ("PASS" if cond else "FAIL", name, detail))
print("假接收端共收到 %d 条：%s" % (len(reqs), ", ".join("%s %s" % (r["path"], r["body"].get("kind")) for r in reqs)))
check("所有请求带假 key", all(r["auth_ok"] for r in reqs), "auth_ok")
for role, p in (("标记文件", mark), ("显示名前缀", prefix)):
    check("演练工作区（%s）0 条" % role, not hits(p), "%d 条" % len(hits(p)))
    check("演练工作区（%s）记了 skip drill" % role, "skip drill iMac:%s" % p in log, p)
check("普通工作区 1 条 agent_gone", len(hits(real, "agent_gone")) == 1, "%d 条" % len(hits(real, "agent_gone")))
check("普通工作区 1 条 agent_unwrapped", len(hits(real, "agent_unwrapped")) == 1, "%d 条" % len(hits(real, "agent_unwrapped")))
check("普通工作区没记 skip drill", "skip drill iMac:%s" % real not in log, real)
print("结论：%s" % ("通过" if ok else "失败"))
sys.exit(0 if ok else 1)
EOF
rc=$?
cat "$OUT/assert.txt"
exit $rc
