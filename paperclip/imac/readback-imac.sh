#!/bin/bash
# S12 ② 读回（在 iMac 上跑，只读）。不打印密钥、IP、ID、PID；密钥文件只看是否非空、长度、权限。
# 会对本机触发路径发两次「不带 bearer / 带错 bearer」的 POST，预期 401；
# 触发器还在 setupPending，Paperclip 只记一条 webhook_test_rejected 活动，不起运行。
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/config.sh"

say() { printf '%s\n' "$*"; }
mask() { sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<ip>/g; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<id>/g; s/[A-Za-z0-9-]+\.[A-Za-z0-9.-]*ts\.net/<magicdns>/g'; }

say "== 时间 / 内存 =="
date '+%F %T %z'
say "memorystatus_level: $(mem_level)"
ps -axo rss=,comm= | grep -E "paperclip-ops|postgres|node/${NODE_VERSION}" | grep -v grep \
    | awk '{s+=$1} END {print "Paperclip 相关进程数", NR, "合计 RSS KB", s}'

say "== 程序和实例 =="
say "装的版本: $("${NODE_BIN}/node" -p 'require(process.argv[1]).version' "${APP_DIR}/node_modules/paperclipai/package.json")"
say "node: ${NODE_BIN}/node $("${NODE_BIN}/node" -v)"
"${PY}" - "${INSTANCE_ROOT}" <<'PYEOF'
import json, os, sys
root = sys.argv[1]
ri = json.load(open(os.path.join(root, "runtime-info.json")))
print("runtime-info: instanceId=%s host=%s port=%s" % (ri.get("instanceId"), ri.get("host"), ri.get("port")))
cfg = json.load(open(os.path.join(root, "config.json")))
s = cfg["server"]
print("config server:", {k: s.get(k) for k in ("deploymentMode", "exposure", "bind", "host", "port", "allowedHostnames", "serveUi")})
print("config database: mode=%s port=%s" % (cfg["database"]["mode"], cfg["database"].get("embeddedPostgresPort")))
print("config telemetry=%s updates.checkEnabled=%s" % (cfg.get("telemetry", {}).get("enabled"), cfg.get("updates", {}).get("checkEnabled")))
PYEOF
say "实例目录: $(ls "${PAPERCLIP_HOME_DIR}/instances" | tr '\n' ' ')（ops 是新的，default 没动）"
[ -f "${DEFAULT_CONFIG}" ] && say "default config.json sha256 前 12 位: $(shasum -a 256 "${DEFAULT_CONFIG}" | cut -c1-12)"
[ -d "${HOME}/paperclip/.git" ] && say "~/paperclip HEAD: $(git -C "${HOME}/paperclip" rev-parse --short=9 HEAD)"

say "== 监听 =="
for port in "${SERVER_PORT}" "${PG_PORT}"; do
    /usr/sbin/lsof -nP -iTCP:"${port}" -sTCP:LISTEN | awk 'NR>1 {print $1, $9}' | sort -u
done

say "== LaunchAgent =="
lp=$(launchctl print "gui/$(id -u)/${LAUNCH_LABEL}" 2>&1)
printf '%s\n' "${lp}" | awk '/^\tstate =|^\tpath =|^\tlast exit code/ {sub(/^\t/, ""); print}'
envnames=$(printf '%s\n' "${lp}" | awk '/^\tenvironment = \{/ {f=1; next} f && /^\t\}/ {f=0} f {print $1}' | sort)
say "环境变量名: $(printf '%s\n' "${envnames}" | tr '\n' ' ')"
if printf '%s\n' "${envnames}" | grep -q '^ORCA_'; then say "环境里的 ORCA_*: 有（不对）"; else say "环境里的 ORCA_*: 没有"; fi
say "启动参数里清掉的变量: $(printf '%s\n' "${lp}" | awk '/^\targuments = \{/ {f=1; next} f && /^\t\}/ {f=0} f && prev == "-u" {printf "%s ", $1} f {prev = $1}')"
for p in $(pgrep -f "paperclipai/dist/index.js run --instance ${PAPERCLIP_INSTANCE_ID}"); do
    # ps -E 带出进程环境；只数变量名，不打印值。
    say "运行中进程环境里 ORCA_* 个数: $(ps -wwwE -o command= -p "${p}" | grep -oE '(^| )ORCA_[A-Z_]*=' | wc -l | tr -d ' ')"
done
say "launchctl getenv ORCA_DISPATCH_BOT 字节数:$(launchctl getenv ORCA_DISPATCH_BOT | wc -c | tr -d ' ')"
say "plist PAPERCLIP_PUBLIC_URL: $(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PAPERCLIP_PUBLIC_URL' "${LAUNCH_PLIST}" 2>/dev/null | mask || echo 未设)"
say "plist PAPERCLIP_API_URL: $(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PAPERCLIP_API_URL' "${LAUNCH_PLIST}")"
for tool in orca notify-run claude node; do
    say "LaunchAgent PATH 下 ${tool} -> $(env -i PATH="${LAUNCH_PATH}" /bin/sh -c "command -v ${tool}" || echo 找不到)"
done

say "== 主机名检查（private 模式）=="
code() { curl -s -o /dev/null -w '%{http_code}' -m 10 "$@"; }
say "Host: 127.0.0.1           -> $(code "${API_URL}/api/health")"
say "Host: evil.example        -> $(code -H 'Host: evil.example' "${API_URL}/api/health")"
say "X-Forwarded-Host: evil    -> $(code -H 'X-Forwarded-Host: evil.example' "${API_URL}/api/health")"

say "== agent / routine / 触发器（不打印 ID）=="
"${PY}" - <<PYEOF
import json, urllib.request, urllib.error
API = "${API_URL}/api"
def get(p):
    with urllib.request.urlopen(API + p, timeout=30) as r:
        return json.load(r)
def post_code(p, headers):
    req = urllib.request.Request(API + p, data=b"{}", method="POST", headers=dict(headers, **{"Content-Type": "application/json"}))
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
h = get("/health")
print("health: status=%s version=%s commit=%s mode=%s exposure=%s" % (h.get("status"), h.get("version"), (h.get("commit") or "")[:7], h.get("deploymentMode"), h.get("deploymentExposure")))
companies = get("/companies")
print("companies:", [c.get("name") for c in companies])
c = next(c for c in companies if c.get("name") == "${COMPANY_NAME}")
cid = c["id"]
print("company requireBoardApprovalForNewAgents:", c.get("requireBoardApprovalForNewAgents"))
agents = get("/companies/%s/agents" % cid)
print("agents:", [(a.get("name"), a.get("adapterType"), a.get("status")) for a in agents])
print("codex_local agent 个数:", sum(1 for a in agents if a.get("adapterType") == "codex_local"))
a = get("/agents/%s" % next(a["id"] for a in agents if a.get("name") == "${AGENT_NAME}"))
ac = a.get("adapterConfig") or {}
print("agent adapterConfig:", {k: ac.get(k) for k in ("engine", "dangerouslySkipPermissions", "model", "extraArgs", "cwd")})
print("agent runtimeConfig.heartbeat:", (a.get("runtimeConfig") or {}).get("heartbeat"))
print("agent budgetMonthlyCents=%s status=%s" % (a.get("budgetMonthlyCents"), a.get("status")))
runs = get("/companies/%s/heartbeat-runs" % cid)
print("heartbeat runs 条数:", len(runs if isinstance(runs, list) else runs.get("items", runs.get("runs", []))))
for r in get("/companies/%s/routines" % cid):
    d = get("/routines/%s" % r["id"])
    vs = d.get("variables") or []
    text = (d.get("title") or "") + (d.get("description") or "")
    print("routine「%s」status=%s concurrencyPolicy=%s 变量=%d 必填=%d 含date/timestamp占位=%s" % (
        d.get("title"), d.get("status"), d.get("concurrencyPolicy"), len(vs),
        sum(1 for v in vs if v.get("required")), "{{date}}" in text or "{{timestamp}}" in text))
    for t in d.get("triggers", []):
        print("  触发器 label=%s kind=%s signingMode=%s setupPending=%s enabled=%s" % (
            t.get("label"), t.get("kind"), t.get("signingMode"), t.get("setupPending"), t.get("enabled")))
        if t.get("kind") == "webhook" and t.get("publicId"):
            p = "/routine-triggers/public/%s/fire" % t["publicId"]
            print("  本机 POST 不带 bearer ->", post_code(p, {}))
            print("  本机 POST 带错 bearer ->", post_code(p, {"Authorization": "Bearer wrong-not-the-secret"}))
print("不存在的 publicId ->", post_code("/routine-triggers/public/%s/fire" % ("0" * 24), {}))
print("fire 后 heartbeat runs 条数:", len((lambda r: r if isinstance(r, list) else r.get("items", r.get("runs", [])))(get("/companies/%s/heartbeat-runs" % cid))))
PYEOF

say "== 文件 =="
for f in "${SECRETS_DIR}"/*.bearer "${SECRETS_DIR}"/*.url; do
    [ -e "${f}" ] || continue
    say "${f}: 权限 $(stat -f '%Lp' "${f}") 非空=$([ -s "${f}" ] && echo 是 || echo 否) 长度 $(wc -c <"${f}" | tr -d ' ')"
done
say "${SECRETS_DIR}: 权限 $(stat -f '%Lp' "${SECRETS_DIR}")"
say "设置文件 ${AGENT_SETTINGS}: 权限 $(stat -f '%Lp' "${AGENT_SETTINGS}")"
cat "${AGENT_SETTINGS}"

say "== Serve =="
/usr/local/bin/tailscale serve status 2>&1 | mask
[ -f "${PUBLIC_URL_FILE}" ] && say "public-url 文件: 有" || say "public-url 文件: 没有"
