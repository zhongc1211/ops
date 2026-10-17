#!/usr/bin/env python3
"""One MCP stdio session against a launcher: initialize, tools/list, then a list of read-only tools/call.
usage: mcp_session.py <launcher> '<json list of [tool, args]>' [KEY=VAL ...]. Prints tools, then each call's
full text result (memory content, no key), with counts of 'fact:' lines and episode lines."""
import json, os, subprocess, sys, time
cmd, calls = sys.argv[1], json.loads(sys.argv[2])
env = dict(os.environ)
for kv in sys.argv[3:]:
    k, v = kv.split("=", 1); env[k] = v
t_start = time.monotonic()
p = subprocess.Popen([cmd], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
def send(o): p.stdin.write(json.dumps(o) + "\n"); p.stdin.flush()
def recv(want):
    while True:
        line = p.stdout.readline()
        if not line:
            print("EXIT", p.wait(), "stderr:", p.stderr.read().strip()[-400:]); sys.exit(2)
        m = json.loads(line)
        if m.get("id") == want: return m
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "v22-gate", "version": "0"}}})
print("server:", recv(1)["result"].get("serverInfo"), "init_s=%.1f" % (time.monotonic() - t_start))
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
print("tools:", sorted(t["name"] for t in recv(2)["result"]["tools"]))
for i, (tool, args) in enumerate(calls):
    t0 = time.monotonic()
    send({"jsonrpc": "2.0", "id": 10 + i, "method": "tools/call", "params": {"name": tool, "arguments": args}})
    r = recv(10 + i)["result"]
    text = "".join(c.get("text", "") for c in r.get("content", []))
    lines = text.splitlines()
    print("=== call %s %s isError=%s ms=%d episodes=%d facts=%d skills=%d" % (tool, json.dumps(args, ensure_ascii=False),
          r.get("isError"), (time.monotonic() - t0) * 1000, sum(1 for l in lines if l.startswith("- [")),
          sum(1 for l in lines if l.startswith("  - fact: ")), sum(1 for l in lines if " (confidence " in l and l.startswith("- "))))
    print(text)
p.stdin.close(); p.terminate()
