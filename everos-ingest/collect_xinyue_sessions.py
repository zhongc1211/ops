#!/usr/bin/env python3
"""Collect 心月 (xinyue-site) coding sessions for one SGT calendar day into HANDOFF JSONL.

Usage:
  MACHINE=box  python3 collect_xinyue_sessions.py [--date YYYY-MM-DD] [--out PATH]
  MACHINE=imac python3 collect_xinyue_sessions.py [--date YYYY-MM-DD] [--out PATH]

Discovers Orca xinyue worktrees with activity on day D, plus Claude Code
transcripts under ~/.claude/projects for those workspaces. Does not print secrets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

SGT = timezone(timedelta(hours=8))
ORCA = os.environ.get("ORCA_BIN") or ("/usr/local/bin/orca" if sys.platform == "darwin" else "orca")


def sgt_day(d: str) -> tuple[datetime, datetime, int, int]:
    start = datetime.strptime(d, "%Y-%m-%d").replace(tzinfo=SGT)
    end = start + timedelta(days=1)
    return start, end, int(start.timestamp() * 1000), int(end.timestamp() * 1000)


def iso_or_none(ms: int | None) -> str | None:
    if not ms:
        return None
    return datetime.fromtimestamp(ms / 1000, SGT).isoformat()


def run_json(cmd: list[str], timeout: int = 90) -> Any:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(f"cmd failed ({p.returncode}): {' '.join(cmd)}\n{p.stderr[-800:]}")
    return json.loads(p.stdout)


def is_xinyue_worktree(w: dict) -> bool:
    path = (w.get("path") or "").lower()
    repo = str(w.get("repo") or "").lower()
    name = w.get("displayName") or ""
    if "xinyue" in path or "xinyue" in repo or "心月" in name:
        return True
    # exclude pure ops night-review auto-runs? keep them if under xinyue-site path
    return False


def claude_project_dir(workspace: str) -> Path | None:
    """Map a workspace path to Claude's encoded project directory."""
    home = Path.home()
    projects = home / ".claude" / "projects"
    if not projects.is_dir():
        return None
    # Claude encodes path: /home/box/foo -> -home-box-foo (non-alnum -> -)
    enc = re.sub(r"[^A-Za-z0-9]", "-", workspace)
    # trim duplicate dashes somewhat — Claude keeps consecutive dashes
    candidates = [
        projects / f"-{enc.lstrip('-')}",
        projects / enc,
    ]
    # Also fuzzy: any dir whose name contains distinctive path tail
    tail = Path(workspace).name
    if tail:
        for d in projects.iterdir():
            if not d.is_dir():
                continue
            # encoded name often has Chinese replaced by dashes; match by known PER or slug
            if enc[:40] and enc[:40] in d.name:
                candidates.append(d)
            # PER-48 style
            m = re.search(r"PER-(\d+)", workspace) or re.search(r"per-(\d+)", workspace, re.I)
            if m and f"PER-{m.group(1)}" in d.name.replace("---", "-"):
                # weak match — prefer exact
                candidates.append(d)
    for c in candidates:
        if c.is_dir():
            return c
    # last resort: scan for jsonl whose first user message cwd matches
    return None


