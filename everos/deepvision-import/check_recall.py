#!/usr/bin/env python3
"""Check every deepvision-site docs/solutions entry is keyword-recallable in EverOS,
and that the xinyue scope does not see it (isolation).

  set -a; . ~/.config/everos/deepvision.env; set +a 
  python3 -I evidence/FDV-68-everos/check_recall.py docs/solutions

The key only goes into the Authorization header; it is never printed.
Per entry: POST /api/v2/memory/search method=keyword top_k=10, query = the entry's title;
PASS when the expected skill is returned and its stored content contains the repo body.
Isolation: same query in app_id=xinyue must not return the skill. Exit 1 on any gap.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_deepvision_lessons import skills  # noqa: E402

from import_deepvision_lessons import scope  # noqa: E402

_a, _p, _g = scope()
SCOPE = {"app_id": _a, "project_id": _p, "agent_id": _g}
OTHER = {"app_id": "xinyue", "project_id": "xinyue-site", "agent_id": "coding-xinyue-site"}


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        os.environ["EVEROS_BASE_URL"].rstrip("/") + path,
        data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + os.environ["EVEROS_API_KEY"],
                 "Content-Type": "application/json", "User-Agent": "deepvision-check-recall/1.0"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def main(solutions: Path) -> int:
    items = skills(solutions)
    listing = post("/api/v2/memory/get", {**SCOPE, "memory_type": "agent_skill", "page_size": 100})
    stored = {s["name"]: s for s in listing["data"]["agent_skills"]}
    print(f"EverOS agent_skill total ({SCOPE['app_id']}/{SCOPE['project_id']}): {len(stored)}\n")
    print("| # | 源文件 | skill name | EverOS id | keyword 召回（query=标题） | 内容一致 | xinyue 范围搜到 |")
    print("|---|---|---|---|---|---|---|")
    bad = 0
    for i, it in enumerate(items, 1):
        key = it["slug"][:50]
        res = post("/api/v2/memory/search", {**SCOPE, "query": it["title"], "method": "keyword", "top_k": 10})
        hits = [s["name"] for s in res["data"].get("agent_skills", [])]
        other = post("/api/v2/memory/search", {**OTHER, "query": it["title"], "method": "keyword", "top_k": 10})
        leak = key in [s["name"] for s in other["data"].get("agent_skills", [])]
        repo_body = it["body"].split("\n---\n来源：", 1)[0].strip()
        same = "是" if key in stored and repo_body in stored[key]["content"] else "否"
        ok = key in hits and same == "是" and not leak
        bad += not ok
        rank = f"是（第 {hits.index(key) + 1}）" if key in hits else "否"
        rid = stored[key]["id"] if key in stored else "（无）"
        print(f"| {i} | `{it['rel']}` | `{key}` | `{rid}` | {rank} | {same} | {'是（泄漏）' if leak else '否'} |")
    print(f"\n总计 {len(items)} 条，缺口 {bad} 条")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "docs/solutions").resolve()))
