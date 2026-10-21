#!/usr/bin/env python3
"""Fake webhook for the PER-79 e2e drill: records every POST, sends nothing anywhere.

mock_webhook.py <log.jsonl> <portfile> [seconds] [stopfile]
Listens on 127.0.0.1 (a free port, written to <portfile>), answers 200 to every POST and appends one line per request
to <log.jsonl>: {"path", "auth_ok", "body"}. The Authorization header itself is not logged, only whether it was
"Bearer e2e-fake" (the KEY in the drill's fake env files). Exits by itself as soon as <stopfile> exists, or after <seconds>
(default 900) when the drill died before creating it: the drill never has to send it a signal.
"""
import json, os, sys, threading, time
from http.server import BaseHTTPRequestHandler, HTTPServer

log, portfile = sys.argv[1], sys.argv[2]
seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 900
stopfile = sys.argv[4] if len(sys.argv) > 4 else None


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n).decode("utf-8", "replace")
        try:
            body = json.loads(raw)
        except ValueError:
            body = raw
        rec = {"path": self.path, "auth_ok": self.headers.get("Authorization") == "Bearer e2e-fake", "body": body}
        with open(log, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


def stop_later():
    end = time.time() + seconds
    while time.time() < end and not (stopfile and os.path.exists(stopfile)):
        time.sleep(0.2)
    srv.shutdown()


srv = HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(srv.server_address[1]))
threading.Thread(target=stop_later, daemon=True).start()
srv.serve_forever()
