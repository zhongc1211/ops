#!/usr/bin/env python3
"""Local webhook receiver for tests. Never forwards anything.

  mock_webhook.py --port 18765 --out requests.jsonl [--key test-key]

Every POST is appended to --out as one JSON line: {ts, path, auth_ok, body}.
While a file named <out>.fail-<last path segment> exists, requests to that path get 503
(used to simulate an unreachable bot).
"""
import argparse
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=18765)
    p.add_argument("--out", required=True)
    p.add_argument("--key", default="test-key")
    a = p.parse_args()

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(n)
            seg = self.path.rstrip("/").rsplit("/", 1)[-1]
            fail = os.path.exists("%s.fail-%s" % (a.out, seg))
            try:
                body = json.loads(raw)
            except ValueError:
                body = {"_raw": raw.decode("utf-8", "replace")}
            rec = {"ts": time.strftime("%H:%M:%S"), "path": self.path,
                   "auth_ok": self.headers.get("Authorization") == "Bearer " + a.key,
                   "answered": 503 if fail else 200, "body": body}
            with open(a.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            self.send_response(503 if fail else 200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":%s}' % (b"false" if fail else b"true"))

        def log_message(self, *args):
            pass

    ThreadingHTTPServer(("127.0.0.1", a.port), H).serve_forever()


if __name__ == "__main__":
    main()