def find_claude_project_dirs(workspace: str) -> list[Path]:
    home = Path.home()
    projects = home / ".claude" / "projects"
    if not projects.is_dir():
        return []
    enc = re.sub(r"[^A-Za-z0-9]", "-", str(Path(workspace).resolve() if Path(workspace).exists() else workspace))
    # Claude prefixes with leading -
    want = "-" + enc.lstrip("-")
    found: list[Path] = []
    exact = projects / want
    if exact.is_dir():
        found.append(exact)
    # Also try unresolved path encoding (as stored by Claude)
    enc2 = re.sub(r"[^A-Za-z0-9]", "-", workspace)
    want2 = "-" + enc2.lstrip("-")
    p2 = projects / want2
    if p2.is_dir() and p2 not in found:
        found.append(p2)
    if found:
        return found
    # fuzzy by unique suffix tokens (PER-N, slug)
    tokens = []
    m = re.search(r"(PER-\d+)", workspace, re.I)
    if m:
        tokens.append(m.group(1).upper())
    base = Path(workspace).name
    if base and len(base) >= 4:
        tokens.append(base)
    for d in projects.iterdir():
        if not d.is_dir():
            continue
        name_u = d.name.upper()
        # require xinyue marker in encoded form
        if "XINYUE" not in name_u and "心月" not in d.name:
            # encoded 心月 becomes dashes; require path fragment
            if "ORCA-WORKSPACES-XINYUE" not in name_u and "REPOS-XINYUE" not in name_u and "PI-REMOTE-XINYUE" not in name_u:
                if "TREEHOUSE-XINYUE" not in name_u and "FIRSTMATE" not in name_u:
                    continue
        for t in tokens:
            # PER-48 appears as PER-48 in dir name with dashes around
            t_enc = re.sub(r"[^A-Za-z0-9]", "-", t).upper()
            if t_enc and t_enc in name_u:
                found.append(d)
                break
    return found


def session_timestamps(jsonl: Path) -> tuple[str | None, str | None]:
    started = ended = None
    try:
        with jsonl.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts = o.get("timestamp")
                if not ts:
                    continue
                if started is None:
                    started = ts
                ended = ts
    except OSError:
        pass
    return started, ended


def to_sgt_iso(ts: str | None) -> str | None:
    if not ts:
        return None
    try:
        if ts.endswith("Z"):
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        else:
            dt = datetime.fromisoformat(ts)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(SGT).isoformat()
    except ValueError:
        return ts


def overlaps_day(started: str | None, ended: str | None, day_start: datetime, day_end: datetime, mtime: float) -> bool:
    """True if session activity intersects [day_start, day_end)."""
    def parse(ts: str | None) -> datetime | None:
        if not ts:
            return None
        try:
            if ts.endswith("Z"):
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            else:
                dt = datetime.fromisoformat(ts)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(SGT)
        except ValueError:
            return None

    s = parse(started)
    e = parse(ended) or s
    if s and e:
        return s < day_end and e >= day_start
    # fallback: file mtime in day
    mt = datetime.fromtimestamp(mtime, SGT)
    return day_start <= mt < day_end


def map_status(ws_status: str | None, live: bool) -> str:
    if live:
        return "running"
    s = (ws_status or "").lower()
    if s in ("completed", "done"):
        return "completed"
    if s in ("in-progress", "active"):
        return "running"
    if s in ("in-review",):
        return "completed"
    if s in ("stuck",):
        return "stuck"
    return "unknown"


def find_status_md(workspace: str) -> str | None:
    p = Path(workspace) / "status.md"
    if p.is_file():
        return str(p)
    # shared status
    for cand in (
        Path("/workspace/xinyue-web/status.md"),
        Path.home() / "xinyue-web/status.md",
    ):
        if cand.is_file():
            return str(cand)
    return None


def find_summary(workspace: str) -> str | None:
    root = Path(workspace)
    if not root.is_dir():
        return None
    for name in ("SUMMARY.md", "summary.md", "收尾.md", "report.md"):
        p = root / name
        if p.is_file():
            return str(p)
    # docs reports
    for p in root.glob("**/per-*-*.md"):
        if p.is_file() and p.stat().st_mtime > 0:
            return str(p)
    return None


