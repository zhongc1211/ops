#!/usr/bin/env python3
"""Run on site as root, detached. One backfill chunk: in-flight check -> stop EverOS -> backfill <phase> (answers y only if the
estimate is <= 5M tokens) -> SIGINT at <budget>s, TERM/KILL 60s later -> start EverOS -> wait for /health ok. Logs to argv[3]."""
import os, re, signal, subprocess, sys, time, json, urllib.request, datetime
phase, budget, log = sys.argv[1], int(sys.argv[2]), open(sys.argv[3], "a", buffering=1)
def ts(): return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime("%H:%M:%S SGT")
def L(*a): log.write(ts() + " " + " ".join(str(x) for x in a) + "\n")
def health():
    try: return json.load(urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=3))
    except Exception: return None
# in-flight: any add/flush in the last 120s, or open upstream connections to :8000
tail = subprocess.run(["tail", "-n", "200", "/var/log/nginx/access.log"], capture_output=True, text=True).stdout.splitlines()
now = time.time(); recent = []
for l in tail:
    m = re.search(r"\[(\d+/\w+/\d+:\d+:\d+:\d+ [+-]\d+)\] \"POST (/api/v2/memory/(add|flush))", l)
    if m and now - datetime.datetime.strptime(m.group(1), "%d/%b/%Y:%H:%M:%S %z").timestamp() < 120: recent.append(m.group(2))
conns = subprocess.run(["ss", "-Htn", "state", "established", "( dport = :8000 )"], capture_output=True, text=True).stdout.strip().splitlines()
L("phase", phase, "budget", budget, "| add/flush in last 120s:", len(recent), "| open conns to :8000:", len(conns))
if recent or conns:
    L("ABORT: in flight, not stopping"); sys.exit(2)
L("stop everos"); subprocess.run(["systemctl", "stop", "everos"], check=True); L("stopped")
cmd = ["sudo", "-u", "everos", "env", "HOME=/var/lib/everos", "COLUMNS=160", "bash", "-c",
       "set -a; . /etc/everos/everos.env; set +a; exec /opt/everos/venv/bin/everos cascade backfill --root /var/lib/everos --phase " + phase]
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd="/var/lib/everos", start_new_session=True)
buf = ""; t0 = time.time(); answered = False
os.set_blocking(p.stdout.fileno(), False)
while p.poll() is None:
    try: chunk = p.stdout.read() or b""
    except Exception: chunk = b""
    if chunk:
        s = chunk.decode(errors="replace"); buf += s
        for line in s.splitlines():
            if line.strip() and not re.search(r"debug|jieba|[Pp]refix dict|Loading model|Dumping", line): L("|", line.strip()[:200])
    if not answered and "[y/N]" in buf:
        m = re.search(r"~?([\d.,]+)\s*([KMB]?)\s*tokens \[y/N\]", buf)
        tok = 0
        if m:
            tok = float(m.group(1).replace(",", "")) * {"": 1, "K": 1e3, "M": 1e6, "B": 1e9}[m.group(2)]
        ok = tok <= 5e6 and (m is not None or phase != "skills")
        L("estimate tokens", int(tok), "->", "y" if ok else "n (too big)")
        p.stdin.write(b"y\n" if ok else b"n\n"); p.stdin.flush(); answered = True
    if time.time() - t0 > budget:
        L("budget reached: SIGINT"); os.killpg(p.pid, signal.SIGINT); t1 = time.time()
        while p.poll() is None and time.time() - t1 < 60: time.sleep(1)
        if p.poll() is None: L("SIGTERM"); os.killpg(p.pid, signal.SIGTERM); time.sleep(10)
        if p.poll() is None: L("SIGKILL"); os.killpg(p.pid, signal.SIGKILL)
        break
    time.sleep(0.5)
try:
    rest = p.stdout.read() or b""
    for line in rest.decode(errors="replace").splitlines():
        if line.strip() and not re.search(r"debug|jieba|[Pp]refix dict|Loading model|Dumping", line): L("|", line.strip()[:200])
except Exception: pass
L("backfill exit", p.wait())
L("start everos"); subprocess.run(["systemctl", "start", "everos"])
for i in range(60):
    h = health()
    if h and h.get("status") == "ok": L("UP health ok embed", h["capabilities"]["embed"], "cascade healthy", h["cascade"]["healthy"]); break
    time.sleep(2)
else: L("WARNING: health not ok after 120s")
L("DONE")
