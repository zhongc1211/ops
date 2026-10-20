#!/usr/bin/env python3
"""Fake agent-probe: no agent processes, no notify-run, no stop marks (same output framing as scripts/agent-probe)."""
import base64
import gzip
import json
import time

doc = {"ts": time.time(), "procs": [], "stops": [], "wake": {"sessions": [], "nr": []}}
print("@@PROBE-BEGIN")
print(base64.b64encode(gzip.compress(json.dumps(doc).encode())).decode())
print("@@PROBE-END")
