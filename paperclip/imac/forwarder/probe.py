"""S12 ② 转发程序的拒绝测试，用原始 socket 逐字节发请求（不经 curl 规范化路径）。

readback-from-mba.sh（打 iMac 上装好的程序）和 selfcheck-mba.sh（打 MBA 本机的自查实例）都用它。
- 只用错的 bearer（每次现编）或不带 bearer，从不读、从不用正确的 bearer。
- publicId 从环境变量 PROBE_PUBLIC_ID 读，输出里一律写成 <id>；地址只写 <host>。
- 每项一行：PASS/FAIL、项目名、期望、实际。最后一行是合计；有 FAIL 时退出码 1。
用法：python3 -I probe.py --host H --port P --mode readback|selfcheck [--upstream-log F] [--down-port P2]
对照的失败方式编号（F<n>）见 FAILURE-MODES.md。
"""
import argparse
import json
import os
import re
import secrets
import socket
import sys
import time

ap = argparse.ArgumentParser()
ap.add_argument("--host", required=True)
ap.add_argument("--port", type=int, required=True)
ap.add_argument("--mode", choices=["readback", "selfcheck"], required=True)
ap.add_argument("--upstream-log", help="selfcheck：替身上游记录收到的请求的文件")
ap.add_argument("--down-port", type=int, help="selfcheck：上游指向没人听的端口的另一个转发实例")
args = ap.parse_args()

PID = os.environ.get("PROBE_PUBLIC_ID", "")
if not re.fullmatch(r"[0-9a-f]{24}", PID):
    sys.exit("PROBE_PUBLIC_ID 不是 24 位小写十六进制")
FIRE = "/api/routine-triggers/public/%s/fire" % PID
WRONG = "Bearer " + secrets.token_hex(24)
BODY = json.dumps({"bot": "forwarder-probe", "status": "probe", "note": "forwarder rejection test, wrong bearer"}).encode()
FIXED_404 = b"not found\n"

results = []


def mask(s):
    return s.replace(PID, "<id>").replace(PID.upper(), "<ID>")


def build(method, target, headers=(), body=b"", version="HTTP/1.1", host=True, cl=True):
    lines = ["%s %s %s" % (method, target, version)]
    if host:
        lines.append("Host: %s:%d" % (args.host, args.port))
    lines += list(headers)
    if cl:
        lines.append("Content-Length: %d" % len(body))
    return ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1") + body


def post(target=FIRE, headers=("Content-Type: application/json", "Authorization: " + WRONG), body=BODY, **kw):
    return build("POST", target, headers, body, **kw)


def exchange(raw, timeout=25.0, expect100=False, body=b"", port=None):
    """发 raw，读到对方关连接为止。返回 dict：status（最后一个非 100 的状态码，None 表示没回）、body、got100、responses、ms。"""
    t0 = time.monotonic()
    data = b""
    got100 = False
    try:
        s = socket.create_connection((args.host, port or args.port), timeout=timeout)
    except OSError as e:
        return {"status": None, "error": type(e).__name__, "ms": int((time.monotonic() - t0) * 1000)}
    try:
        s.sendall(raw)
        if expect100:
            s.settimeout(3)
            try:
                first = s.recv(65536)
            except socket.timeout:
                first = b""
            data += first
            if first.startswith(b"HTTP/1.1 100"):
                got100 = True
                s.sendall(body)
            s.settimeout(timeout)
        while True:
            try:
                chunk = s.recv(65536)
            except (ConnectionResetError, BrokenPipeError):
                break
            if not chunk:
                break
            data += chunk
    except socket.timeout:
        pass
    finally:
        s.close()
    ms = int((time.monotonic() - t0) * 1000)
    statuses = [int(m) for m in re.findall(rb"(?:^|\r\n)HTTP/1\.[01] (\d{3})", data)]
    finals = [c for c in statuses if c != 100]
    resp_body = data.split(b"\r\n\r\n")[-1] if finals else b""
    return {"status": finals[0] if finals else None, "responses": len(finals), "got100": got100 or 100 in statuses,
            "body": resp_body, "raw": data, "ms": ms}


