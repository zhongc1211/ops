#!/usr/bin/env python3
"""Collect deepvision-ads or vllm-omni coding sessions for one SGT calendar day into HANDOFF JSONL.

Same rules and output as collect_deepvision_site_sessions.py (deepvision官网, FDV-68 A+E+H+K), only the
repo changes (Zack 10-18 13:18「补」, ID 10-16 批):
  H  the session's cwd has a git remote whose repo name is exactly REPO (deepvision-ads stays apart
     from deepvision-site; vllm-omni matches the fork and the upstream checkout);
  A+E  setup/config sessions are excluded before the ticket guard (xinyue patterns);
  K  that project's own night review sessions are excluded (ads 9b5c20e7, vllm c392a743);
  ticket guard: FDV-N for ads, PER-N (already in the xinyue guard) for vllm.
  No OD rule: the Open Design prefix is deepvision-site only.
  secret-like whole-session exclusion comes with the site collector (10-18 16:11).

Runs the deepvision-site collector with its module settings swapped for the chosen repo, so the
site script itself is not changed.

Usage:
  MACHINE=box python3 collect_repo_sessions.py --repo deepvision-ads --date D [--out PATH] [--dry-run]
  (all other options are the deepvision-site collector's: --stage-dir, --remote-dir, --machine)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import collect_deepvision_site_sessions as dvs  # noqa: E402

SITE = dvs.REPO_NAME
PROFILES = {
    "deepvision-ads": {
        "night_review": (re.compile(r"deepvision广告夜审（每晚一次"),),   # K, 9b5c20e7
        "ticket": r"|\bFDV-\d+",
    },
    "vllm-omni": {
        "night_review": (re.compile(r"vllm-omni夜审（每晚一次"),),        # K, c392a743
        "ticket": "",                                                     # PER-N is in the base guard
    },
}


def configure(repo: str) -> None:
    p = PROFILES[repo]
    dvs.REPO_NAME = repo
    dvs.NIGHT_REVIEW_MARKERS = tuple(("night-review", rx) for rx in p["night_review"])
    dvs.DEV_GUARD_RE = re.compile(dvs.base.DEV_GUARD_RE.pattern + p["ticket"], re.I)
    dvs.OD_PREFIX = "\0"  # no path starts with NUL: the OD rule never applies
    site_collect = dvs.collect

    def collect(machine: str, day: str):
        kept, excluded, other = site_collect(machine, day)
        for r in kept + excluded:  # the site collector's included_by text names its own repo
            r["_include"] = r["_include"].replace(f"remote is {SITE}", f"remote is {repo}").replace(
                f"with {SITE} remote", f"with {repo} remote")
        return kept, excluded, other

    dvs.collect = collect


def main() -> int:
    argv = sys.argv[1:]
    if "--repo" not in argv or argv.index("--repo") + 1 >= len(argv):
        print("usage: collect_repo_sessions.py --repo {%s} ..." % ",".join(PROFILES), file=sys.stderr)
        return 2
    i = argv.index("--repo")
    repo = argv[i + 1]
    if repo not in PROFILES:
        print(f"unknown repo: {repo} (known: {', '.join(PROFILES)})", file=sys.stderr)
        return 2
    configure(repo)
    sys.argv = [sys.argv[0]] + argv[:i] + argv[i + 2:]
    return dvs.main()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:  # exit 4 = collector error (1 is reserved for "done, do not start the model")
        print(f"collector error: {e}", file=sys.stderr)
        raise SystemExit(4)
