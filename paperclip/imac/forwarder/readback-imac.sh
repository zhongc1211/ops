#!/bin/bash
# S12 ② 转发程序装好以后在 iMac 上的读回（只读）。由 MBA 的 readback-from-mba.sh 经 ssh 调用，也可以单独跑。
# 用法：readback-imac.sh runs       只打印 company 下 heartbeat runs 的条数
#       readback-imac.sh publicid   只打印「S12 演练叫醒（测试）」触发器的 publicId（给 MBA 的 probe 用，不落盘）
#       readback-imac.sh checks     监听、LaunchAgent、环境、日志、没设 PUBLIC_URL、.url 文件、本机和局域网地址打 8110
# 不打印 bearer、IP、ID、PID；.url 文件只和 Paperclip 读回的 webhookUrl 比较（路径相同、origin 是转发地址），不打印内容。
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/../config.sh"

say() { printf '%s\n' "$*"; }
mask() { sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<ip>/g; s/[0-9a-f]{24}/<publicId>/g'; }

api_py() {
    "${PY}" - "${API_URL}" "${COMPANY_NAME}" "${ROUTINE_TEST_TITLE}" "$1" <<'PYEOF'
import json, sys, urllib.request
api, company_name, test_title, what = sys.argv[1:5]
def get(p):
    with urllib.request.urlopen(api + "/api" + p, timeout=30) as r:
        return json.load(r)
c = next(c for c in get("/companies") if c.get("name") == company_name)
if what == "runs":
    runs = get("/companies/%s/heartbeat-runs" % c["id"])
    print(len(runs if isinstance(runs, list) else runs.get("items", runs.get("runs", []))))
elif what == "publicid":
    r = next(r for r in get("/companies/%s/routines" % c["id"]) if r.get("title") == test_title)
    t = next(t for t in get("/routines/%s" % r["id"])["triggers"] if t.get("kind") == "webhook" and t.get("publicId"))
    print(t["publicId"])
PYEOF
}

case "${1:-}" in
runs) api_py runs; exit ;;
publicid) api_py publicid; exit ;;
checks) ;;
*) echo "用法: $0 runs|publicid|checks" >&2; exit 2 ;;
esac

date '+%F %T %z'
say "memorystatus_level: $(mem_level)"
ip4=$("${TS}" ip -4 2>/dev/null | head -1)

say "== 监听（F1）=="
/usr/sbin/lsof -nP -iTCP:"${FWD_PORT}" -sTCP:LISTEN | awk 'NR>1 {print $1, $9}' | sort -u | mask
n=$(/usr/sbin/lsof -nP -iTCP:"${FWD_PORT}" -sTCP:LISTEN | awk 'NR>1 {print $9}' | sort -u)
[ "${n}" = "${ip4}:${FWD_PORT}" ] && say "PASS  8110 只听 tailnet IPv4" || say "FAIL  8110 的监听不是只有 tailnet IPv4"

code() { curl -s -o /dev/null -w '%{http_code}' -m 5 "$@" 2>/dev/null; }
lan=""
for ifc in en0 en1 en2; do lan=$(ipconfig getifaddr "${ifc}" 2>/dev/null) && [ -n "${lan}" ] && break; done
for target in "127.0.0.1" "[::1]" "${lan:-}"; do
    [ -n "${target}" ] || { say "没有局域网地址，跳过"; continue; }
    c=$(code -X POST "http://${target}:${FWD_PORT}/")
    label=$([ "${target}" = "${lan}" ] && echo "局域网地址" || echo "${target}")
    [ "${c}" = 000 ] && say "PASS  ${label}:8110 连不上（000）" || say "FAIL  ${label}:8110 -> ${c}"
done

say "== LaunchAgent（F3、F23、F24、F25）=="
lp=$(launchctl print "gui/$(id -u)/${FWD_LABEL}" 2>&1)
printf '%s\n' "${lp}" | awk '/^\tstate =|^\truns =|^\tlast exit code/ {sub(/^\t/, ""); print}'
"${PY}" - "${FWD_PLIST}" "${HOME}" "${NODE_BIN}/node" "${FWD_JS}" <<'PYEOF'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
home, node, js = sys.argv[2:5]
want = ["/usr/bin/env", "-i", "HOME=" + home, "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=en_US.UTF-8",
        node, "--max-old-space-size=32", js]
