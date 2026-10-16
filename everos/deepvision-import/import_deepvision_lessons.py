#!/usr/bin/env python3
"""Import deepvision-site docs/solutions/**/*.md into EverOS agent_skills (same method as
the xinyue import: AgentSkillWriter.write_main on site; the HTTP API cannot write agent_skill
while skill_extraction is off).

Scope: app_id=deepvision project_id=deepvision-site agent_id=coding-deepvision-site user_id=zack.
Writes under:
  <EVEROS_ROOT>/<app_id>/<project_id>/agents/<agent_id>/skills/skill_<name>/SKILL.md

Run on site (needs the everos package):
  sudo -u everos env EVEROS_ROOT=/var/lib/everos \
    /opt/everos/venv/bin/python3 \
    import_deepvision_lessons.py <checkout>/docs/solutions
"""
from __future__ import annotations

import asyncio
import datetime as dt
import os
import re
import sys
from pathlib import Path

# Approved scope (Zack 2026-10-16 13:07): app/project isolation, user_id unified as "zack".
APP_ID_DEFAULT, PROJECT_ID_DEFAULT, AGENT_ID_DEFAULT = "deepvision", "deepvision-site", "coding-deepvision-site"
USER_ID = "zack"


def scope() -> tuple[str, str, str]:
    return (os.environ.get("EVEROS_APP_ID") or APP_ID_DEFAULT,
            os.environ.get("EVEROS_PROJECT_ID") or PROJECT_ID_DEFAULT,
            os.environ.get("EVEROS_AGENT_ID") or AGENT_ID_DEFAULT)


SOURCE = "deepvision-site-solutions-import-2026-10-16"


def parse(text: str) -> tuple[dict, str]:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end > 0:
            meta = {}
            for line in text[3:end].splitlines():  # flat `key: value` only; same result on box and site
                k, sep, v = line.partition(":")
                if sep and k.strip() and not k.startswith(" "):
                    meta[k.strip()] = v.strip().strip('"')
            return meta, text[end + 4 :].lstrip("\n")
    return {}, text


def slug_and_date(path: Path) -> tuple[str, str]:
    m = re.match(r"(.+)-(\d{4}-\d{2}-\d{2})$", path.stem)
    return (m.group(1), m.group(2)) if m else (path.stem, "2026-10-16")


def title_of(meta: dict, body: str, slug: str) -> str:
    if meta.get("title"):
        return str(meta["title"]).strip()
    m = re.search(r"^#\s+(.+)$", body, re.M)
    return m.group(1).strip() if m else slug


def skills(solutions: Path) -> list[dict]:
    out = []
    for path in sorted(solutions.rglob("*.md")):
        text = path.read_text(encoding="utf-8")
        meta, body = parse(text)
        slug, date_s = slug_and_date(path)
        date_s = str(meta.get("date") or date_s)
        title = title_of(meta, body, slug)
        rel = path.relative_to(solutions.parent.parent)  # docs/solutions/<cat>/<file>
        if meta.get("title") or not re.match(r"^#\s", body):
            body = f"# {title}\n\n{body}"
        skill_body = f"{body.rstrip()}\n\n---\n来源：deepvision-site {rel}（2026-10-16 导入 EverOS）\n"
        out.append({
            "slug": slug,
            "title": title,
            "date": date_s,
            "category": str(meta.get("category") or path.parent.name),
            "body": skill_body,
            "rel": str(rel),
        })
    return out


async def main(solutions: Path) -> int:
    from everos.core.persistence import MemoryRoot
    from everos.infra.persistence.markdown.mds.agent_skill import AgentSkillFrontmatter
    from everos.infra.persistence.markdown.writers.agent_skill_writer import AgentSkillWriter

    APP_ID, PROJECT_ID, AGENT_ID = scope()
    items = skills(solutions)
    if not items:
        raise SystemExit(f"no *.md under {solutions}")
    writer = AgentSkillWriter(root=MemoryRoot.resolve())
    for it in items:
        safe = AgentSkillFrontmatter.sanitize_skill_name(it["slug"])
        created = dt.datetime.fromisoformat(f"{it['date']}T12:00:00+08:00")
        fm = AgentSkillFrontmatter(
            id=f"skill_{safe}", type="agent_skill", schema_version=1, agent_id=AGENT_ID,
            track="agent", name=safe, description=it["title"][:500], confidence=0.95,
            maturity_score=0.85, source_case_ids=[], cluster_id=None,
            created_at=created, updated_at=created,
            category=it["category"], seen_count=1, seen_dates=[it["date"]], source=SOURCE,
        )
        path = await writer.write_main(AGENT_ID, safe, frontmatter=fm, body=it["body"],
                                       app_id=APP_ID, project_id=PROJECT_ID)
        print(f"OK {it['rel']} -> {path}")
    print(f"TOTAL {len(items)}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    raise SystemExit(asyncio.run(main(Path(sys.argv[1]).resolve())))
