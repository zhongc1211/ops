#!/usr/bin/env python3
"""Loopback-only (no token) counts + keyword recall for the deepvision-ads import. Run on site."""
import json, re, sys, urllib.request
from pathlib import Path
B = "http://127.0.0.1:8000/api/v2/memory"
SKIP = set()  # Zack: import all 16
def post(p, b):
    r = urllib.request.Request(B + p, json.dumps(b).encode(), {"content-type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=120) as x: return x.status, json.loads(x.read())
    except urllib.error.HTTPError as e: return e.code, e.read().decode()[:300]
def total(app, proj, mt, owner):
    c, r = post("/get", {"app_id": app, "project_id": proj, "memory_type": mt, "page_size": 100, **owner})
    d = r.get("data", {}) if isinstance(r, dict) else {}
    return d.get("total_count", d.get("total", len(next((v for v in d.values() if isinstance(v, list)), []))))
R = Path("/var/lib/everos")
disk = lambda a, p, g: len(list((R / a / p / "agents" / g / "skills").glob("*/SKILL.md")))
out = {
 "xinyue_episode": total("xinyue", "xinyue-site", "episode", {"user_id": "zack"}),
 "xinyue_skill": total("xinyue", "xinyue-site", "agent_skill", {"agent_id": "coding-xinyue-site"}),
 "xinyue_skill_disk": disk("xinyue", "xinyue-site", "coding-xinyue-site"),
 "vllm_skill": total("vllm-omni", "vllm-omni", "agent_skill", {"agent_id": "coding-vllm-omni"}),
 "dvsite_skill": total("deepvision", "deepvision-site", "agent_skill", {"agent_id": "coding-deepvision-site"}),
 "dvsite_skill_disk": disk("deepvision", "deepvision-site", "coding-deepvision-site"),
 "dvads_skill_api": total("deepvision", "deepvision-ads", "agent_skill", {"agent_id": "coding-deepvision-ads"}),
 "dvads_skill_disk": disk("deepvision", "deepvision-ads", "coding-deepvision-ads"),
}
d = R / "deepvision/deepvision-ads/agents/coding-deepvision-ads/skills"
out["skipped_present_on_disk"] = [n for n in SKIP if (d / f"skill_{n}").exists()]
if "--recall" in sys.argv:
    scopes = {"ads": ("deepvision", "deepvision-ads", "coding-deepvision-ads"),
              "dvsite": ("deepvision", "deepvision-site", "coding-deepvision-site"),
              "xinyue": ("xinyue", "xinyue-site", "coding-xinyue-site")}
    rows = []
    for f in sorted((Path(__file__).resolve().parent / "source").glob("*.md")):
        if f.stem in SKIP: continue
        q = re.search(r"\*\*规则[：:]\*\*\s*(.+)", f.read_text()).group(1).strip()
        row = {"slug": f.stem}
        for k, (a, p, g) in scopes.items():
            c, r = post("/search", {"app_id": a, "project_id": p, "agent_id": g, "query": q, "method": "keyword", "top_k": 10})
            row[k] = [c, f.stem in json.dumps(r, ensure_ascii=False)]
        rows.append(row)
    out["recall"] = [f"{r['slug']} ads={r['ads']} dvsite={r['dvsite']} xinyue={r['xinyue']}" for r in rows]
    out["ads_found"] = sum(r["ads"][1] for r in rows)
    out["leak_dvsite"] = sum(r["dvsite"][1] for r in rows); out["leak_xinyue"] = sum(r["xinyue"][1] for r in rows)
print(json.dumps(out, ensure_ascii=False, indent=1))
