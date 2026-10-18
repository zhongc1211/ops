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


# --- exclusion: smoke / night-review / collector / setup sessions never go to EverOS ------
# Decided by the session's task (first user message, plus the brief file it points to),
# not by the workspace name.
EXCLUDE_PATH_RE = re.compile(r"/auto-run-\d+-\d{8}T\d{4}$")
# Opening prompts of automation / smoke sessions (first real user message).
EXCLUDE_PROMPT_MARKERS = (
    ("smoke", re.compile(r"^\s*这是 EverOS MCP 冒烟")),
    ("smoke", re.compile(r"^\s*只调用下面(列出)?的只读工具")),
    # one-shot config/recall acceptance checks ("This is an isolated config check. ...")
    ("smoke", re.compile(r"^\s*This is an? (isolated |quick )?(config|smoke|recall|acceptance)[ -]?(check|test)", re.I)),
    ("smoke", re.compile(r"^\s*这是.{0,24}(冒烟|召回验收|recall 验收|验收检查)", re.I)),
    ("night-review", re.compile(r"心月夜审（xinyue-site，每晚一次")),
    ("night-review", re.compile(r"^\s*(【[^】]*】)?\s*心月夜审")),
    ("collector", re.compile(r"本任务的全部工作由预检脚本完成")),
)
# Setup/config of the agent tooling itself (EverOS wiring, MCP mounts, ingest/review
# automations). Matched only against the task headline (first lines of the task), so the
# rule boilerplate a dev brief carries further down ("接派活会话必须挂 everos-mcp") does not count.
SETUP_TASK_RES = (
    re.compile(r"(挂上|挂载|挂好|挂|配置|配好|接入|接上|安装|装上).{0,40}(everos-mcp|EverOS|MCP\b|claude 配置|Claude 配置)", re.I),
    re.compile(r"(everos-mcp|EverOS|MCP\b).{0,16}(接入|接线|接上|冒烟|挂载|挂上|配置|样板|采集|setup|set up|wiring)", re.I),
    re.compile(r"(修改|改|新建|创建|配置|手动跑).{0,24}(采集|夜审|ingest).{0,16}(automation|自动化)", re.I),
)
# Product work on the site stays in, even if it touches EverOS (e.g. a PER ticket that
# wires EverOS into the studio): a Linear ticket or PR work in the headline wins.
# Recall/smoke acceptance runs ("召回验收", "recall check"); checked after DEV_GUARD_RE.
SMOKE_TASK_RE = re.compile(r"(召回|recall).{0,12}(验收|冒烟|smoke|acceptance|check)", re.I)
DEV_GUARD_RE = re.compile(r"(\bPER-\d+|\bPR\s*#?\d+|开\s*PR|gh pr|feat/[\w./-]+|Linear)", re.I)
BRIEF_PATH_RE = re.compile(r"(/[\w.\-/]+\.md)")


def task_headline(text: str, lines: int = 2) -> str:
    out = [l.strip() for l in text.splitlines() if l.strip()][:lines]
    return " ".join(out)[:400]


def brief_text(first: str) -> str:
    """If the first message points at a brief file (e.g. "读 /workspace/ops/tasks/x.md 照做"), return its start."""
    head = task_headline(first, 1)
    if len(head) > 160:
        return ""
    for m in BRIEF_PATH_RE.finditer(head):
        p = m.group(1)
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                return f.read(4000)
        except OSError:
            continue
    return ""


def task_type(first: str) -> tuple[str, str]:
    """Return (kind, why) for the session's task: smoke/night-review/collector/setup/dev."""
    for kind, rx in EXCLUDE_PROMPT_MARKERS:
        if rx.search(first):
            return kind, f"opening prompt looks like {kind}"
    texts = [("task", first)]
    b = brief_text(first)
    if b:
        texts.append(("brief", b))
    for src, t in texts:
        head = task_headline(t)
        if DEV_GUARD_RE.search(head):
            return "dev", f"{src} headline names a ticket/PR"
        m = SMOKE_TASK_RE.search(head)
        if m:
            return "smoke", f"{src} headline is a recall/smoke acceptance: {m.group(0)[:40]!r}"
        for rx in SETUP_TASK_RES:
            m = rx.search(head)
            if m:
                return "setup", f"{src} headline is setup/config: {m.group(0)[:40]!r}"
    return "dev", "no exclusion rule matched"


