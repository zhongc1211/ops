#!/usr/bin/env python3
"""fake-ssh.py: an ssh that connects nowhere, for the checks that need the default store host (box) (B2a, PER-146: N8, G1a, G1b).

Installed as `ssh` first in PATH. One JSON line per call to $FAKE_SSH_LOG: {"host", "kind", "path", "rc", "cmd"}, the path
exactly as the caller sent it (N8 reads it). Hosts listed in $FAKE_SSH_DOWN (space separated) answer 255, like an
unreachable host. Every other host is a folder $FAKE_SSH_ROOT/<host>/ that plays the three remote commands the gate sends:
  grep -Eq '<re>' <dir>/<file>                   -> /usr/bin/grep -Eq '<re>' store/<file>
  cat <dir>/<project>/<D>.status                 -> prints state/<project>/<D>.status (rc 1 when it is not there)
  mkdir -p <dir> && tar -xzf - -C <dir>          -> unpacks stdin into store/
Files are found by name, not by directory (FAILURE-MODES.md H3). Anything else exits 99 and is logged as unhandled.
"""
import json, os, re, shlex, subprocess, sys

VALUED = set("BbcDEeFIiJLlmOopQRSWw")
a, i = sys.argv[1:], 0
while i < len(a) and a[i].startswith("-"):
    i += 2 if len(a[i]) == 2 and a[i][1] in VALUED else 1
host = a[i].split("@")[-1] if i < len(a) else ""
cmd = " ".join(a[i + 1:])
root = os.path.join(os.environ["FAKE_SSH_ROOT"], host)


def done(kind, path, rc):
    with open(os.environ["FAKE_SSH_LOG"], "a", encoding="utf-8") as f:
        f.write(json.dumps({"host": host, "kind": kind, "path": path, "rc": rc, "cmd": cmd}, ensure_ascii=False) + "\n")
    sys.exit(rc)


if host in os.environ.get("FAKE_SSH_DOWN", "").split():
    done("down", "", 255)
try:
    w = shlex.split(cmd)
except ValueError:
    w = []
if len(w) == 4 and w[:2] == ["grep", "-Eq"]:
    f = os.path.join(root, "store", os.path.basename(w[3]))
    done("grep", w[3], subprocess.run(["/usr/bin/grep", "-Eq", w[2], f], stderr=subprocess.DEVNULL).returncode)
if len(w) == 2 and w[0] == "cat" and w[1].endswith(".status"):
    f = os.path.join(root, "state", *w[1].split("/")[-2:])
    if not os.path.isfile(f):
        done("cat", w[1], 1)
    sys.stdout.write(open(f, encoding="utf-8").read()); sys.stdout.flush()
    done("cat", w[1], 0)
m = re.fullmatch(r"mkdir -p (\S+) && tar -xzf - -C (\S+)", cmd)
if m and m.group(1) == m.group(2):
    store = os.path.join(root, "store")
    os.makedirs(store, exist_ok=True)
    done("tar", m.group(1), subprocess.run(["/usr/bin/tar", "-xzf", "-", "-C", store], stdin=sys.stdin).returncode)
done("unhandled", "", 99)
