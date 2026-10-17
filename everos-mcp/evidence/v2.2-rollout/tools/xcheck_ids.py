#!/usr/bin/env python3
"""Server-side isolation cross-check (same body the v2.2 launcher sends: hybrid, no enable_llm_rerank), tailnet + Host.
usage: xcheck_ids.py <env-file> <query> <user|agent>. Prints ids with their app/project/owner. Key never printed."""
import json, os, sys, time, urllib.request
envf, q, track = sys.argv[1:4]
env = {}
for l in open(os.path.expanduser(envf)):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1); env[k.replace("export ", "")] = v.strip().strip('"\'')
b = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"], "query": q, "method": "hybrid", "top_k": -1, "include_profile": False}
b.update({"agent_id": env["EVEROS_ASSISTANT_SENDER_ID"]} if track == "agent" else {"user_id": env["EVEROS_USER_ID"]})
t = time.monotonic()
r = urllib.request.urlopen(urllib.request.Request("http://100.64.0.5/api/v2/memory/search", json.dumps(b).encode(),
    {"Content-Type": "application/json", "Authorization": "Bearer " + env["EVEROS_API_KEY"], "Host": "everos.deepvision.sg"}), timeout=120)
d = json.load(r)["data"]
want = (b["app_id"], b["project_id"])
foreign = 0; nf = 0; out = []
for k in ("episodes", "agent_skills", "agent_cases"):
    for it in d.get(k) or []:
        sc = (it.get("app_id"), it.get("project_id")); own = it.get("user_id") or it.get("agent_id")
        bad = sc != want or own not in (b.get("user_id"), b.get("agent_id"))
        foreign += bad; f = len(it.get("atomic_facts") or []); nf += f
        out.append("  %s %s %s/%s owner=%s facts=%d%s" % (k, it.get("id"), sc[0], sc[1], own, f, " FOREIGN" if bad else ""))
print("- %s/%s %s q=%s -> %d %.2fs items=%d atomic_facts=%d foreign=%d" % (want[0], want[1], track, q, r.status, time.monotonic() - t, len(out), nf, foreign))
print("\n".join(out))