def first_user_text(jsonl: str | None) -> str:
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
                if not c or c.startswith("<"):
                    continue
                return c
    except OSError:
        pass
    return ""


def transcript_entrypoint(jsonl: str | None) -> str | None:
    """Claude Code writes `entrypoint` on each line: "cli" for interactive sessions,
    "sdk-cli" for `claude -p` / print mode, "sdk-ts"/"sdk-py" for SDK runs."""
    if not jsonl:
        return None
    try:
        with open(jsonl, "r", encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 200:
                    break
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if o.get("entrypoint"):
                    return str(o["entrypoint"])
    except OSError:
        pass
    return None


def exclusion_reason(row: dict, literals: list[str] | None = None) -> str | None:
    wp = (row.get("workspace_path") or "").rstrip("/")
    if wp and EXCLUDE_PATH_RE.search(wp):
        return "night-review auto-run worktree"
    # `claude -p` and SDK runs are non-interactive one-shots (smoke / acceptance), never dev
    # work. pi sessions are not collected here (only ~/.claude/projects is read); `pi -p
    # --no-session` leaves no transcript and pi session headers carry no mode field.
    ep = transcript_entrypoint(row.get("transcript_path"))
    if ep and ep.startswith("sdk"):
        return f"non-interactive session (entrypoint={ep}, claude -p / SDK): smoke/acceptance"
    first = first_user_text(row.get("transcript_path"))
    kind, why = task_type(first)
    if kind != "dev":
        return why
    b = brief_text(first)
    return secret_like_reason(
        [("title", row.get("workspace") or ""), ("task headline", task_headline(first)), ("brief headline", task_headline(b))],
        [first, b], row.get("transcript_path"), literals or [])


# --- redaction for transcripts pushed off this machine -----------------------------------
SECRET_ENV_FILES_GLOBS = ("~/.config/everos/*.env", "~/.config/grokbot/webhooks/*.env")
SECRET_KEY_RE = re.compile(r"(KEY|TOKEN|SECRET|PASS|COOKIE|URL)", re.I)
SECRET_PATTERNS = [re.compile(p) for p in (
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    r"(?i)\bBearer\s+[A-Za-z0-9._~+/=\-]{16,}",
    r"\bsk-[A-Za-z0-9_\-]{16,}",
    r"\bgh[pousr]_[A-Za-z0-9]{20,}",
    r"\bgithub_pat_[A-Za-z0-9_]{20,}",
    r"\bcfut_[A-Za-z0-9_\-]{20,}",
    r"\bAKIA[0-9A-Z]{16}\b",
    r"\bxox[abprs]-[A-Za-z0-9-]{10,}",
    r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}",
    r"(?i)\b([A-Z0-9_]*(?:api[_-]?key|secret|password|passwd|token))(\\?[\"']?\s*[=:]\s*\\?[\"']?)[A-Za-z0-9._~+/\-]{16,}",
)]
REDACTED = "[REDACTED]"


def load_literal_secrets() -> list[str]:
    import glob
    vals: set[str] = set()
    for g in SECRET_ENV_FILES_GLOBS:
        for fn in glob.glob(os.path.expanduser(g)):
            if fn.endswith((".bak",)) or ".bak-" in fn:
                continue
            try:
                for line in open(fn, encoding="utf-8", errors="replace"):
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    k = k.replace("export ", "").strip()
                    v = v.strip().strip('"').strip("'")
                    if SECRET_KEY_RE.search(k) and not k.upper().endswith("BASE_URL") and len(v) >= 16:
                        vals.add(v)
            except OSError:
                continue
    # longest first so a value containing another is replaced whole
    return sorted(vals, key=len, reverse=True)