def check(name, ok, want, got):
    results.append(ok)
    print("%s  %s | 期望 %s | 实际 %s" % ("PASS" if ok else "FAIL", mask(name), want, mask(str(got))), flush=True)


def expect(name, raw, want, fixed_body=None, **kw):
    r = exchange(raw, **kw)
    ok = r["status"] == want
    if ok and want == 404 and fixed_body is not False:
        ok = r["body"] == FIXED_404  # 404 必须是转发程序自己回的固定正文，不是上游的
    if ok and r.get("responses", 0) > 1:
        ok = False
    got = "%s%s" % (r["status"], "" if r["status"] != 404 else (" 固定正文" if r["body"] == FIXED_404 else " 非固定正文"))
    if r.get("responses", 0) > 1:
        got += " 回了 %d 个响应" % r["responses"]
    check(name, ok, want, got)
    return r


# ---- 应转给上游、由 Paperclip（或替身）回 401 的 ----
expect("POST 触发路径 不带 bearer", post(headers=("Content-Type: application/json",)), 401)
expect("POST 触发路径 带错 bearer", post(), 401)
expect("POST 触发路径 带错 bearer + 伪造 X-Forwarded-Host（F13）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "X-Forwarded-Host: evil.example")), 401)
expect("POST 触发路径 带错 bearer + 伪造 Host（F13）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG), host=False)
       .replace(b"\r\nContent-Length", b"\r\nHost: evil.example\r\nContent-Length", 1), 401)
expect("POST 触发路径 带错 bearer + Forwarded、X-Forwarded-For、Cookie（F12）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Forwarded: for=203.0.113.4;host=evil",
                     "X-Forwarded-For: 203.0.113.4", "X-Forwarded-Proto: https", "Cookie: a=b")), 401)
r = expect("POST 触发路径 带错 bearer + Expect: 100-continue（F10）",
           post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Expect: 100-continue"), body=b"")
           .replace(b"Content-Length: 0", b"Content-Length: %d" % len(BODY)), 401, expect100=True, body=BODY)
check("  上一项先收到 100 Continue", bool(r.get("got100")), True, r.get("got100"))

# ---- 非触发路径、方法、版本：转发程序自己回 404 ----
for path in ("/", "/api/health", "/api/companies"):
    expect("GET %s" % path, build("GET", path, cl=False), 404)
expect("POST /api/companies", post(target="/api/companies"), 404)
for m in ("GET", "HEAD", "PUT", "PATCH", "DELETE", "OPTIONS"):
    want_body = None if m != "HEAD" else False  # HEAD 的响应不带正文，只看状态码
    expect("%s 触发路径（F6）" % m, build(m, FIRE, ("Authorization: " + WRONG,)), 404, fixed_body=want_body)
expect("POST 触发路径 HTTP/1.0（F7）", post(version="HTTP/1.0"), 404)

