#!/bin/bash
# S12 ② 转发程序的本地自查（开发自查，用了替身上游，不是 E2E）。只在 MBA 上跑，不碰 iMac。
# 起三个进程，都只听 127.0.0.1 的空闲端口，跑完全部关掉：
#   1) 替身上游：记下收到的每个请求（方法、路径、全部头、正文），一律回 401；Idempotency-Key 为 slow 时 20 秒才回。
#   2) 转发程序（--dev-listen / --dev-upstream），上游指向替身。
#   3) 另一个转发程序，上游指向没人听的端口，用来测 502。
# 然后跑 probe.py --mode selfcheck，再查日志里有没有 bearer、publicId、IP。
# 用法：selfcheck-mba.sh <输出目录>    输出目录里留下 probe.txt、forwarder.log、upstream.jsonl（bearer 已打码）
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?用法: selfcheck-mba.sh <输出目录>}
mkdir -p "${out}"
NODE=${NODE:-$(command -v node)}
work=$(mktemp -d)
pids=()
cleanup() {
    for p in "${pids[@]:-}"; do [ -n "${p}" ] && kill "${p}" 2>/dev/null; done
    wait 2>/dev/null
    rm -rf "${work}"
}
trap cleanup EXIT

free_port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }
up_port=$(free_port); fwd_port=$(free_port); down_port=$(free_port); fwd2_port=$(free_port)

cat >"${work}/upstream.py" <<'PYEOF'
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
port, log = int(sys.argv[1]), sys.argv[2]
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def handle_any(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        with open(log, "a") as f:
            f.write(json.dumps({"method": self.command, "path": self.path, "headers": list(self.headers.items()), "body": body}) + "\n")
        if self.headers.get("Idempotency-Key") == "slow":
            time.sleep(20)
        out = b'{"error":"Unauthorized"}'
        self.send_response(401)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Set-Cookie", "probe=1")
        self.send_header("Content-Length", str(len(out)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(out)
    do_POST = do_GET = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = handle_any
    def log_message(self, *a):
        pass
ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF

: >"${work}/upstream.jsonl"
python3 -I "${work}/upstream.py" "${up_port}" "${work}/upstream.jsonl" & pids+=($!)
# 和 LaunchAgent 一样用 env -i 起：本会话的环境里有 ORCA_*，转发程序见到会拒绝启动（F23）。
# 直接后台起 env（env 会 exec 成 node，$! 就是 node 的进程），不包成函数，免得 kill 只杀到子 shell。
fwd=(env -i HOME="${HOME}" PATH=/usr/bin:/bin LANG=en_US.UTF-8 "${NODE}" --max-old-space-size=32 "${here}/forwarder.js")
"${fwd[@]}" --dev-listen "127.0.0.1:${fwd_port}" --dev-upstream "127.0.0.1:${up_port}" >"${work}/forwarder.log" 2>&1 & pids+=($!)
"${fwd[@]}" --dev-listen "127.0.0.1:${fwd2_port}" --dev-upstream "127.0.0.1:${down_port}" >"${work}/forwarder-down.log" 2>&1 & pids+=($!)
sleep 1
for p in "${pids[@]}"; do kill -0 "${p}" 2>/dev/null || { echo "有进程没起来:"; cat "${work}"/forwarder*.log; exit 1; }; done

{
    date '+%F %T %z'
    echo "开发自查（替身上游，不是 E2E）。node: ${NODE} $("${NODE}" -v)；git: $(git -C "${here}" rev-parse HEAD 2>/dev/null)"
    echo "forwarder.js sha256: $(shasum -a 256 "${here}/forwarder.js" | cut -c1-16)"
    echo "== 启动检查 =="
    "${NODE}" "${here}/forwarder.js" --dev-listen 127.0.0.1:1 --dev-upstream 127.0.0.1:1 >"${work}/orca.log" 2>&1; rc=$?
    grep -q 'reason=orca_env_present' "${work}/orca.log" && [ "${rc}" = 1 ] && r=PASS || r=FAIL
    echo "${r}  环境里有 ORCA_* 时拒绝启动（本会话环境里 ORCA_ 键 $(env | grep -c '^ORCA_') 个）| 期望 退出码 1 | 实际 ${rc}"
    echo "== 参数检查 =="
    for bad in "--dev-listen 0.0.0.0:1 --dev-upstream 127.0.0.1:1" "--dev-listen 127.0.0.1:1" "--listen 127.0.0.1:1" "--dev-listen 198.51.100.2:1 --dev-upstream 127.0.0.1:1"; do
        # shellcheck disable=SC2086
        "${NODE}" "${here}/forwarder.js" ${bad} >/dev/null 2>&1; rc=$?
        [ "${rc}" = 2 ] && r=PASS || r=FAIL
        echo "${r}  参数 '${bad}' 被拒 | 期望 退出码 2 | 实际 ${rc}"
    done
    echo "== 监听 =="
    lsof -nP -a -p "${pids[1]}" -iTCP -sTCP:LISTEN | awk 'NR>1 {print "转发程序监听:", $9}'
    echo "== probe.py =="
    PROBE_PUBLIC_ID=$(python3 -I -c 'import secrets; print(secrets.token_hex(12))') \
        python3 -I "${here}/probe.py" --host 127.0.0.1 --port "${fwd_port}" --mode selfcheck \
        --upstream-log "${work}/upstream.jsonl" --down-port "${fwd2_port}"
    echo "probe 退出码: $?"
    echo "== 日志检查（F17）=="
    logs="${work}/forwarder.log ${work}/forwarder-down.log"
    # shellcheck disable=SC2086
    echo "日志行数: $(cat ${logs} | wc -l | tr -d ' ')"
    # shellcheck disable=SC2086
    for pat in 'Bearer' '[0-9a-f]{24}' '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' 'forwarder-probe' 'evil'; do
        n=$(cat ${logs} | grep -cE "${pat}")
        [ "${n}" = 0 ] && r=PASS || r=FAIL
        echo "${r}  日志里 /${pat}/ 出现次数 | 期望 0 | 实际 ${n}"
    done
    echo "日志里出现的字段名: $(cat ${logs} | grep -oE '[a-z]+=' | sort -u | tr '\n' ' ')"
    echo "日志样例（前 5 行）:"; head -5 "${work}/forwarder.log"
    echo "内存: 转发程序 RSS $(ps -o rss= -p "${pids[1]}" | tr -d ' ') KB"
} 2>&1 | tee "${out}/probe.txt"

cp "${work}/forwarder.log" "${out}/forwarder.log"
sed -E 's/Bearer [0-9a-f]{48}/Bearer <wrong-random>/g; s/[0-9a-f]{24}/<test-id>/g' "${work}/upstream.jsonl" >"${out}/upstream.jsonl"