def redact_text(text: str, literals: list[str]) -> tuple[str, int]:
    n = 0
    for v in literals:
        for form in {v, json.dumps(v)[1:-1]}:
            if form and form in text:
                n += text.count(form)
                text = text.replace(form, REDACTED)
    for rx in SECRET_PATTERNS:
        def sub(m: re.Match) -> str:
            nonlocal n
            n += 1
            if m.re.groups >= 2:
                return m.group(1) + m.group(2) + REDACTED
            return REDACTED
        text = rx.sub(sub, text)
    return text, n


def stage_filtered_transcript(src: str, dst: Path, literals: list[str]) -> tuple[int, int]:
    """Copy src -> dst with secrets redacted. Returns (redactions, dropped_invalid_lines)."""
    red = dropped = 0
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    with open(src, "r", encoding="utf-8", errors="replace") as fi, tmp.open("w", encoding="utf-8") as fo:
        for line in fi:
            if not line.strip():
                continue
            out, n = redact_text(line.rstrip("\n"), literals)
            red += n
            try:
                json.loads(out)
            except json.JSONDecodeError:
                dropped += 1
                continue
            fo.write(out + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(dst)
    return red, dropped


# --- whole-session exclusion: secret-like sessions never go to EverOS --------------------
# dr eggbot 2026-10-18 16:11, after Zack「密钥不落地」. Checked only for sessions the task rules
# would keep, so every existing exclusion keeps its old reason. Key words count only in the
# title, the task headline and the brief headline: nearly every dev transcript mentions
# API_KEY / SECRET / TOKEN somewhere in tool output (10-17: 2 of 3 box ads sessions, all 4 iMac
# vllm sessions). Env values and token formats count anywhere in the transcript.
# v2 (Zack 10-18 16:30, FDV-67): plain TOKEN(S) is gone ("max tokens" in vllm headlines); only
# api/access token and 令牌 count. "AI key" / "API key" / 密钥 are new (FDV-72「开AI key」).
SECRET_WORD_RE = re.compile(
    r"(?<![A-Za-z0-9])(AI[\s_-]?KEYS?|API[\s_-]?KEYS?|KEYS|SECRETS?|REVOKE[DS]?|(?:API|ACCESS)[\s_-]?TOKENS?"
    r"|PRIVATE[_-]KEYS?|PASSWORDS?|CREDENTIALS?)(?![A-Za-z0-9])|令牌|密钥", re.I)
# Token formats with a fixed prefix (SECRET_PATTERNS minus the generic NAME=value one, which
# matches placeholders such as GOOGLE_CLIENT_SECRET=<name>); Bearer needs a digit for the same reason.
SECRET_FORMAT_RES = (
    ("private key", SECRET_PATTERNS[0]), ("sk-", SECRET_PATTERNS[2]), ("gh?_", SECRET_PATTERNS[3]),
    ("github_pat_", SECRET_PATTERNS[4]), ("cfut_", SECRET_PATTERNS[5]), ("AKIA", SECRET_PATTERNS[6]),
    ("xox?-", SECRET_PATTERNS[7]), ("JWT", SECRET_PATTERNS[8]),
    ("Bearer", re.compile(r"(?i)\bBearer\s+(?=[A-Za-z0-9._~+/=\-]*\d)[A-Za-z0-9._~+/=\-]{20,}")),
)


def secret_hit(text: str, literal_forms: list[str]) -> str | None:
    """What secret-like thing text contains (never the value itself), or None."""
    if any(v in text for v in literal_forms):
        return "an env secret value"
    for name, rx in SECRET_FORMAT_RES:
        if rx.search(text):
            return f"a {name} token"
    return None


def secret_like_reason(heads: list[tuple[str, str]], texts: list[str], transcript: str | None,
                       literals: list[str]) -> str | None:
    """Reason starting with "secret-like" when the whole session must stay out of EverOS.
    heads: (where, text) checked for key words; texts and every transcript line: env values / token formats."""
    for src, t in heads:
        m = SECRET_WORD_RE.search(t or "")
        if m:
            return f"secret-like: {src} names {m.group(0).upper()!r}"
    forms = sorted({f for v in literals for f in (v, json.dumps(v)[1:-1]) if f})
    for t in texts:
        hit = secret_hit(t or "", forms)
        if hit:
            return f"secret-like: task or brief contains {hit}"
    if transcript:
        try:
            with open(transcript, "r", encoding="utf-8", errors="replace") as f:
                for n, line in enumerate(f, 1):
                    hit = secret_hit(line, forms)
                    if hit:
                        return f"secret-like: transcript line {n} contains {hit}"
        except OSError:
            pass
    return None


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
    kept: list[dict] = []
    excluded: list[dict] = []
    literals = load_literal_secrets()
    for r in rows:
        why = exclusion_reason(r, literals)
        if why:
            excluded.append({"session_id": r["session_id"], "machine": machine, "workspace": r.get("workspace"),
                             "transcript_path": r.get("transcript_path"), "reason": why})
        else:
            kept.append(r)
    # Remove workspace_path to stay close to schema (night review may not care)
    for r in kept:
        r.pop("workspace_path", None)
    return kept, excluded


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=os.environ.get("D") or datetime.now(SGT).strftime("%Y-%m-%d"))
    ap.add_argument("--out", default="")
    ap.add_argument("--machine", default=os.environ.get("MACHINE") or ("imac" if sys.platform == "darwin" else "box"))
    ap.add_argument("--stage-dir", default="", help="copy redacted transcripts here (for pushing to box)")
    ap.add_argument("--remote-dir", default="", help="path the staged transcripts will have on box")
    args = ap.parse_args()
    machine = args.machine
    if machine not in ("box", "imac"):
        print(f"bad machine: {machine}", file=sys.stderr)
        return 2
    rows, excluded = collect(machine, args.date)
    out = args.out
    if not out:
        out = f"/var/lib/everos-ingest/xinyue/{args.date}/sessions-{machine}.jsonl"
    out_p = Path(out)
    out_p.parent.mkdir(parents=True, exist_ok=True)
    if args.stage_dir:
        if not args.remote_dir:
            print("--stage-dir needs --remote-dir", file=sys.stderr)
            return 2
        literals = load_literal_secrets()
        if not literals:
            # F6: never ship transcripts when the secret list could not be loaded
            print("no literal secrets loaded from env files; refusing to stage transcripts", file=sys.stderr)
            return 3
        stage = Path(args.stage_dir)
        if stage.exists():
            import shutil
            shutil.rmtree(stage)
        stage.mkdir(parents=True)
        os.chmod(stage, 0o700)
        total_red = 0
        for r in rows:
            src = r.get("transcript_path")
            if not src or not os.access(src, os.R_OK):
                r["transcript_source_path"] = src
                r["transcript_path"] = None
                continue
            name = f"{r['session_id']}.jsonl"
            red, dropped = stage_filtered_transcript(src, stage / name, literals)
            total_red += red
            r["transcript_source_path"] = src
            r["transcript_path"] = f"{args.remote_dir.rstrip('/')}/{name}"
            r["transcript_redactions"] = red
            r["transcript_dropped_lines"] = dropped
        print(f"staged {sum(1 for r in rows if r.get('transcript_path'))} transcripts -> {stage} "
              f"(literal secrets loaded={len(literals)}, redactions={total_red})")
    ex_p = out_p.with_name(out_p.stem + ".excluded.jsonl")
    with ex_p.open("w", encoding="utf-8") as f:
        for e in excluded:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(f"excluded {len(excluded)} sessions -> {ex_p}")
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
        # exit 4, not 1: the precheck wrappers use exit 1 to mean "done, do not start the model"
        import traceback
        traceback.print_exc()
        print(f"collect failed: {e}", file=sys.stderr)
        raise SystemExit(4)
