#!/usr/bin/env python3
"""Per-project memory counts (read-only). Run on site. md files on disk + API /memory/get total_count via loopback."""
import json, os, sys, urllib.request, collections, hashlib
ROOT = "/var/lib/everos"
SCOPES = [("xinyue", "xinyue-site", "coding-xinyue-site"), ("deepvision", "deepvision-site", "coding-deepvision-site"),
          ("deepvision", "deepvision-ads", "coding-deepvision-ads"), ("vllm-omni", "vllm-omni", "coding-vllm-omni"),
          ("ops", "everos-smoke", None)]
TYPES = ["episode", "profile", "agent_case", "agent_skill"]
out = {}
for app, proj, agent in SCOPES:
    base = os.path.join(ROOT, app, proj); c = collections.Counter(); h = hashlib.sha256()
    for dp, dn, fn in sorted(os.walk(base)):
        dn.sort()
        for f in sorted(fn):
            if f.endswith(".md"):
                rel = os.path.relpath(os.path.join(dp, f), base); parts = rel.split(os.sep)
                c["/".join(p for p in parts[:-1] if not p.startswith("20"))[:80]] += 1; h.update(rel.encode())
    api = {}
    owners = [("user_id", "zack")] + ([("agent_id", agent)] if agent else [("user_id", "smoke-user")])
    for ok, ov in owners:
        for t in TYPES:
            body = json.dumps({"app_id": app, "project_id": proj, ok: ov, "memory_type": t, "page": 1, "page_size": 1}).encode()
            try:
                r = urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8000/api/v2/memory/get", body, {"Content-Type": "application/json"}), timeout=20)
                d = json.load(r).get("data") or {}; api[f"{ov}:{t}"] = d.get("total_count", d.get("total"))
            except Exception as e:
                api[f"{ov}:{t}"] = "ERR " + str(e)[:40]
    out[f"{app}/{proj}"] = {"md_total": sum(c.values()), "md_paths_sha8": h.hexdigest()[:8], "md_by_dir": dict(sorted(c.items())), "api": api}
print(json.dumps(out, indent=1, ensure_ascii=False))
