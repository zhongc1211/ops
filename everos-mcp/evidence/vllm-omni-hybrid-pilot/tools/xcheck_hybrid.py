#!/usr/bin/env python3
"""Read-only cross-check for the hybrid pilot: POST /api/v2/memory/search with the body the pilot launcher sends.
usage: xcheck_hybrid.py <env-file> <query> <agent|user> [rerank 0|1]. Key read from the env file, never printed."""
import json, sys, time, urllib.request
envf, query, track = sys.argv[1], sys.argv[2], sys.argv[3]
rerank = (sys.argv[4] if len(sys.argv) > 4 else ("1" if track == "agent" else "0")) == "1"
env = {}
for line in open(envf):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); env[k] = v.strip().strip('"').strip("'")
body = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"], "query": query, "method": "hybrid", "top_k": -1, "include_profile": False}
body.update({"agent_id": env["EVEROS_ASSISTANT_SENDER_ID"]} if track == "agent" else {"user_id": env["EVEROS_USER_ID"]})
if rerank: body["enable_llm_rerank"] = True
req = urllib.request.Request(env["EVEROS_BASE_URL"].rstrip("/") + "/api/v2/memory/search", data=json.dumps(body).encode(),
      headers={"Content-Type": "application/json", "Authorization": "Bearer " + env["EVEROS_API_KEY"], "User-Agent": "everos-hybrid-pilot/1.0"}, method="POST")
t0 = time.monotonic()
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        status = r.status; data = json.load(r)
except urllib.error.HTTPError as e:
    status = e.code; data = {"error_body": e.read().decode(errors="replace")[:500]}
ms = int((time.monotonic() - t0) * 1000)
d = data.get("data") or {}
print(json.dumps({"request": body, "http_status": status, "ms": ms,
  "agent_skills": [{"id": s.get("id"), "name": s.get("name"), "score": s.get("score")} for s in d.get("agent_skills") or []],
  "agent_cases": [c.get("id") for c in d.get("agent_cases") or []],
  "episodes": [e.get("id") for e in d.get("episodes") or []],
  "data_counts": {k: (len(v) if isinstance(v, list) else type(v).__name__) for k, v in d.items()}, "error": data.get("error") or data.get("error_body")}, ensure_ascii=False, indent=1))
