#!/usr/bin/env python3
"""Local log wrapper only; unpushed_scan.py owns all reminder decisions."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys
from local_state import maintain_logs


def main():
    machine = sys.argv[1]
    if machine not in ('imac', 'mba'):
        return 2
    os.umask(0o077)
    state = Path(os.environ.get('UNPUSHED_STATE_DIR', '~/.orca-state/unpushed-scan')).expanduser()
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'local-log.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('已有未推送扫描持锁，本轮跳过', file=sys.stderr)
            return 4
        prefix = 'unpushed-scan' if machine == 'imac' else 'unpushed-scan-mba'
        log = maintain_logs(state, prefix)
        # Scanner prints each log line to stdout. Capture that once, including errors.
        with log.open('a') as out:
            return subprocess.run([sys.executable, str(Path(__file__).with_name('unpushed_scan.py')),
                                   '--machine', machine, '--state', str(state / 'state.json'),
                                   *sys.argv[2:]], stdout=out, stderr=subprocess.STDOUT).returncode


if __name__ == '__main__':
    sys.exit(main())
