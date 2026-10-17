#!/usr/bin/env python3
"""Print response field names (no values except ids/scope) for one hybrid search. Key read from env file, never printed."""
import json, sys, urllib.request, os
envf, q, track = sys.argv[1], sys.argv[2], sys.argv[3]
env = {}
for l in open(os.path.expanduser(envf)):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1); env[k.replace("export ", "")] = v.strip().strip('"\'')
b = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"], "query": q, "method": "hybrid", "top_k": -1, "include_profile": False}
b.update({"agent_id": env["EVEROS_ASSISTANT_SENDER_ID"]} if track == "agent" else {"user_id": env["EVEROS_USER_ID"]})
r = urllib.request.urlopen(urllib.request.Request("http://100.64.0.5/api/v2/memory/search", json.dumps(b).encode(),
    {"Content-Type": "application/json", "Authorization": "Bearer " + env["EVEROS_API_KEY"], "Host": "everos.deepvision.sg"}), timeout=90)
d = json.load(r)["data"]
for k, v in d.items():
    if isinstance(v, list) and v:
        it = v[0]
        print(k, len(v), sorted(it.keys()) if isinstance(it, dict) else type(it))
        if isinstance(it, dict):
            print("  scope:", {x: it.get(x) for x in ("id", "app_id", "project_id", "user_id", "agent_id", "owner_id", "sender_id")})
            af = it.get("atomic_facts")
            if af: print("  atomic_fact keys:", sorted(af[0].keys()), {x: af[0].get(x) for x in ("id", "app_id", "project_id", "user_id")})
    else:
        print(k, v if not isinstance(v, list) else 0)
