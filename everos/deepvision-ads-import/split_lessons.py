#!/usr/bin/env python3
"""Split LESSONS-dv-ads.md (one file, 16 skills) into source/<slug>.md with the same
frontmatter shape import/import_lessons.py reads (title/date/category/kind/seen/seen_dates)."""
import re, sys
from pathlib import Path
src, out = Path(sys.argv[1]), Path(sys.argv[2])
text = src.read_text(encoding="utf-8")
parts = re.split(r"^## skill: (\S+)\s*$", text, flags=re.M)[1:]
n = 0
for slug, chunk in zip(parts[0::2], parts[1::2]):
    m = re.search(r"```yaml\n(.*?)```\n", chunk, re.S)
    meta = dict(re.findall(r"^(\w+): (.*)$", m.group(1), re.M))
    body = chunk[m.end():].strip() + "\n"
    dates = [d.strip() for d in meta["seen_dates"].strip("[]").split(",")]
    assert len(slug) <= 50, slug
    fm = (f"---\ntitle: {meta['title']}\ndate: {dates[0]}\ncategory: {meta['category']}\n"
          f"kind: {meta['category']}\nseen: {len(dates)}\nseen_dates: [{', '.join(dates)}]\n"
          f"origin: \"{meta['origin']}\"\n---\n\n")
    (out / f"{slug}.md").write_text(fm + body, encoding="utf-8")
    n += 1
print(n)
