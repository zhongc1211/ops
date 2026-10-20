"""Drill stand-ins for Orca's local port, the public tunnel URL and the guest uptime clock.

local  (127.0.0.1:LP): orca_mode ok -> 200; slow -> 200 after 8s; hang -> never answers (curl -m times out, 000);
                       down -> closes the connection without a reply (curl 000).
public (127.0.0.1:PP): no cloudflared process or cf_stale present -> 530 "error code: 1033"; Orca not ok -> 502; else 200.
uptime file: mirrors /proc/uptime, but stops advancing while the `paused` flag exists (stand-in for a stopped guest clock).
"""
import os, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

W, LP, PP = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
CF_MATCH = f"cloudflared tunnel --config {W}/cf.yml"

def mode():
    try:
        return open(f"{W}/orca_mode").read().strip()
    except OSError:
        return "ok"

class Quiet(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def reply(self, code, body):
        b = body.encode()
        self.send_response(code); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

class Local(Quiet):
    def do_GET(self):
        m = mode()
        if m == "hang":
            time.sleep(3600); return
        if m == "down":
            self.close_connection = True; return
        if m == "slow":
            time.sleep(8)
        self.reply(200, "orca")

class Public(Quiet):
    def do_GET(self):
        cf = subprocess.run(["pgrep", "-f", CF_MATCH], capture_output=True).returncode == 0
        if not cf or os.path.exists(f"{W}/cf_stale"):
            self.reply(530, "error code: 1033")
        elif mode() in ("ok", "slow"):
            self.reply(200, "orca")
        else:
            self.reply(502, "bad gateway")

def uptime():
    offset, last = 0.0, None
    while True:
        real = float(open("/proc/uptime").read().split()[0])
        if last is not None and os.path.exists(f"{W}/paused"):
            offset += real - last
        last = real
        with open(f"{W}/.uptime", "w") as f:
            f.write(f"{real - offset:.2f} 0.00\n")
        os.replace(f"{W}/.uptime", f"{W}/uptime")
        time.sleep(0.2)

for port, h in ((LP, Local), (PP, Public)):
    s = ThreadingHTTPServer(("127.0.0.1", port), h); s.daemon_threads = True
    threading.Thread(target=s.serve_forever, daemon=True).start()
uptime()
