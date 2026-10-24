#!/bin/bash
# S12 ② 触发转发程序（代替 Serve）：装程序和它的 LaunchAgent，把 Paperclip 的 PAPERCLIP_PUBLIC_URL 设成转发地址，
# 重启 Paperclip，再更新两个触发器的 .url 文件。失败方式见同目录 FAILURE-MODES.md（F<n>）。
# 用法（在 iMac 上）：install.sh          只打印计划和检查结果，不动手
#                     install.sh --apply  照做（可以重跑：已装的会重装成同一份，备份只在第一次做）
#                     install.sh --off    撤掉转发程序，PUBLIC_URL 和 .url 文件恢复成装之前的样子，重启 Paperclip
# tailnet 地址运行时取，屏幕上一律打码；不打印 bearer、publicId、ID。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/../config.sh"

mode=${1:-plan}
case "${mode}" in plan | --apply | --off) ;; *) echo "用法: $0 [--apply | --off]" >&2; exit 2 ;; esac
uid=$(id -u)
domain="gui/${uid}"
NODE="${NODE_BIN}/node"
say() { printf '%s\n' "$*"; }
die() { printf 'forwarder/install: %s\n' "$*" >&2; exit 1; }
mask() { sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<ip>/g; s/[0-9a-f]{24}/<publicId>/g'; }
loaded() { launchctl print "${domain}/${FWD_LABEL}" >/dev/null 2>&1; }
listeners() { /usr/sbin/lsof -nP -iTCP:"${FWD_PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1, $9}' | sort -u; }
health() { curl -s -o /dev/null -w '%{http_code}' -m 5 "${API_URL}/api/health" 2>/dev/null || true; }

wait_health() {
    for _ in $(seq 60); do
        [ "$(health)" = 200 ] && return 0
        sleep 2
    done
    return 1
}

restart_paperclip() {
    "${here}/../launchagent.sh" --apply 2>&1 | mask
    wait_health || die "Paperclip 重启后 120 秒内 health 不是 200，停下（看 ${INSTANCE_ROOT}/logs/launchd.err.log）"
    say "Paperclip health 200"
}

PUBLIC_BACKUP="${FWD_STATE}/public-url.before"
PUBLIC_NONE="${FWD_STATE}/public-url.none"

# ---------------- --off ----------------
if [ "${mode}" = --off ]; then
    say "== 撤掉转发程序 =="
    if loaded; then
        launchctl bootout "${domain}/${FWD_LABEL}" && say "已 bootout ${domain}/${FWD_LABEL}"
    else
        say "${domain}/${FWD_LABEL} 没加载"
    fi
    rm -f "${FWD_PLIST}" "${FWD_JS}"
    say "已删 ${FWD_PLIST} 和 ${FWD_JS}（日志 ${FWD_LOG_DIR} 留着）"

    # PUBLIC_URL：按装之前的记录还原（F32）。
    if [ -f "${PUBLIC_BACKUP}" ]; then
        install -m 600 "${PUBLIC_BACKUP}" "${PUBLIC_URL_FILE}"
        say "public-url 恢复成装之前的内容"
    elif [ -f "${PUBLIC_NONE}" ]; then
        rm -f "${PUBLIC_URL_FILE}"
        say "装之前没有 public-url，已删掉"
    else
        say "没有装之前的记录（没跑过 --apply），public-url 不动"
    fi
    restart_paperclip

    # .url 文件：还原备份。
    for slug in ops-system s12-drill; do
        b="${SECRETS_DIR}/${slug}.url.before-forwarder"
        if [ -f "${b}" ]; then
            mv -f "${b}" "${SECRETS_DIR}/${slug}.url"
            chmod 600 "${SECRETS_DIR}/${slug}.url"
            say "${slug}.url 恢复成装之前的内容"
        fi
    done
    rm -f "${PUBLIC_BACKUP}" "${PUBLIC_NONE}"

    sleep 2
    if [ -n "$(listeners)" ]; then
        say "8110 还有人在听（不对）:"; listeners | mask
        exit 1
    fi
    say "8110 没人在听"
    say "plist PAPERCLIP_PUBLIC_URL: $(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PAPERCLIP_PUBLIC_URL' "${LAUNCH_PLIST}" 2>/dev/null | mask || echo 未设)"
    exit 0
fi

# ---------------- 计划和检查（plan、--apply 都做）----------------
say "== 计划 =="
say "程序: ${here}/forwarder.js -> ${FWD_JS}"
say "LaunchAgent: ${FWD_LABEL} -> ${FWD_PLIST}（由 ${FWD_LABEL}.plist.template 渲染），launchctl bootstrap ${domain}"
say "监听: tailnet IPv4:${FWD_PORT}（程序运行时自己取）；上游: ${API_URL}"
say "日志: ${FWD_LOG_DIR}/forwarder.log"
say "然后: ${PUBLIC_URL_FILE} 写成 http://<tailnet-ip>:${FWD_PORT}，跑 ../launchagent.sh --apply 重启 Paperclip（设 PAPERCLIP_PUBLIC_URL）"
say "然后: ${SECRETS_DIR}/{ops-system,s12-drill}.url 写成 Paperclip 读回的新 webhookUrl（旧文件备份成 .url.before-forwarder）"

[ -f "${here}/forwarder.js" ] || die "找不到 ${here}/forwarder.js"
[ -f "${here}/${FWD_LABEL}.plist.template" ] || die "找不到 plist 模板"
nv=$("${NODE}" -v) || die "找不到 ${NODE}"
[ "${nv}" = "${NODE_VERSION}" ] || die "node 版本是 ${nv}，要 ${NODE_VERSION}"
say "node: ${NODE} ${nv}"
"${NODE}" --check "${here}/forwarder.js" || die "forwarder.js 语法检查不过"

ip4=$("${TIMEOUT}" 10 "${TS}" ip -4 2>/dev/null | head -1 || true)
"${PY}" - "${ip4}" <<'PYEOF' || die "tailnet IPv4 不对（取不到，或不在 100.64.0.0/10）"
import ipaddress, sys
a = ipaddress.ip_address(sys.argv[1])
assert a.version == 4 and a in ipaddress.ip_network("100.64.0.0/10")
PYEOF
/sbin/ifconfig | grep -F "inet ${ip4} " >/dev/null || die "tailnet 地址不在本机网卡上"
say "tailnet IPv4: <ip>（在 100.64.0.0/10 里，挂在本机网卡上）"
base="http://${ip4}:${FWD_PORT}"

cur=$(listeners)
if [ -n "${cur}" ] && ! loaded; then
    say "8110 已经有别的程序在听:"; printf '%s\n' "${cur}" | mask
    die "端口被占，不装（F27）"
fi
say "8110 现状: $([ -n "${cur}" ] && printf '%s' "${cur}" | mask | tr '\n' ' ' || echo 没人听)"
[ "$(health)" = 200 ] || die "Paperclip ${API_URL} health 不是 200，先把 Paperclip 起好"
say "Paperclip health 200"
launchctl print "${domain}/${LAUNCH_LABEL}" >/dev/null 2>&1 || die "Paperclip 的 LaunchAgent ${LAUNCH_LABEL} 没加载"
mem=$(mem_level)
say "memorystatus_level: ${mem}"
say "public-url 现状: $([ -s "${PUBLIC_URL_FILE}" ] && head -1 "${PUBLIC_URL_FILE}" | mask || echo 没有)"

if [ "${mode}" != --apply ]; then
    loaded && say "将先 bootout 已加载的 ${FWD_LABEL}"
    say "（只打印，未执行。加 --apply 照做）"
    exit 0
fi

# ---------------- --apply ----------------
[ "${mem}" -ge 20 ] || die "memorystatus_level=${mem} 低于 20，不装（F26）"

# 1) 程序
install -d -m 700 "${FWD_DIR}" "${FWD_STATE}" "${FWD_LOG_DIR}"
install -m 644 "${here}/forwarder.js" "${FWD_JS}"
say "已装 ${FWD_JS}（sha256 前 12 位 $(shasum -a 256 "${FWD_JS}" | cut -c1-12)）"

# 2) 渲染 plist 并核对（F23、F24、F25）
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT
sed -e "s#@LABEL@#${FWD_LABEL}#g" \
    -e "s#@HOME@#${HOME}#g" \
    -e "s#@NODE@#${NODE}#g" \
    -e "s#@SCRIPT@#${FWD_JS}#g" \
    -e "s#@DIR@#${FWD_DIR}#g" \
    -e "s#@LOG_DIR@#${FWD_LOG_DIR}#g" \
    "${here}/${FWD_LABEL}.plist.template" >"${tmp}"
grep -q '@[A-Z_]*@' "${tmp}" && die "plist 里还有没替换的占位符"
plutil -lint "${tmp}" >/dev/null || die "plist 格式不对"
"${PY}" - "${tmp}" "${HOME}" "${NODE}" "${FWD_JS}" <<'PYEOF' || die "plist 核对不过"
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
home, node, js = sys.argv[2:5]
want = ["/usr/bin/env", "-i", "HOME=" + home, "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=en_US.UTF-8",
        node, "--max-old-space-size=32", js]
assert d["ProgramArguments"] == want, "ProgramArguments 和期望的不一致"
assert not any("--dev" in a for a in d["ProgramArguments"]), "参数里有 --dev"
assert not any(k.startswith("ORCA_") for k in d.get("EnvironmentVariables", {})), "EnvironmentVariables 里有 ORCA_"
assert d["RunAtLoad"] is True and d["KeepAlive"] is True and d["ThrottleInterval"] == 30
print("plist 核对通过：env -i 起 node，参数逐项和期望一致，没有 --dev，没有 ORCA_ 变量，RunAtLoad/KeepAlive/ThrottleInterval=30")
PYEOF

# 3) 加载
if loaded; then
    launchctl bootout "${domain}/${FWD_LABEL}" || true
    sleep 2
fi
install -m 644 "${tmp}" "${FWD_PLIST}"
launchctl bootstrap "${domain}" "${FWD_PLIST}"
say "已 bootstrap ${domain} ${FWD_PLIST}（$(date '+%F %T %z')）"

# 4) 只许听 tailnet IPv4:8110（F1）
ok=""
for _ in $(seq 20); do
    cur=$(listeners)
    if [ "${cur}" = "node ${ip4}:${FWD_PORT}" ]; then ok=1; break; fi
    sleep 1
done
if [ -z "${ok}" ]; then
    say "8110 的监听不对:"; listeners | mask
    launchctl bootout "${domain}/${FWD_LABEL}" || true
    die "已 bootout 转发程序，停下"
fi
say "8110 只有一个监听: node <ip>:${FWD_PORT}"
code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "${base}/" || true)
[ "${code}" = 404 ] || die "本机打转发地址的 / 应是 404，实际 ${code}"
say "本机打转发地址 GET / -> 404"

# 5) PUBLIC_URL：第一次装时记下原状，然后写转发地址（F21、F32）
if [ ! -f "${PUBLIC_BACKUP}" ] && [ ! -f "${PUBLIC_NONE}" ]; then
    if [ -f "${PUBLIC_URL_FILE}" ]; then
        install -m 600 "${PUBLIC_URL_FILE}" "${PUBLIC_BACKUP}"
        say "已备份装之前的 public-url"
    else
        : >"${PUBLIC_NONE}"
        say "装之前没有 public-url（记下了）"
    fi
fi
(umask 077; printf '%s\n' "${base}" >"${PUBLIC_URL_FILE}")
chmod 600 "${PUBLIC_URL_FILE}"
say "public-url 写成 http://<ip>:${FWD_PORT}"
restart_paperclip

# 6) .url 文件：从 Paperclip 读回新的 webhookUrl，核对后写入（F22、F33）
"${PY}" - "${API_URL}" "${COMPANY_NAME}" "${SECRETS_DIR}" "${base}" "${FWD_PATH_RE}" <<'PYEOF'
import json, os, re, shutil, sys, urllib.request
api, company_name, secrets_dir, base, path_re = sys.argv[1:6]
def get(p):
    with urllib.request.urlopen(api + "/api" + p, timeout=30) as r:
        return json.load(r)
company = next(c for c in get("/companies") if c.get("name") == company_name)
found = {}
for r in get("/companies/%s/routines" % company["id"]):
    for t in get("/routines/%s" % r["id"]).get("triggers", []):
        label = t.get("label") or ""
        if t.get("kind") == "webhook" and label.endswith("-bearer") and not t.get("archived"):
            found[label[: -len("-bearer")]] = t.get("webhookUrl") or ""
for slug in ("ops-system", "s12-drill"):
    url = found.get(slug, "")
    prefix = base + "/api/routine-triggers/public/"
    if not url.startswith(prefix) or not re.match(path_re, url[len(base):]):
        raise SystemExit("%s 的 webhookUrl 不是转发地址开头或路径不对，停下（PUBLIC_URL 没生效？）" % slug)
    dst = os.path.join(secrets_dir, slug + ".url")
    bak = dst + ".before-forwarder"
    if os.path.exists(dst) and not os.path.exists(bak):
        shutil.copy2(dst, bak)
        os.chmod(bak, 0o600)
    fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(url + "\n")
    os.chmod(dst, 0o600)
    print("已更新 %s.url：http://<ip>:%s/api/routine-triggers/public/<publicId>/fire（权限 600）" % (slug, base.rsplit(":", 1)[1]))
PYEOF

say "== 装好了 =="
say "读回（在 MBA 的仓库里）：paperclip/imac/forwarder/readback-from-mba.sh"
say "两台 wake env 里的 URL 这次没改，要 Zack 批了再改（README「待办」）"