print(("PASS" if d["ProgramArguments"] == want else "FAIL") + "  ProgramArguments 和期望逐项相等（env -i，node v24.22.1，没有 --dev）")
print(("PASS" if not any(k.startswith("ORCA_") for k in d.get("EnvironmentVariables", {})) else "FAIL") + "  plist 里没有 ORCA_ 变量")
print("RunAtLoad=%s KeepAlive=%s ThrottleInterval=%s" % (d.get("RunAtLoad"), d.get("KeepAlive"), d.get("ThrottleInterval")))
PYEOF
for p in $(pgrep -f "${FWD_JS}"); do
    say "运行中转发程序 comm: $(ps -o comm= -p "${p}" | sed "s#${HOME}#~#")，RSS $(ps -o rss= -p "${p}" | tr -d ' ') KB"
    say "运行中转发程序环境里 ORCA_* 个数: $(ps -wwwE -o command= -p "${p}" | grep -oE '(^| )ORCA_[A-Z_]*=' | wc -l | tr -d ' ')"
done

say "== 日志（F17、F28）=="
log="${FWD_LOG_DIR}/forwarder.log"
if [ -f "${log}" ]; then
    say "${log}: $(wc -l <"${log}" | tr -d ' ') 行，$(wc -c <"${log}" | tr -d ' ') 字节，权限 $(stat -f '%Lp' "${log}")"
    for pat in 'Bearer' '[0-9a-f]{24}' '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' 'forwarder-probe' 'evil'; do
        k=$(grep -cE "${pat}" "${log}")
        [ "${k}" = 0 ] && say "PASS  日志里 /${pat}/ 0 次" || say "FAIL  日志里 /${pat}/ ${k} 次"
    done
    say "最后 5 行:"; tail -5 "${log}"
else
    say "FAIL  没有 ${log}"
fi
say "launchd.err.log: $(wc -l <"${FWD_LOG_DIR}/launchd.err.log" 2>/dev/null | tr -d ' ') 行"

say "== 不设 PUBLIC_URL、.url 文件（F21、F22、F34–F38）=="
pu=$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PAPERCLIP_PUBLIC_URL' "${LAUNCH_PLIST}" 2>/dev/null)
[ -z "${pu}" ] && say "PASS  Paperclip plist 里没有 PAPERCLIP_PUBLIC_URL" \
    || say "FAIL  Paperclip plist PAPERCLIP_PUBLIC_URL = $(printf '%s' "${pu}" | mask)"
[ -e "${PUBLIC_URL_FILE}" ] && say "FAIL  实例目录里有 public-url" || say "PASS  实例目录里没有 public-url"
say "Paperclip plist PAPERCLIP_API_URL: $(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PAPERCLIP_API_URL' "${LAUNCH_PLIST}")"
# .url 只和 Paperclip 读回的 webhookUrl 比较，不打印内容：路径相同，origin 是 http://<当前 tailnet-ip>:8110。
"${PY}" - "${API_URL}" "${COMPANY_NAME}" "${SECRETS_DIR}" "http://${ip4}:${FWD_PORT}" "${FWD_PATH_RE}" <<'PYEOF'
import json, os, re, stat, sys, urllib.parse, urllib.request
api, company_name, secrets_dir, fwd_origin, path_re = sys.argv[1:6]
def get(p):
    with urllib.request.urlopen(api + "/api" + p, timeout=30) as r:
        return json.load(r)
c = next(c for c in get("/companies") if c.get("name") == company_name)
for r in get("/companies/%s/routines" % c["id"]):
    for t in get("/routines/%s" % r["id"]).get("triggers", []):
        label = t.get("label") or ""
        if t.get("kind") != "webhook" or not label.endswith("-bearer"):
            continue
        slug = label[: -len("-bearer")]
        path = os.path.join(secrets_dir, slug + ".url")
        on_disk = open(path).read().strip() if os.path.exists(path) else ""
        w = urllib.parse.urlsplit(t.get("webhookUrl") or "")
        d = urllib.parse.urlsplit(on_disk)
        same_path = bool(re.fullmatch(path_re, w.path)) and d.path == w.path and not (d.query or d.fragment)
        fwd = "%s://%s" % (d.scheme, d.netloc) == fwd_origin
        mode = oct(stat.S_IMODE(os.stat(path).st_mode))[2:] if os.path.exists(path) else "-"
        print("%s  %s.url 的路径和 webhookUrl 的路径相同" % ("PASS" if same_path else "FAIL", slug))
        print("%s  %s.url 的 origin 是 http://<tailnet-ip>:8110" % ("PASS" if fwd else "FAIL", slug))
        print("%s  %s.url 权限 600（实际 %s）" % ("PASS" if mode == "600" else "FAIL", slug, mode))
        print("%s  webhookUrl 是本机地址（没设 PUBLIC_URL）" % ("PASS" if "%s://%s" % (w.scheme, w.netloc) == api else "FAIL"))
PYEOF
"${PY}" -c 'import json,sys; s=json.load(open(sys.argv[1]))["server"]; print("config.json allowedHostnames 条数:", len(s.get("allowedHostnames") or []))' "${CONFIG_PATH}"
