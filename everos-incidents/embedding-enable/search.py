#!/usr/bin/env python3
"""search.py <envname> <user|agent> <method> <query> [llm_rerank] — POST /api/v2/memory/search over tailnet; key never printed."""
import json, sys, time, urllib.request, os
envn, side, method, q = sys.argv[1:5]; llm = len(sys.argv) > 5 and sys.argv[5] == "1"
env = {}
for l in open(os.path.expanduser(f"~/.config/everos/{envn}.env")):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1); env[k.replace("export ", "")] = v.strip().strip('"').strip("'")
body = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"], "query": q, "method": method, "top_k": 5}
body["agent_id" if side == "agent" else "user_id"] = env["EVEROS_ASSISTANT_SENDER_ID"] if side == "agent" else env["EVEROS_USER_ID"]
if llm: body["enable_llm_rerank"] = True
req = urllib.request.Request(os.environ.get("EP", "http://100.64.0.5") + "/api/v2/memory/search", json.dumps(body).encode(),
      {"Content-Type": "application/json", "Authorization": "Bearer " + env["EVEROS_API_KEY"], "Host": "everos.deepvision.sg"})
t = time.time()
try:
    r = urllib.request.urlopen(req, timeout=90); code = r.status; d = json.load(r)
except urllib.error.HTTPError as e:
    code = e.code; d = json.loads(e.read() or b"{}")
dt = time.time() - t
res = d.get("data", d).get("results", d.get("data", d)) if isinstance(d, dict) else d
own = body.get("agent_id") or body.get("user_id")
print(f"- {body['app_id']}/{body['project_id']} {side}={own} {method}{'+llm_rerank' if llm else ''} q={q} -> {code} {dt:.3f}s")
if code != 200: print("   ERROR", json.dumps(d, ensure_ascii=False)[:300]); sys.exit()
if os.environ.get("DUMP"): print(json.dumps(d, ensure_ascii=False)[:3000])
foreign = []
for k, v in (res.items() if isinstance(res, dict) else []):
    if isinstance(v, list):
        print(f"   {k}: {len(v)}")
        for it in v:
            iid = it.get("id") or it.get("memory_id") or "?"
            scope = f"{it.get('app_id','?')}/{it.get('project_id','?')}"
            extra = it.get("timestamp") or it.get("created_at") or ""
            print(f"     {iid} {scope} {str(extra)[:19]} score={it.get('score')}")
            if scope not in (f"{body['app_id']}/{body['project_id']}", "?/?"): foreign.append(iid)
            if iid.startswith("coding-") and not iid.startswith(own): foreign.append(iid)
print("   foreign:", foreign or "none")
