#!/usr/bin/env python3
"""After eggbot's import: check every source/*.md lesson is in EverOS and keyword-recallable.

  set -a; . ~/.config/everos/dv-ads.env; set +a
  python3 -I check_recall.py [--skip slug,...] > recall-after-import.md   # exit 0 = all present

Scope is fixed: app_id=deepvision project_id=deepvision-ads agent_id=coding-deepvision-ads.
For each lesson: listed by /memory/get (agent_skill), and POST /memory/search method=keyword,
top_k=10, query = the lesson's 规则 line, PASS when the skill name is among returned agent_skills.
Also checks the lesson body (without H1) appears verbatim in the stored skill content.
Isolation: the same queries with project_id=deepvision-site and app_id=xinyue must not return
any deepvision-ads skill. The key goes only into the Authorization header; never printed.
"""
from __future__ import annotations

import json, os, re, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCOPE = {"app_id": "deepvision", "project_id": "deepvision-ads", "agent_id": "coding-deepvision-ads"}
OTHER_SCOPES = [{"app_id": "deepvision", "project_id": "deepvision-site", "agent_id": "coding-deepvision-ads"},
                {"app_id": "xinyue", "project_id": "xinyue-site", "agent_id": "coding-deepvision-ads"}]


def post(path, payload):
    req = urllib.request.Request(os.environ["EVEROS_BASE_URL"].rstrip("/") + path, data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + os.environ["EVEROS_API_KEY"], "Content-Type": "application/json",
                 "User-Agent": "curl/8.5.0"})  # Cloudflare 403s the default Python-urllib UA
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def skills_of(resp):
    d = resp.get("data") or {}
    return d.get("agent_skills") or d.get("skills") or []


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def main():
    skip = set()
    if "--skip" in sys.argv:
        skip = set(sys.argv[sys.argv.index("--skip") + 1].split(","))
    lessons = []
    for p in sorted((HERE / "source").glob("*.md")):
        if p.stem in skip:
            continue
        t = p.read_text(encoding="utf-8")
        body = t[t.find("\n---", 3) + 4:].lstrip("\n")
        rule = re.search(r"\*\*规则[：:]\*\*\s*(.+)", body).group(1).strip()
        lessons.append((p.stem, rule, re.sub(r"^#\s+.+\n+", "", body, count=1).strip()))
    stored = {s.get("name"): s for s in skills_of(post("/api/v2/memory/get", {**SCOPE, "memory_type": "agent_skill", "page_size": 100}))}
    print(f"EverOS agent_skill in deepvision/deepvision-ads/coding-deepvision-ads: {len(stored)}; expected lessons: {len(lessons)}\n")
    print("| # | skill | 已存 | keyword 召回（名次） | 内容一致 | 隔离（他处命中） |\n|---|---|---|---|---|---|")
    bad = 0
    for i, (name, rule, body) in enumerate(lessons, 1):
        s = stored.get(name)
        hits = [x.get("name") for x in skills_of(post("/api/v2/memory/search", {**SCOPE, "query": rule, "method": "keyword", "top_k": 10}))]
        rank = hits.index(name) + 1 if name in hits else None
        same = bool(s) and norm(body) in norm(s.get("content") or "")
        leak = 0
        for o in OTHER_SCOPES:
            leak += sum(1 for x in skills_of(post("/api/v2/memory/search", {**o, "query": rule, "method": "keyword", "top_k": 10})) if x.get("name") == name)
        ok = bool(s) and rank is not None and leak == 0
        bad += 0 if ok else 1
        print(f"| {i} | `{name}` | {'是' if s else '**否**'} | {('是（第 %d）' % rank) if rank else '**否**'} | {'是' if same else '否/未知'} | {leak} |")
    print(f"\n总计 {len(lessons)} 条，缺口 {bad} 条")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