variants = [
    ("结尾多一个斜杠", FIRE + "/"),
    ("少 /fire", "/api/routine-triggers/public/%s" % PID),
    ("只有前缀带斜杠", "/api/routine-triggers/public/"),
    ("只有前缀不带斜杠", "/api/routine-triggers/public"),
    ("publicId 大写", "/api/routine-triggers/public/%s/fire" % PID.upper()),
    ("路径大写 /API", "/API/routine-triggers/public/%s/fire" % PID),
    ("FIRE 大写", "/api/routine-triggers/public/%s/FIRE" % PID),
    ("查询串", FIRE + "?x=1"),
    ("空查询串", FIRE + "?"),
    ("带 #", FIRE + "#frag"),
    ("开头双斜杠", "/" + FIRE),
    ("中间双斜杠", FIRE.replace("/routine-triggers", "//routine-triggers")),
    ("../ 回到 fire", FIRE + "/../fire"),
    ("../../health", "/api/routine-triggers/public/../../health"),
    ("%2e%2e 编码的点", "/api/routine-triggers/public/%2e%2e/%2e%2e/health"),
    ("%2F 编码的斜杠（前）", "/api/routine-triggers/public%%2F%s%%2Ffire" % PID),
    ("%2F 编码的斜杠（后）", "/api/routine-triggers/public/%s%%2Ffire" % PID),
    ("%65 编码的字母", "/api/routine-triggers/public/%s/fir%%65" % PID),
    ("编码的 publicId 首字", "/api/routine-triggers/public/%%%02x%s/fire" % (ord(PID[0]), PID[1:])),
    ("23 位 publicId", "/api/routine-triggers/public/%s/fire" % PID[:23]),
    ("25 位 publicId", "/api/routine-triggers/public/%s0/fire" % PID),
    ("绝对形式请求目标", "http://127.0.0.1:3110" + FIRE),
    ("绝对形式请求目标（转发地址）", "http://%s:%d%s" % (args.host, args.port, FIRE)),
    ("反斜杠", FIRE.replace("/fire", "\\fire")),
    ("分号参数", FIRE + ";x=1"),
    ("超长路径（6000 字节，头未超限）", FIRE + "/" + "a" * 6000),
    ("超长路径（超过 8 KiB 头上限）", FIRE + "/" + "a" * 9000),
]
for name, target in variants:
    expect("路径变体：%s（F5）" % name, post(target=target), 404)

# ---- 走私、头、正文（F8–F12、F15）----
expect("Transfer-Encoding: chunked（F9）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Transfer-Encoding: chunked"),
            body=b"%x\r\n%s\r\n0\r\n\r\n" % (len(BODY), BODY), cl=False), 404)
expect("Transfer-Encoding + Content-Length 同时带（F8）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Transfer-Encoding: chunked"),
            body=b"0\r\n\r\n"), 404)
expect("两个 Content-Length（F8）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Content-Length: %d" % len(BODY))), 404)
expect("两个 Authorization（F12）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Authorization: " + WRONG)), 404)
expect("Expect: 100-continue 打非触发路径，不该回 100（F10）",
       build("POST", "/api/companies", ("Content-Type: application/json", "Expect: 100-continue")), 404)
