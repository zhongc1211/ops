#!/bin/sh
# trigger always returns nonzero: Orca must never start an agent for this task.
# Default runs sha -> dry-run -> execute; drills MUST pass --dry-run-only.
PY=$(command -v python3) || exit 1
exec "$PY" -I - "$0" "$@" <<'PYEOF'
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
import uuid

SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_json(path, value):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value, indent=2) + '\n')
    tmp.replace(path)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def worker(args, run_dir):
    result = dict(started_at=now(), pid=os.getpid(), ppid=os.getppid(),
                  sid=os.getsid(0), pgid=os.getpgrp(), dry_run_only=args.dry_run_only,
                  sha_rc=None, dry_run_rc=None, execute_rc=None, rc=1, status='failed')
    lock = None
    locked = False
    child = None

    def interrupted(signum, frame):
        raise SystemExit(128 + signum)

    def stop_group(process):
        def send(sig):
            try:
                os.killpg(process.pid, sig)
                return True
            except ProcessLookupError:
                return False

        send(signal.SIGTERM)
        deadline = time.monotonic() + 10
        while send(0) and time.monotonic() < deadline:
            process.poll()  # Reap the direct child as soon as it exits.
            time.sleep(0.05)
        if send(0):
            send(signal.SIGKILL)
        process.wait()
        # Keep the lock until the entire owned group is gone, including descendants.
        while send(0):
            time.sleep(0.05)

    def stage(name, command, cwd):
        nonlocal child
        result[name + '_started_at'] = now()
        with (run_dir / (name + '.log')).open('wb') as log:
            try:
                child = subprocess.Popen(command, cwd=cwd, stdin=subprocess.DEVNULL,
                                         # Keep our lock alive if the supervisor is SIGKILLed mid-stage.
                                         stdout=log, stderr=subprocess.STDOUT, close_fds=True,
                                         pass_fds=(lock.fileno(),), start_new_session=True)
                child.wait()
            finally:
                for sig in SIGNALS:
                    signal.signal(sig, signal.SIG_IGN)
                try:
                    if child is not None:
                        if sys.exc_info()[0] is not None or child.poll() != 0:
                            stop_group(child)
                        result[name + '_rc'] = child.returncode
                    child = None
                    result[name + '_finished_at'] = now()
                finally:
                    for sig in SIGNALS:
                        signal.signal(sig, interrupted)
        return result[name + '_rc']

    for sig in SIGNALS:
        signal.signal(sig, interrupted)
    try:
        os.chdir(args.workspace)
        lock = (args.archive / '.nightly.lock').open('a+')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(now(), 'already_running', flush=True)
            result.update(rc=0, status='already_running')
            return
        locked = True
        lock.seek(0)
        try:
            previous = json.load(lock)
        except (ValueError, OSError):
            previous = {}
        if previous.get('status') == 'running':
            # The kernel lock is free. Never unlink its inode or kill a recorded PID.
            stale = not alive(int(previous['pid']))
            print(now(), 'stale_lock_recovered' if stale else 'released_lock_recovered', flush=True)
            result['stale_lock_recovered'] = stale
        owner = dict(pid=os.getpid(), started_at=result['started_at'], status='running')
        lock.seek(0)
        lock.truncate()
        json.dump(owner, lock)
        lock.flush()
        print(now(), 'lock_acquired', flush=True)
        result['sha_started_at'] = now()
        # Require both entry points; an incomplete manifest must never authorize cleanup.
        manifest = {}
        for line in (args.bundle / 'SHA256SUMS').read_text().splitlines():
            digest, name = line.split(None, 1)
            manifest[name.lstrip('*')] = digest
        for name in ('scripts/ws-cleanup.sh', 'scripts/ws-cleanup-nightly.sh'):
            digest = hashlib.sha256((args.bundle / name).read_bytes()).hexdigest()
            if manifest.get(name) != digest:
                raise ValueError('sha_mismatch')
        result.update(sha_rc=0, sha_finished_at=now())
        print(now(), 'sha_ok', flush=True)
        cleanup = str(args.bundle / 'scripts/ws-cleanup.sh')
        result['rc'] = stage('dry_run', ['/bin/bash', cleanup, '--dry-run', '--out',
                                        str(run_dir / 'dryrun')], args.workspace)
        if result['rc'] != 0:
            return
        if not args.dry_run_only:
            result['rc'] = stage('execute', ['/bin/bash', cleanup, '--execute', '--only-from',
                                            str(run_dir / 'dryrun/worktrees.tsv'), '--out',
                                            str(run_dir / 'exec')], args.workspace)
        result['status'] = 'completed' if result['rc'] == 0 else 'failed'
    except BaseException as exc:
        if result['sha_rc'] is None:
            result.update(sha_rc=1, sha_finished_at=now())
        result['rc'] = exc.code if isinstance(exc, SystemExit) and isinstance(exc.code, int) else 1
        # Log only the exception class; command errors can contain URLs or credentials.
        result.update(status='failed', error=type(exc).__name__)
        print(now(), 'failed', type(exc).__name__, flush=True)
    finally:
        # Ignore further catchable termination while publishing the final record.
        for sig in SIGNALS:
            signal.signal(sig, signal.SIG_IGN)
        result['finished_at'] = now()
        try:
            write_json(run_dir / 'rc.txt', result)
        finally:
            if locked:
                lock.seek(0)
                lock.truncate()
                json.dump(dict(pid=os.getpid(), status='finished'), lock)
                lock.flush()
            if lock is not None:
                lock.close()  # Kernel releases the lock even after a crash/SIGKILL.


