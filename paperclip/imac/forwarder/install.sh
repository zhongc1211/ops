#!/bin/bash
# S12 ② 触发转发程序（代替 Serve）：装程序和它的 LaunchAgent，再把两个触发器 .url 文件里的 origin 换成转发地址。
# 不设 PAPERCLIP_PUBLIC_URL，不碰 Paperclip 的 LaunchAgent、public-url 和 Paperclip 进程，对 Paperclip 只发 GET。
# 失败方式见同目录 FAILURE-MODES.md（F<n>）。
# 用法（在 iMac 上）：install.sh          只打印计划和检查结果，不动手
#                     install.sh --apply  照做（可以重跑：已装的会重装成同一份，.url 的备份只在第一次做）
#                     install.sh --off    撤掉转发程序，.url 从备份还原，核对 8110 没人听
# tailnet 地址运行时取，屏幕上一律打码；不打印 bearer、publicId、ID，.url 的内容只由脚本读写、不打印。
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
# 没人听时 lsof 退出码是 1；在 pipefail 加 set -e 下会让 cur=$(listeners) 直接退出整个脚本（FAILURE-MODES C3）。
listeners() { { /usr/sbin/lsof -nP -iTCP:"${FWD_PORT}" -sTCP:LISTEN 2>/dev/null || true; } | awk 'NR>1 {print $1, $9}' | sort -u; }
health() { curl -s -o /dev/null -w '%{http_code}' -m 5 "${API_URL}/api/health" 2>/dev/null || true; }