expect("Expect: 其它值（F10）",
       post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Expect: something-else")), 404)
big = b'{"pad":"' + b"x" * (70 * 1024) + b'"}'
expect("70 KiB 正文（F15）", post(body=big), 413)
pipelined = post() + build("GET", "/api/health", cl=False)
r = exchange(pipelined)
check("一个连接里连发两个请求，只回第一个（F11）", r["status"] == 401 and r["responses"] == 1, "401，1 个响应",
      "%s，%s 个响应" % (r["status"], r.get("responses")))
r = exchange(build("POST", FIRE, ("Content-Type: application/json", "Authorization: " + WRONG, "Bad Header: x"), BODY))
check("非法头名（F30）", r["status"] == 404 and r["body"] == FIXED_404, 404, r["status"])

# ---- 只在自查里做的：看上游收到了什么、超时、上游不在、慢连接、连接数 ----
if args.mode == "selfcheck":
    def upstream_records():
        with open(args.upstream_log) as f:
            return [json.loads(line) for line in f if line.strip()]

    n_forwarded = 6  # 上面 401 的 6 项和连发两个请求的第一个，各转一次；下面单独核对
    recs = upstream_records()
    check("替身上游收到的请求数（只有该放行的才到上游）", len(recs) == n_forwarded + 1, n_forwarded + 1, len(recs))
    check("替身上游收到的都是 POST 触发路径",
          all(x["method"] == "POST" and x["path"] == FIRE for x in recs), True,
          sorted({(x["method"], mask(x["path"])) for x in recs}))
    allowed = {"host", "authorization", "content-type", "idempotency-key", "content-length", "connection"}
    seen = sorted({k.lower() for x in recs for k, _ in x["headers"]})
    check("替身上游收到的头只有白名单里的（F12）", set(seen) <= allowed, sorted(allowed), seen)
    check("替身上游收到的 Host 都是 127.0.0.1:3110（F13）",
          all(dict((k.lower(), v) for k, v in x["headers"]).get("host") == "127.0.0.1:3110" for x in recs), True,
          sorted({dict((k.lower(), v) for k, v in x["headers"]).get("host") for x in recs}))
    check("替身上游收到的正文和发出的一样、Content-Length 对得上",
          all(x["body"] == BODY.decode() and dict((k.lower(), v) for k, v in x["headers"]).get("content-length") == str(len(BODY))
              for x in recs), True, sorted({len(x["body"]) for x in recs}))

    r = exchange(post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Idempotency-Key: audit-1")))
    rec = upstream_records()[-1]
    hdr = dict((k.lower(), v) for k, v in rec["headers"])
    check("Idempotency-Key 原样转过去", hdr.get("idempotency-key") == "audit-1", "audit-1", hdr.get("idempotency-key"))
    check("上游回的 Set-Cookie 不回传（F29）", b"set-cookie" not in r["raw"].lower(), "没有 Set-Cookie",
          "有" if b"set-cookie" in r["raw"].lower() else "没有")
    check("上游回的状态码和正文原样返回", r["status"] == 401 and r["body"] == b'{"error":"Unauthorized"}', "401 和替身的正文",
          "%s %r" % (r["status"], r["body"][:40]))

    r = exchange(post(headers=("Content-Type: application/json", "Authorization: " + WRONG, "Idempotency-Key: slow")))
    check("上游 20 秒不回 -> 504，15 秒左右（F18）", r["status"] == 504 and 14000 <= r["ms"] <= 17000, "504，14–17 秒",
          "%s，%.1f 秒" % (r["status"], r["ms"] / 1000))
    if args.down_port:
        r = exchange(post(), port=args.down_port)
        check("上游没人听 -> 502（F18）", r["status"] == 502, 502, r["status"])

    t0 = time.monotonic()
    s = socket.create_connection((args.host, args.port), timeout=30)
    s.sendall(b"POST " + FIRE.encode() + b" HTTP/1.1\r\nHost: x\r\n")
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except (socket.timeout, ConnectionResetError):
            break
        if not c:
            break
        data += c
    s.close()
    secs = time.monotonic() - t0
    check("只发半个请求头的慢连接，被关掉（F14）", secs <= 7.5, "≤ 7.5 秒内关", "%.1f 秒，回 %s" % (secs, data[:12]))

    t0 = time.monotonic()
    s = socket.create_connection((args.host, args.port), timeout=30)
    s.sendall(post(body=b"").replace(b"Content-Length: 0", b"Content-Length: 1000") + b'{"a":')
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except (socket.timeout, ConnectionResetError):
            break
        if not c:
            break
        data += c
    s.close()
    secs = time.monotonic() - t0
    check("正文发一半就停的慢连接，被关掉（F14）", secs <= 12.5, "≤ 12.5 秒内关", "%.1f 秒，回 %s" % (secs, data[:12]))

    idle = [socket.create_connection((args.host, args.port), timeout=5) for _ in range(20)]
    time.sleep(0.5)
    r = exchange(post(), timeout=5)
    check("20 个空连接占着时，第 21 个被拒（F16）", r["status"] is None, "没响应（被关）", r["status"])
    for s in idle:
        s.close()
    time.sleep(1.5)
    r = exchange(post())
    check("空连接关掉以后恢复（F16）", r["status"] == 401, 401, r["status"])

total, failed = len(results), results.count(False)
print("合计 %d 项，PASS %d，FAIL %d" % (total, total - failed, failed))
sys.exit(1 if failed else 0)
