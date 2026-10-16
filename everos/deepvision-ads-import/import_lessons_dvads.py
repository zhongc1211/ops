#!/usr/bin/env python3
"""Import deepvision-ads lessons (source/*.md) into EverOS agent_skills on site.

Same method as ../import/import_lessons.py (AgentSkillWriter.write_main), scope:
  app_id=deepvision project_id=deepvision-ads agent_id=coding-deepvision-ads
Writes <EVEROS_ROOT>/deepvision/deepvision-ads/agents/coding-deepvision-ads/skills/skill_<slug>/SKILL.md

Run on site:
  sudo -u everos env EVEROS_ROOT=/var/lib/everos /opt/everos/venv/bin/python3 import_lessons_dvads.py [--dry-run] [--skip slug,slug] <source_dir>
"""
from __future__ import annotations

import asyncio
import datetime as dt
import re
import sys
from pathlib import Path

import yaml

APP_ID = "deepvision"
PROJECT_ID = "deepvision-ads"
AGENT_ID = "coding-deepvision-ads"
SOURCE_TAG = "deepvision-ads-lessons-import-2026-10-16"
EXPECTED = 16


def parse(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8")
    end = text.find("\n---", 3)
    meta = yaml.safe_load(text[3:end]) or {}
    return meta, text[end + 4 :].lstrip("\n")


def rule_line(body: str) -> str:
    m = re.search(r"\*\*规则[：:]\*\*\s*(.+)", body)
    if not m:
        raise SystemExit("no 规则 line")
    return m.group(1).strip()


async def main(src: Path, dry: bool, skip: set[str] = frozenset()) -> int:
    files = sorted(src.glob("*.md"))
    if len(files) != EXPECTED:
        print(f"expected {EXPECTED} lesson files, found {len(files)}", file=sys.stderr)
        return 2
    unknown = set(skip) - {p.stem for p in files}
    if unknown:
        raise SystemExit(f"--skip names not found: {sorted(unknown)}")
    for n in sorted(skip):
        print(f"SKIP {n}")
    items = []
    for p in files:
        if p.stem in skip:
            continue
        meta, body = parse(p)
        dates = [str(d) for d in meta["seen_dates"]]
        items.append(dict(name=p.stem, title=meta["title"], description=rule_line(body), category=str(meta["category"]),
                          seen_dates=dates, created=dt.datetime.fromisoformat(f"{dates[0]}T12:00:00+08:00"),
                          body=body.rstrip() + f"\n\n---\n来源：deepvision-ads {meta.get('origin', '')}（2026-10-16 导入 EverOS）\n"))
    if dry:
        for i in items:
            print(f"DRY {i['name']} ({len(i['name'])}) {i['category']} {i['seen_dates']}")
        print(f"TOTAL {len(items)}")
        return 0
    from everos.core.persistence import MemoryRoot
    from everos.infra.persistence.markdown.mds.agent_skill import AgentSkillFrontmatter
    from everos.infra.persistence.markdown.writers.agent_skill_writer import AgentSkillWriter
    writer = AgentSkillWriter(root=MemoryRoot.resolve())
    for i in items:
        safe = AgentSkillFrontmatter.sanitize_skill_name(i["name"])
        if safe != i["name"]:
            print(f"WARN slug sanitized {i['name']} -> {safe}", file=sys.stderr)
        fm = AgentSkillFrontmatter(
            id=f"skill_{safe}", type="agent_skill", schema_version=1, agent_id=AGENT_ID, track="agent",
            name=safe, description=i["description"][:500], confidence=0.95, maturity_score=0.85,
            source_case_ids=[], cluster_id=None, created_at=i["created"], updated_at=i["created"],
            category=i["category"], seen_count=len(i["seen_dates"]), seen_dates=i["seen_dates"], source=SOURCE_TAG,
        )
        out = await writer.write_main(AGENT_ID, safe, frontmatter=fm, body=i["body"], app_id=APP_ID, project_id=PROJECT_ID)
        print(f"OK {safe} -> {out}")
    print(f"TOTAL {len(items)}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[1:]
    skip: set[str] = set()
    if "--skip" in argv:
        i = argv.index("--skip")
        skip = {x for x in argv[i + 1].split(",") if x}
        del argv[i : i + 2]
    args = [a for a in argv if a != "--dry-run"]
    raise SystemExit(asyncio.run(main(Path(args[0] if args else Path(__file__).parent / "source"), "--dry-run" in sys.argv, skip)))