# .url 文件：plan 只报告现状；apply 核对后写入；restore 从备份还原；verify-off 核对已还原。
# 参数：动作 转发 origin（restore、verify-off 时不用）。只对 Paperclip 发 GET；屏幕上不出 .url 的内容。
url_py() {
    "${PY}" - "$1" "${API_URL}" "${COMPANY_NAME}" "${SECRETS_DIR}" "${2:-}" "${FWD_PATH_RE}" <<'PYEOF'
import json, os, re, stat, sys, urllib.parse, urllib.request
action, api, company_name, secrets_dir, fwd_origin, path_re = sys.argv[1:7]
SLUGS = ("ops-system", "s12-drill")
BAK = ".before-forwarder"

def dst_of(slug):
    return os.path.join(secrets_dir, slug + ".url")

def mode_of(p):
    return oct(stat.S_IMODE(os.stat(p).st_mode))[2:]

def read(p):
    with open(p) as f:
        return f.read().strip()

def write_600(path, text):
    # F35、F36：先写同目录临时文件（600），fsync 后原子换名，不会留下半个文件。
    tmp = path + ".tmp-forwarder"
    if os.path.exists(tmp):
        os.unlink(tmp)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text + "\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    os.chmod(path, 0o600)

if action == "restore":
    # 不需要 Paperclip 在跑。
    for slug in SLUGS:
        dst, bak = dst_of(slug), dst_of(slug) + BAK
        if os.path.exists(bak):
            os.replace(bak, dst)
            os.chmod(dst, 0o600)
            print("%s.url 已从备份还原（权限 %s）" % (slug, mode_of(dst)))
        else:
            print("%s.url 没有备份，不动" % slug)
    sys.exit(0)

def get(p):
    with urllib.request.urlopen(api + "/api" + p, timeout=30) as r:
        return json.load(r)

companies = [c for c in get("/companies") if c.get("name") == company_name]
if len(companies) != 1:
    sys.exit("停下：名为「%s」的 company 不是恰好一个" % company_name)
found = {}
for r in get("/companies/%s/routines" % companies[0]["id"]):
    for t in get("/routines/%s" % r["id"]).get("triggers", []):
        label = t.get("label") or ""
        if t.get("kind") == "webhook" and label.endswith("-bearer") and not t.get("archived"):
            found.setdefault(label[: -len("-bearer")], []).append(t.get("webhookUrl") or "")

# F37：读回的 webhookUrl 必须是本机 origin 加合规路径，两个触发器都在、各只有一个。
local, paths, bad = {}, {}, []
for slug in SLUGS:
    urls = found.get(slug, [])
    if len(urls) != 1:
        bad.append("%s 的 bearer 触发器有 %d 个，应是 1 个" % (slug, len(urls)))
        continue
    u = urllib.parse.urlsplit(urls[0])
    origin = "%s://%s" % (u.scheme, u.netloc)
    if origin != api:
        bad.append("%s 读回的 webhookUrl 不是本机地址（PUBLIC_URL 被设了？）" % slug)
    elif not re.fullmatch(path_re, u.path) or urls[0] != origin + u.path:
        bad.append("%s 读回的 webhookUrl 路径不合规则（或带查询串、#）" % slug)
    else:
        local[slug], paths[slug] = urls[0], u.path
if bad:
    sys.exit("停下，什么都没写：\n  " + "\n  ".join(bad))

def describe(p):
    if not os.path.exists(p):
        return "没有"
    v = read(p)
    kind = "本机地址" if v in local.values() else ("转发地址" if fwd_origin and v.startswith(fwd_origin + "/") else "别的内容")
    return "%s，权限 %s" % (kind, mode_of(p))

if action == "plan":
    for slug in SLUGS:
        dst = dst_of(slug)
        print("%s: webhookUrl 是本机地址、路径合规则；.url 现在是%s；备份 %s" % (slug, describe(dst), describe(dst + BAK)))
    sys.exit(0)

if action == "verify-off":
    # F32：--off 以后每个 .url 都应是装之前的本机地址，权限 600。
    failed = 0
    for slug in SLUGS:
        dst = dst_of(slug)
        ok = os.path.exists(dst) and read(dst) == local[slug] and mode_of(dst) == "600"
        failed |= not ok
        print("%s  %s.url 是 Paperclip 读回的本机地址、权限 600（现在是%s）" % ("PASS" if ok else "FAIL", slug, describe(dst)))
    sys.exit(1 if failed else 0)

assert action == "apply" and fwd_origin
# F40：没有备份时，现在的 .url 必须正好是本机的 webhookUrl，才能当成「装之前」备份下来。两个都核对完才写（F35）。
for slug in SLUGS:
    dst, bak = dst_of(slug), dst_of(slug) + BAK
    if os.path.exists(bak):
        if read(bak) != local[slug]:
            sys.exit("停下，什么都没写：%s.url%s 不是 Paperclip 读回的本机地址（%s）" % (slug, BAK, describe(bak)))
    elif not (os.path.exists(dst) and read(dst) == local[slug]):
        sys.exit("停下，什么都没写：%s.url 没有备份，现在的内容也不是 Paperclip 读回的本机地址（%s）" % (slug, describe(dst)))
for slug in SLUGS:
    dst, bak = dst_of(slug), dst_of(slug) + BAK
    if not os.path.exists(bak):
        write_600(bak, read(dst))
        print("已备份 %s.url -> %s.url%s（权限 %s）" % (slug, slug, BAK, mode_of(bak)))
    new = fwd_origin + paths[slug]  # F34：只换 origin，路径来自 Paperclip
    write_600(dst, new)
    ok = read(dst) == new and mode_of(dst) == "600"
    print("%s  %s.url 写成 http://<tailnet-ip>:%s/api/routine-triggers/public/<publicId>/fire，读回相同、权限 %s" % (
        "PASS" if ok else "FAIL", slug, fwd_origin.rsplit(":", 1)[1], mode_of(dst)))
    if not ok:
        sys.exit("停下：%s.url 读回不对" % slug)
PYEOF
}

