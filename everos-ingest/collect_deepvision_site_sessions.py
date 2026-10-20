#!/usr/bin/env python3
"""Collect deepvision-site coding sessions for one SGT calendar day into HANDOFF JSONL.

Rules (Zack 2026-10-16 19:07, FDV-68 EXCLUSION-OPTIONS.md A+E+H+K):
  H  a session belongs to deepvision-site when its cwd's git remote names the repo
     `deepvision-site` exactly (box ~/orca/workspaces/deepvision-site/…, /workspace/repos/…;
     iMac ~/orca/workspaces/site/…); never by a name substring (deepvision-ads stays out).
  A  setup/config rules are checked before the ticket guard, so "FDV-68 … 接入 EverOS" is
     excluded even though it names a ticket.
  E  setup/config patterns are the xinyue ones (SETUP_TASK_RES), unchanged; brief instructions
     ("不调 everos", "挂了就记一句", "不打印密钥") are cut first (base.setup_match, 10-19 FDV-67).
  K  the deepvision-site night review's own sessions (43c55a22) are excluded.
  OD (Coding助手 19:21) besides H, sessions whose cwd starts with the fixed Open Design project
     prefix below (FDV-61 redesign work, not a git repo) also belong to deepvision-site. The full
     prefix is hard-coded; no substring matching.
  secret-like (dr eggbot 10-18 16:11) a session the rules above keep is still excluded whole when
     its title, task headline or brief headline names a key word (KEYS, AI KEY, API KEY, SECRET,
     REVOKE, API/ACCESS TOKEN, 密钥 …), or the task, brief or any transcript line holds an env secret value or a
     token format; see collect_xinyue_sessions.secret_like_reason.

Reuses helpers from collect_xinyue_sessions.py (same directory) without changing it.

Usage:
  MACHINE=box python3 collect_deepvision_site_sessions.py --date D [--out PATH] [--dry-run]
  --dry-run   print a table of kept/excluded sessions with the rule that decided each one;
              writes only the --out files you pass (default: nothing under /var/lib).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import collect_xinyue_sessions as base  # noqa: E402

REPO_NAME = "deepvision-site"
REMOTE_RE = re.compile(r"[:/](?:[\w.-]+/)?([\w.-]+?)(?:\.git)?/?$")
NIGHT_REVIEW_MARKERS = (
    ("night-review", re.compile(r"deepvision官网夜审（每天 00:10 SGT 一次")),  # K, current 43c55a22
    ("night-review", re.compile(r"deepvision官网夜审（每晚一次")),            # K, 43c55a22 before 13:22
)
DEV_GUARD_RE = re.compile(base.DEV_GUARD_RE.pattern + r"|\bFDV-\d+", re.I)
BRIEF_ANY_RE = re.compile(r"((?:~/|/|\.{0,2}/?)[\w.\-/一-鿿]+\.md)")

# OD: full prefix, iMac Open Design app data; a project dir name must start with "fdv61-".
OD_PREFIX = os.path.join(str(Path.home()), "Library/Application Support/Open Design/namespaces/release-stable/data/projects/fdv61-")

_remote_cache: dict[str, str | None] = {}


def repo_of(path: str | None) -> str | None:
    """Repo name from `git remote get-url origin` of path (or its nearest existing parent)."""
    if not path:
        return None
    p = Path(path)
    while not p.exists() and p != p.parent:
        p = p.parent
    key = str(p)
    if key not in _remote_cache:
        try:
            r = subprocess.run(["git", "-C", key, "remote", "get-url", "origin"],
                               capture_output=True, text=True, timeout=10)
            m = REMOTE_RE.search(r.stdout.strip()) if r.returncode == 0 else None
            _remote_cache[key] = m.group(1) if m else None
        except (OSError, subprocess.TimeoutExpired):
            _remote_cache[key] = None
    return _remote_cache[key]


def transcript_cwd(jsonl: Path) -> str | None:
    try:
        with jsonl.open("r", encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 50:
                    break
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if o.get("cwd"):
                    return o["cwd"]
    except OSError:
        pass
    return None


def brief_text(first: str, cwd: str | None) -> tuple[str, str]:
    """Like base.brief_text, but also resolves ~/ and relative .md paths (against the session cwd, R5)."""
    head = base.task_headline(first, 1)
    if len(head) > 160:
        return "", ""
    for m in BRIEF_ANY_RE.finditer(head):
        raw = m.group(1)
        raw = os.path.expanduser(raw)
        p = Path(raw) if raw.startswith("/") else (Path(cwd) / raw if cwd else None)
        if not p:
            continue
        try:
            return p.read_text(encoding="utf-8", errors="replace")[:4000], str(p)
        except OSError:
            continue
    return "", ""


PASTED_RE = re.compile(r"^\s*<pasted_content\b[^>]*>\s*(.*?)\s*(?:</pasted_content>|$)", re.S)


def first_user_text(jsonl: str | None) -> str:
    """Like base.first_user_text, but a message wrapped in <pasted_content …> is unwrapped
    instead of skipped (base skips anything starting with "<")."""
    if not jsonl:
        return ""
    try:
        with open(jsonl, "r", encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 400:
                    break
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if o.get("type") != "user" or o.get("isMeta") or o.get("isSidechain"):
                    continue
                c = (o.get("message") or {}).get("content")
                if isinstance(c, list):
                    c = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                c = (c or "").strip()
                m = PASTED_RE.match(c)
                if m:
                    c = m.group(1).strip()
                if not c or c.startswith("<"):
                    continue
                return c
    except OSError:
        pass
    return ""


def task_type(first: str, cwd: str | None) -> tuple[str, str]:
    """(kind, rule) — kind is dev or an exclusion kind; rule names the deciding rule."""
    for kind, rx in tuple(base.EXCLUDE_PROMPT_MARKERS) + NIGHT_REVIEW_MARKERS:
        if rx.search(first):
            rule = "K" if rx in [r for _, r in NIGHT_REVIEW_MARKERS] else "marker"
            return kind, f"{rule}: opening prompt is {kind}"
    texts = [("task", first)]
    b, bpath = brief_text(first, cwd)
    if b:
        texts.append((f"brief {bpath}", b))
    for src, t in texts:
        head = base.task_headline(t)
        m = base.setup_match(head)  # A: setup before ticket guard; E: xinyue patterns
        if m:
            return "setup", f"A+E: {src} headline is setup/config: {m.group(0)[:40]!r}"
    for src, t in texts:
        m = DEV_GUARD_RE.search(base.task_headline(t))
        if m:
            return "dev", f"ticket guard: {src} headline names {m.group(0)!r}"
    return "dev", "no exclusion rule matched"


def collect(machine: str, day: str) -> tuple[list[dict], list[dict], list[dict]]:
    day_start, day_end, start_ms, end_ms = base.sgt_day(day)
    data = base.run_json([base.ORCA, "worktree", "list", "--json"], timeout=120)
    worktrees = data.get("result", {}).get("worktrees") or data.get("worktrees") or []
    wt_by_path = {}
    for w in worktrees:
        p = (w.get("path") or "").rstrip("/")
        if p and repo_of(p) == REPO_NAME:  # H
            wt_by_path[os.path.realpath(p)] = w

    rows: list[dict] = []
    other_repo: list[dict] = []
    seen_wt: set[str] = set()
    projects = Path.home() / ".claude" / "projects"
    for d in sorted(projects.iterdir()) if projects.is_dir() else []:
        if not d.is_dir():
            continue
        for sf in d.glob("*.jsonl"):
            started, ended = base.session_timestamps(sf)
            if not base.overlaps_day(started, ended, day_start, day_end, sf.stat().st_mtime):
                continue
            cwd = transcript_cwd(sf)
            repo = repo_of(cwd)
            if repo == REPO_NAME:
                include_by = "H: git remote is deepvision-site"
            elif cwd and cwd.startswith(OD_PREFIX):
                include_by = "OD: Open Design projects/fdv61-* prefix"
            else:
                other_repo.append({"session_id": sf.stem, "cwd": cwd, "repo": repo})
                continue
            real = os.path.realpath(cwd) if cwd and os.path.exists(cwd) else cwd
            w = next((wt_by_path[k] for k in wt_by_path if real == k or (real or "").startswith(k + "/")), None)
            if w:
                seen_wt.add(os.path.realpath(w["path"]))
            branch = (w.get("branch") or "").replace("refs/heads/", "") if w else None
            wpath = w.get("path") if w else cwd
            rows.append({
                "session_id": sf.stem,
                "machine": machine,
                "workspace": (w.get("displayName") if w else None) or cwd,
                "workspace_path": wpath,
                "linear_id": w.get("linkedLinearIssue") if w else None,
                "started_at": base.to_sgt_iso(started),
                "ended_at": base.to_sgt_iso(ended),
                "status": base.map_status(w.get("workspaceStatus"), False) if w else "unknown",
                "transcript_path": str(sf),
                "status_md_path": str(Path(wpath) / "status.md") if wpath and (Path(wpath) / "status.md").is_file() else None,
                "summary_path": base.find_summary(wpath) if wpath else None,
                "git_branch": branch or None,
                "pr_urls": base.gh_pr_urls(wpath, branch) if branch else [],
                "_cwd": cwd,
                "_include": include_by,
            })
    # worktree active on D but no transcript (e.g. pi or another agent) → placeholder row, like xinyue
    for k, w in wt_by_path.items():
        la, ca = w.get("lastActivityAt") or 0, w.get("createdAt") or 0
        if k in seen_wt or not ((start_ms <= la < end_ms) or (start_ms <= ca < end_ms)):
            continue
        raw = str(w.get("worktreeInstanceId") or w.get("worktreeId") or k)
        rows.append({
            "session_id": "orca-wt-" + hashlib.sha1(raw.encode()).hexdigest()[:12],
            "machine": machine, "workspace": w.get("displayName") or k, "workspace_path": w.get("path"),
            "linear_id": w.get("linkedLinearIssue"), "started_at": base.iso_or_none(ca), "ended_at": base.iso_or_none(la),
            "status": base.map_status(w.get("workspaceStatus"), False), "transcript_path": None,
            "status_md_path": None, "summary_path": None,
            "git_branch": (w.get("branch") or "").replace("refs/heads/", "") or None, "pr_urls": [], "_cwd": w.get("path"),
            "_include": "H: Orca worktree with deepvision-site remote, active on D, no Claude transcript (placeholder)",
        })
    rows.sort(key=lambda r: r.get("started_at") or "")
    kept, excluded = [], []
    literals = base.load_literal_secrets()
    for r in rows:
        wp = (r.get("workspace_path") or "").rstrip("/")
        if wp and base.EXCLUDE_PATH_RE.search(wp):
            kind, rule = "night-review", "K: night-review auto-run worktree path"
        else:
            first = first_user_text(r.get("transcript_path"))
            kind, rule = task_type(first, r.get("_cwd"))
            if kind == "dev":  # whole-session secret-like exclusion (see base.secret_like_reason)
                b, bpath = brief_text(first, r.get("_cwd"))
                why = base.secret_like_reason(
                    [("title", r.get("workspace") or ""), ("task headline", base.task_headline(first)),
                     (f"brief {bpath} headline", base.task_headline(b))],
                    [first, b], r.get("transcript_path"), literals)
                if why:
                    kind, rule = "secret-like", why
        r["_rule"] = rule
        (kept if kind == "dev" else excluded).append(r)
    return kept, excluded, other_repo


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=os.environ.get("D") or datetime.now(base.SGT).strftime("%Y-%m-%d"))
    ap.add_argument("--out", default="")
    ap.add_argument("--machine", default=os.environ.get("MACHINE") or ("imac" if sys.platform == "darwin" else "box"))
    ap.add_argument("--stage-dir", default="", help="copy redacted transcripts here (for pushing to box)")
    ap.add_argument("--remote-dir", default="", help="path the staged transcripts will have on box")
    ap.add_argument("--dry-run", action="store_true", help="print kept/excluded with rules; no staging")
    args = ap.parse_args()
    if args.machine not in ("box", "imac", "mba"):
        print(f"bad machine: {args.machine}", file=sys.stderr)
        return 2
    kept, excluded, other = collect(args.machine, args.date)
    if args.dry_run:
        print(f"date={args.date} machine={args.machine} kept={len(kept)} excluded={len(excluded)} other_repo={len(other)}")
        literals = base.load_literal_secrets()
        for tag, rs in (("KEEP", kept), ("EXCLUDE", excluded)):
            for r in rs:
                head = base.task_headline(first_user_text(r.get("transcript_path")))[:60] or "(no transcript)"
                head = base.redact_text(head, literals)[0].replace("\t", " ")
                print(f"{tag}\t{r['session_id']}\t{r.get('workspace')}\t{r.get('linear_id') or '-'}\t{r['_include']}\t{r['_rule']}\t{head}")
        repos: dict[str, int] = {}
        for o in other:
            repos[str(o["repo"])] = repos.get(str(o["repo"]), 0) + 1
        print("OTHER_REPO\t" + json.dumps(repos, ensure_ascii=False, sort_keys=True))
        if not args.out:
            return 0
    out = Path(args.out or f"/var/lib/everos-ingest/{REPO_NAME}/{args.date}/sessions-{args.machine}.jsonl")
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.stage_dir and not args.dry_run:
        if not args.remote_dir:
            print("--stage-dir needs --remote-dir", file=sys.stderr)
            return 2
        literals = base.load_literal_secrets()
        if not literals:
            print("no literal secrets loaded from env files; refusing to stage transcripts", file=sys.stderr)
            return 3
        stage = Path(args.stage_dir)
        if stage.exists():
            import shutil
            shutil.rmtree(stage)
        stage.mkdir(parents=True)
        os.chmod(stage, 0o700)
        for r in kept:
            src = r.get("transcript_path")
            r["transcript_source_path"] = src
            if not src or not os.access(src, os.R_OK):
                r["transcript_path"] = None
                continue
            name = f"{r['session_id']}.jsonl"
            red, dropped = base.stage_filtered_transcript(src, stage / name, literals)
            r["transcript_path"] = f"{args.remote_dir.rstrip('/')}/{name}"
            r["transcript_redactions"], r["transcript_dropped_lines"] = red, dropped
    with out.with_name(out.stem + ".excluded.jsonl").open("w", encoding="utf-8") as f:
        for r in excluded:
            f.write(json.dumps({"session_id": r["session_id"], "machine": args.machine, "workspace": r.get("workspace"),
                                "transcript_path": r.get("transcript_path"), "included_by": r["_include"], "reason": r["_rule"]}, ensure_ascii=False) + "\n")
    with out.open("w", encoding="utf-8") as f:
        for r in kept:
            r["include_rule"] = r.pop("_rule")
            r["included_by"] = r.pop("_include")
            r.pop("_cwd", None)
            r.pop("workspace_path", None)
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(kept)} sessions -> {out}; excluded {len(excluded)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:  # exit 4 = collector error (1 is reserved for "done, do not start the model")
        print(f"collector error: {e}", file=sys.stderr)
        raise SystemExit(4)