def trigger(args):
    os.umask(0o077)
    args.archive.mkdir(parents=True, exist_ok=True)
    run_dir = args.archive / (datetime.datetime.now().strftime('%Y%m%d-%H%M%S-') + uuid.uuid4().hex[:12])
    run_dir.mkdir()
    read_fd, write_fd = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            os.close(read_fd)
            os.setsid()  # Leave Orca's session and process group before orphaning.
            if os.fork() != 0:
                os._exit(0)
            os.chdir('/')
            null = os.open('/dev/null', os.O_RDONLY)
            log = os.open(run_dir / 'worker.log', os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            os.dup2(null, 0)
            os.dup2(log, 1)
            os.dup2(log, 2)
            # Close *all* inherited descriptors, including Orca pipes above fd 2.
            for name in os.listdir('/dev/fd'):
                fd = int(name)
                if fd > 2 and fd != write_fd:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
            os.environ.clear()
            os.environ.update(HOME=str(Path.home()), PATH=args.path, LANG='en_US.UTF-8')
            os.write(write_fd, b'1')
            os.close(write_fd)  # No pipe to the precheck survives into the actual work.
            worker(args, run_dir)
        finally:
            os._exit(0)
    os.close(write_fd)
    try:
        ready, _, _ = select.select([read_fd], [], [], 3)
        launched = bool(ready and os.read(read_fd, 1) == b'1')
    finally:
        os.close(read_fd)
    # Intermediate child exits immediately; no wait on the actual worker or its pipes.
    os.waitpid(pid, 0)
    print('ws-cleanup-nightly:', 'detached' if launched else 'launch_failed', run_dir, flush=True)
    return 1


try:
    launcher = Path(sys.argv.pop(1)).resolve()
    parser = argparse.ArgumentParser(description='Detached nightly cleanup; trigger always exits nonzero.')
    parser.add_argument('mode', choices=['trigger'])
    parser.add_argument('--dry-run-only', action='store_true')
    parser.add_argument('--bundle', type=Path, default=launcher.parent.parent)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--archive', type=Path, default=Path.home() / 'ops-archive/ws-cleanup/nightly')
    options = parser.parse_args()
    for key in ('bundle', 'workspace', 'archive'):
        setattr(options, key, getattr(options, key).resolve())
    options.path = os.environ.get('PATH', '/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin')
    sys.exit(trigger(options))
except SystemExit:
    sys.exit(1)  # Including --help: no invocation may authorize an Orca model run.
except Exception as exc:
    print('ws-cleanup-nightly: trigger_failed', type(exc).__name__, file=sys.stderr)
    sys.exit(1)
PYEOF
