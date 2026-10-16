#!/usr/bin/env python3
"""Loopback-only (no token) counts + recall for the deepvision-site import. Run on site."""
import json, sys, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_deepvision_lessons import skills
B = "http://127.0.0.1:8000/api/v2/memory"
def post(p, b):
    r = urllib.request.Request(B + p, json.dumps(b).encode(), {"content-type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=120) as x: return x.status, json.loads(x.read())
    except urllib.error.HTTPError as e: return e.code, e.read().decode()[:300]
def total(app, proj, mt, owner):
    c, r = post("/get", {"app_id": app, "project_id": proj, "memory_type": mt, "page_size": 100, **owner})
    d = r.get("data", {}) if isinstance(r, dict) else {}
    return d.get("total_count", d.get("total", len(next((v for v in d.values() if isinstance(v, list)), []))))
root = Path("/var/lib/everos")
out = {
 "xinyue_episode": total("xinyue", "xinyue-site", "episode", {"user_id": "zack"}),
 "xinyue_skill": total("xinyue", "xinyue-site", "agent_skill", {"agent_id": "coding-xinyue-site"}),
 "xinyue_skill_disk": len(list((root/"xinyue/xinyue-site/agents/coding-xinyue-site/skills").glob("*/SKILL.md"))),
 "vllm_skill": total("vllm-omni", "vllm-omni", "agent_skill", {"agent_id": "coding-vllm-omni"}),
 "dv_skill_api": total("deepvision", "deepvision-site", "agent_skill", {"agent_id": "coding-deepvision-site"}),
 "dv_skill_disk": len(list((root/"deepvision/deepvision-site/agents/coding-deepvision-site/skills").glob("*/SKILL.md"))),
}
if "--recall" in sys.argv:
    rows = []
    for it in skills(Path(__file__).resolve().parent / "docs/solutions"):
        hit = {}
        for k, (a, p, g) in {"dv": ("deepvision", "deepvision-site", "coding-deepvision-site"),
                             "xinyue": ("xinyue", "xinyue-site", "coding-xinyue-site")}.items():
            c, r = post("/search", {"app_id": a, "project_id": p, "agent_id": g, "query": it["title"], "method": "keyword", "top_k": 10})
            s = json.dumps(r, ensure_ascii=False)
            hit[k] = (c, it["slug"] in s or it["slug"].replace("-", "_") in s)
        rows.append({"slug": it["slug"], **{k: v for k, v in hit.items()}})
    out["recall"] = rows
    out["dv_found"] = sum(1 for r in rows if r["dv"][1]); out["xinyue_leak"] = sum(1 for r in rows if r["xinyue"][1])
print(json.dumps(out, ensure_ascii=False, indent=1))