def gh_pr_urls(workspace: str, branch: str | None) -> list[str]:
    if not branch:
        return []
    br = branch.replace("refs/heads/", "")
    try:
        p = subprocess.run(
            ["gh", "pr", "list", "--head", br, "--json", "url", "--limit", "5"],
            cwd=workspace if Path(workspace).is_dir() else None,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if p.returncode != 0:
            return []
        data = json.loads(p.stdout or "[]")
        return [x["url"] for x in data if x.get("url")]
    except Exception:
        return []


def live_terminal_count(worktree_id: str | None, path: str) -> int:
    try:
        sel = f"path:{path}" if path else None
        if not sel:
            return 0
        data = run_json([ORCA, "terminal", "list", "--worktree", sel, "--json"], timeout=60)
        terms = data.get("result", {}).get("terminals") or []
        return sum(1 for t in terms if t.get("connected") or t.get("agentIdentity"))
    except Exception:
        return 0


def collect(machine: str, day: str) -> list[dict]:
    day_start, day_end, start_ms, end_ms = sgt_day(day)
    data = run_json([ORCA, "worktree", "list", "--json"], timeout=120)
    worktrees = data.get("result", {}).get("worktrees") or data.get("worktrees") or []
    rows: list[dict] = []
    seen_sessions: set[str] = set()

    xinyue_wts = [w for w in worktrees if is_xinyue_worktree(w)]

    for w in xinyue_wts:
        path = w.get("path") or ""
        la = w.get("lastActivityAt") or 0
        ca = w.get("createdAt") or 0
        wt_on_day = (start_ms <= la < end_ms) or (start_ms <= ca < end_ms)
        linear = w.get("linkedLinearIssue")
        branch = w.get("branch")
        if branch:
            branch = branch.replace("refs/heads/", "")
        display = w.get("displayName") or path
        wt_id = w.get("worktreeId") or w.get("worktreeInstanceId") or path
        live = False
        try:
            live = live_terminal_count(w.get("worktreeId"), path) > 0
        except Exception:
            live = bool((w.get("liveTerminalCount") or 0) > 0) or (w.get("terminalVerdict") == "live")

        status_md = find_status_md(path)
        summary = find_summary(path)
        prs = gh_pr_urls(path, branch) if wt_on_day or live else []

        project_dirs = find_claude_project_dirs(path)
        session_files: list[Path] = []
        for pd in project_dirs:
            for f in pd.glob("*.jsonl"):
                # skip subagents folder files (handled only as parent)
                if "/subagents/" in str(f):
                    continue
                session_files.append(f)

        matched_any = False
        for sf in session_files:
            sid = sf.stem  # uuid
            started, ended = session_timestamps(sf)
            if not overlaps_day(started, ended, day_start, day_end, sf.stat().st_mtime):
                continue
            matched_any = True
            if sid in seen_sessions:
                continue
            seen_sessions.add(sid)
            st = map_status(w.get("workspaceStatus"), live and sf == max(session_files, key=lambda p: p.stat().st_mtime, default=sf))
            # if ended long ago and not live -> completed
            if not live and ended:
                st = "completed" if (w.get("workspaceStatus") or "").lower() in ("completed", "in-review", "done", "") else map_status(w.get("workspaceStatus"), False)
            rows.append(
                {
                    "session_id": sid,
                    "machine": machine,
                    "workspace": display,
                    "workspace_path": path,
                    "linear_id": linear,
                    "started_at": to_sgt_iso(started),
                    "ended_at": to_sgt_iso(ended) if not live else None,
                    "status": "running" if live and sf.stat().st_mtime >= (end_ms / 1000 - 86400) else st,
                    "transcript_path": str(sf),
                    "status_md_path": status_md,
                    "summary_path": summary,
                    "git_branch": branch,
                    "pr_urls": prs,
                }
            )

        # worktree active on day but no claude transcript matched → still emit a row
        if (wt_on_day or live) and not matched_any:
            raw = str(w.get("worktreeInstanceId") or w.get("worktreeId") or path or display)
            digest = hashlib.sha1(raw.encode()).hexdigest()[:12]
            sid = f"orca-wt-{digest}"
            if sid not in seen_sessions:
                seen_sessions.add(sid)
                rows.append(
                    {
                        "session_id": sid,
                        "machine": machine,
                        "workspace": display,
                        "workspace_path": path,
                        "linear_id": linear,
                        "started_at": iso_or_none(ca if start_ms <= ca < end_ms else (la if la else ca)),
                        "ended_at": None if live else iso_or_none(la),
                        "status": map_status(w.get("workspaceStatus"), live),
                        "transcript_path": None,
                        "status_md_path": status_md,
                        "summary_path": summary,
                        "git_branch": branch,
                        "pr_urls": prs,
                    }
                )

    # Also catch Claude xinyue sessions whose project dir wasn't linked to a listed worktree
    projects = Path.home() / ".claude" / "projects"
    if projects.is_dir():
        for d in projects.iterdir():
            if not d.is_dir():
                continue
            name_u = d.name.upper()
            if not (
                "XINYUE" in name_u
                or "ORCA-WORKSPACES-XINYUE" in name_u
                or "REPOS-XINYUE" in name_u
                or "PI-REMOTE-XINYUE" in name_u
                or "TREEHOUSE-XINYUE" in name_u
            ):
                continue
            for sf in d.glob("*.jsonl"):
                sid = sf.stem
                if sid in seen_sessions:
                    continue
                started, ended = session_timestamps(sf)
                if not overlaps_day(started, ended, day_start, day_end, sf.stat().st_mtime):
                    continue
                seen_sessions.add(sid)
                # recover cwd from a line if possible
                cwd = None
                try:
                    with sf.open("r", encoding="utf-8", errors="replace") as f:
                        for i, line in enumerate(f):
                            if i > 50:
                                break
                            try:
                                o = json.loads(line)
                            except json.JSONDecodeError:
                                continue
                            if o.get("cwd"):
                                cwd = o["cwd"]
                                break
                except OSError:
                    pass
                rows.append(
                    {
                        "session_id": sid,
                        "machine": machine,
                        "workspace": cwd or d.name,
                        "workspace_path": cwd,
                        "linear_id": None,
                        "started_at": to_sgt_iso(started),
                        "ended_at": to_sgt_iso(ended),
                        "status": "unknown",
                        "transcript_path": str(sf),
                        "status_md_path": find_status_md(cwd) if cwd else None,
                        "summary_path": find_summary(cwd) if cwd else None,
                        "git_branch": None,
                        "pr_urls": [],
                    }
                )

    # strip helper field workspace_path from output? Keep it — useful; schema allows extra fields.
    # Actually stick to schema + workspace_path is fine. HANDOFF lists required keys; extras OK for night review.
    # Sort by started_at
    rows.sort(key=lambda r: r.get("started_at") or "")
    # Remove workspace_path to stay close to schema (night review may not care)
    for r in rows:
        r.pop("workspace_path", None)
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=os.environ.get("D") or datetime.now(SGT).strftime("%Y-%m-%d"))
    ap.add_argument("--out", default="")
    ap.add_argument("--machine", default=os.environ.get("MACHINE") or ("imac" if sys.platform == "darwin" else "box"))
    args = ap.parse_args()
    machine = args.machine
    if machine not in ("box", "imac"):
        print(f"bad machine: {machine}", file=sys.stderr)
        return 2
    rows = collect(machine, args.date)
    out = args.out
    if not out:
        out = f"/var/lib/everos-ingest/xinyue/{args.date}/sessions-{machine}.jsonl"
    out_p = Path(out)
    out_p.parent.mkdir(parents=True, exist_ok=True)
    with out_p.open("w", encoding="utf-8") as f:
        for r in rows:
            # ensure required keys
            for k in (
                "session_id",
                "machine",
                "workspace",
                "linear_id",
                "started_at",
                "ended_at",
                "status",
                "transcript_path",
                "status_md_path",
                "summary_path",
                "git_branch",
                "pr_urls",
            ):
                r.setdefault(k, None if k != "pr_urls" else [])
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(rows)} sessions -> {out_p}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"collect failed: {e}", file=sys.stderr)
        raise
