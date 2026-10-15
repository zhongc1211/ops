#!/usr/bin/env python3
"""Import xinyue LESSONS.md + lessons/*.md into EverOS agent_skills.

Writes under:
  <EVEROS_ROOT>/xinyue/xinyue-site/agents/coding-xinyue-site/skills/skill_<name>/SKILL.md
"""
from __future__ import annotations

import asyncio
import datetime as dt
import re
import sys
from pathlib import Path

import yaml

from everos.core.persistence import MemoryRoot
from everos.infra.persistence.markdown.mds.agent_skill import AgentSkillFrontmatter
from everos.infra.persistence.markdown.writers.agent_skill_writer import AgentSkillWriter

APP_ID = "xinyue"
PROJECT_ID = "xinyue-site"
AGENT_ID = "coding-xinyue-site"

# Done-right rows from LESSONS.md (not separate lesson files).
DONE_RIGHT = [
    {
        "name": "done-right-verification-five-sections",
        "title": "验证记录固定五节",
        "date": "2026-10-13",
        "body": (
            "**做法：** 验证记录固定五节：回退测试（改动前后各一次 CI）、真实使用证据、"
            "跑在哪个提交、回滚方式、没跑的。\n\n"
            "**出处：** #74 的验证评论\n"
        ),
    },
    {
        "name": "done-right-list-unverified-in-ship-comment",
        "title": "上线评论单列没有验证的",
        "date": "2026-10-13",
        "body": (
            "**做法：** 上线评论单列「没有验证的」：没有用真实口令登录、没有实际调用模型、"
            "没有在真实手机上试玩。\n\n"
            "**出处：** #61–#67、#73 的上线评论，Linear PER-37 到 PER-43\n"
        ),
    },
    {
        "name": "done-right-rollback-commands-in-ship-comment",
        "title": "上线评论给出可执行回滚命令和版本号",
        "date": "2026-10-13",
        "body": (
            "**做法：** 上线评论里给出可以直接执行的回滚命令和回滚版本号。\n\n"
            "**出处：** #61–#67、#73 的上线评论；PER-28 的上线评论\n"
        ),
    },
    {
        "name": "done-right-confirm-fail-before-fix",
        "title": "修复前先确认新用例会失败",
        "date": "2026-10-13",
        "body": (
            "**做法：** 修复前先确认新用例会失败：新增用例和原有的 403 用例在修复前都失败，"
            "修复后通过。\n\n"
            "**出处：** #66、#72\n"
        ),
    },
    {
        "name": "done-right-explain-changed-test-premise",
        "title": "改用例前提时在 PR 正文单独说明",
        "date": "2026-10-13",
        "body": (
            "**做法：** 改了一条用例的前提时，在 PR 正文里单独说明原来测什么、现在测什么、为什么。\n\n"
            "**出处：** #72「一个用例改了前提」\n"
        ),
    },
    {
        "name": "done-right-dont-claim-untriggered-as-verified",
        "title": "未实际触发的功能不要写成验证过",
        "date": "2026-10-13",
        "body": (
            "**做法：** 没有在 testing 上制造真实故障时，写明「这句话的显示没有实际触发过」，"
            "不把部署成功写成功能验证过。\n\n"
            "**出处：** #66\n"
        ),
    },
]


def _parse_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end < 0:
        return {}, text
    meta = yaml.safe_load(text[3:end]) or {}
    body = text[end + 4 :].lstrip("\n")
    return meta, body


def _rule_line(body: str) -> str:
    m = re.search(r"\*\*规则[：:]\*\*\s*(.+)", body)
    if m:
        return m.group(1).strip()
    # first non-empty non-heading line
    for line in body.splitlines():
        s = line.strip()
        if s and not s.startswith("#") and not s.startswith("---"):
            return s[:200]
    return ""


def _skill_body_from_lesson(meta: dict, body: str) -> str:
    title = meta.get("title") or "lesson"
    # Keep the original lesson body (already has 规则 / Seen / sections).
    # Only ensure an H1 title and import footer.
    body_wo_h1 = re.sub(r"^#\s+.+\n+", "", body, count=1).strip()
    parts = [
        f"# {title}",
        "",
        body_wo_h1,
        "",
        "---",
        "来源：xinyue-site docs/solutions/lessons（2026-10-16 导入 EverOS）",
        "",
    ]
    return "\n".join(parts)


async def write_skill(
    writer: AgentSkillWriter,
    *,
    name: str,
    description: str,
    body: str,
    category: str,
    seen_count: int,
    seen_dates: list[str],
    created: dt.datetime,
) -> Path:
    safe = AgentSkillFrontmatter.sanitize_skill_name(name)
    fm = AgentSkillFrontmatter(
        id=f"skill_{safe}",
        type="agent_skill",
        schema_version=1,
        agent_id=AGENT_ID,
        track="agent",
        name=safe,
        description=description[:500],
        confidence=0.95,
        maturity_score=0.85,
        source_case_ids=[],
        cluster_id=None,
        created_at=created,
        updated_at=created,
        # extras allowed by model_config
        category=category,
        seen_count=int(seen_count),
        seen_dates=list(seen_dates),
        source="xinyue-lessons-import-2026-10-16",
    )
    path = await writer.write_main(
        AGENT_ID,
        safe,
        frontmatter=fm,
        body=body,
        app_id=APP_ID,
        project_id=PROJECT_ID,
    )
    return path


async def main(lessons_dir: Path) -> int:
    root = MemoryRoot.resolve()
    writer = AgentSkillWriter(root=root)
    written: list[tuple[str, str]] = []

    for path in sorted(lessons_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        meta, body = _parse_frontmatter(text)
        name = path.stem  # already hyphenated slug
        title = meta.get("title") or name
        rule = _rule_line(body)
        description = rule or title
        kind = meta.get("kind") or meta.get("category") or "lessons"
        seen = meta.get("seen") or 1
        seen_dates = meta.get("seen_dates") or [str(meta.get("date") or "2026-10-13")]
        # normalize dates to strings
        seen_dates = [str(d) for d in seen_dates]
        date_s = str(meta.get("date") or seen_dates[0])
        created = dt.datetime.fromisoformat(f"{date_s}T12:00:00+08:00")
        skill_body = _skill_body_from_lesson(meta, body)
        out = await write_skill(
            writer,
            name=name,
            description=description,
            body=skill_body,
            category=str(kind),
            seen_count=int(seen),
            seen_dates=seen_dates,
            created=created,
        )
        written.append((name, str(out)))
        print(f"OK lesson {name} -> {out}")

    for item in DONE_RIGHT:
        created = dt.datetime.fromisoformat(f"{item['date']}T12:00:00+08:00")
        body = (
            f"# {item['title']}\n\n"
            f"{item['body']}\n"
            "category: done_right（不进 Seen×3 升级）\n\n"
            "---\n来源：xinyue-site docs/solutions/LESSONS.md Done right（2026-10-16 导入 EverOS）\n"
        )
        out = await write_skill(
            writer,
            name=item["name"],
            description=item["title"],
            body=body,
            category="done_right",
            seen_count=1,
            seen_dates=[item["date"]],
            created=created,
        )
        written.append((item["name"], str(out)))
        print(f"OK done_right {item['name']} -> {out}")

    print(f"TOTAL {len(written)}")
    for n, p in written:
        print(f"  {n}\t{p}")
    return 0


if __name__ == "__main__":
    lessons = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/xinyue-lessons-import/lessons")
    raise SystemExit(asyncio.run(main(lessons)))
