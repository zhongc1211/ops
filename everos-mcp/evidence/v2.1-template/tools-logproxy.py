# Test-only logging proxy: listens on the box's tailnet IP, logs method/path/Host (never the auth header), forwards to site nginx.
import http.client, http.server, sys, time
LOG = open(sys.argv[1], "a", buffering=1)
class H(http.server.BaseHTTPRequestHandler):
    def _go(self):
        n = int(self.headers.get("Content-Length") or 0); body = self.rfile.read(n) if n else None
        c = http.client.HTTPConnection("100.64.0.5", 80, timeout=60)
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in ("connection",)}
        c.putrequest(self.command, self.path, skip_host=True, skip_accept_encoding=True)
        for k, v in hdrs.items(): c.putheader(k, v)
        c.endheaders(body); r = c.getresponse(); data = r.read()
        LOG.write("%s %s %s Host=%s auth=%s -> upstream %s\n" % (time.strftime("%H:%M:%S"), self.command, self.path,
                  self.headers.get("Host"), "Bearer <redacted>" if self.headers.get("Authorization") else "none", r.status))
        self.send_response(r.status)
        for k, v in r.getheaders():
            if k.lower() not in ("transfer-encoding", "connection", "content-length"): self.send_header(k, v)
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    do_GET = do_POST = _go
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("100.64.0.6", 18080), H).serve_forever()