# F21：Paperclip 带着 PUBLIC_URL（或者下次重启会带上）不是这一轮预期的状态，发现就停下。
check_no_public_url() {
    local bad="" pu
    pu=$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PAPERCLIP_PUBLIC_URL' "${LAUNCH_PLIST}" 2>/dev/null || true)
    if [ -n "${pu}" ]; then
        say "Paperclip plist 里有 PAPERCLIP_PUBLIC_URL=$(printf '%s' "${pu}" | mask)"
        bad=1
    fi
    if [ -e "${PUBLIC_URL_FILE}" ]; then
        say "实例目录里有 public-url: $(head -1 "${PUBLIC_URL_FILE}" | mask)"
        bad=1
    fi
    [ -z "${bad}" ] || die "这一轮不设 PAPERCLIP_PUBLIC_URL，上面的状态不是预期的，停下，什么都没做（F21）"
    say "Paperclip plist 里没有 PAPERCLIP_PUBLIC_URL，实例目录里没有 public-url"
}

# ---------------- --off ----------------
if [ "${mode}" = --off ]; then
    say "== 撤掉转发程序（不碰 Paperclip）=="
    if loaded; then
        launchctl bootout "${domain}/${FWD_LABEL}" && say "已 bootout ${domain}/${FWD_LABEL}"
    else
        say "${domain}/${FWD_LABEL} 没加载"
    fi
    rm -f "${FWD_PLIST}" "${FWD_JS}"
    say "已删 ${FWD_PLIST} 和 ${FWD_JS}（日志 ${FWD_LOG_DIR} 留着）"
    url_py restore

    sleep 2
    rc=0
    if [ -n "$(listeners)" ]; then
        say "FAIL  8110 还有人在听:"; listeners | mask
        rc=1
    else
        say "PASS  8110 没人在听"
    fi
    if [ "$(health)" = 200 ]; then
        url_py verify-off || rc=1
    else
        say "FAIL  Paperclip health 不是 200，没法核对 .url 是否还原"
        rc=1
    fi
    exit "${rc}"
fi

# ---------------- 计划和检查（plan、--apply 都做）----------------
say "== 计划 =="
say "程序: ${here}/forwarder.js -> ${FWD_JS}"
say "LaunchAgent: ${FWD_LABEL} -> ${FWD_PLIST}（由 ${FWD_LABEL}.plist.template 渲染），launchctl bootstrap ${domain}"
say "监听: tailnet IPv4:${FWD_PORT}（程序运行时自己取）；上游: ${API_URL}"
say "日志: ${FWD_LOG_DIR}/forwarder.log"
say "然后: ${SECRETS_DIR}/{ops-system,s12-drill}.url 的 origin 换成 http://<tailnet-ip>:${FWD_PORT}，路径取自 Paperclip 读回的 webhookUrl（第一次先备份成 .url.before-forwarder）"
say "不做: 不设 PAPERCLIP_PUBLIC_URL，不写 public-url，不跑 launchagent.sh，不重启 Paperclip"

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
check_no_public_url
mem=$(mem_level)
say "memorystatus_level: ${mem}"
url_py plan "${base}" || die ".url 的预检不过"

if [ "${mode}" != --apply ]; then
    loaded && say "将先 bootout 已加载的 ${FWD_LABEL}"
    say "（只打印，未执行。加 --apply 照做）"
    exit 0
fi

# ---------------- --apply ----------------
[ "${mem}" -ge 20 ] || die "memorystatus_level=${mem} 低于 20，不装（F26）"

# 1) 程序
install -d -m 700 "${FWD_DIR}" "${FWD_LOG_DIR}"
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

# 5) .url 文件：origin 换成转发地址（F22、F34–F37、F40）
url_py apply "${base}" || die ".url 没写好，停下（已写好的是完整的新地址，备份还在；可以重跑 --apply 或跑 --off）"

say "== 装好了 =="
say "读回（在 MBA 的仓库里）：paperclip/imac/forwarder/readback-from-mba.sh"
say "两台 wake env 里的 URL 这次没改，要 Zack 批了再改（README「待办」）"
