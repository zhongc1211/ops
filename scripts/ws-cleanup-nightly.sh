#!/bin/sh
# Scheduled precheck only. Manual Orca runs bypass prechecks.
# Default: sha -> dry-run -> execute. Drills MUST pass --dry-run-only.
PY=$(command -v python3)
[ -z "$WS_NIGHTLY_PYTHON" ] || PY=$WS_NIGHTLY_PYTHON
[ -n "$PY" ] || exit 1
"$PY" -I - "$0" "$@" <<'PYEOF'
import argparse
import csv
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import tempfile
import time
import uuid

SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def load_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {} if default is None else default


def write_json(path, value):
    tmp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    tmp.write_text(json.dumps(value, indent=2) + '\n')
    tmp.replace(path)


def log(run_dir, event):
    # Fixed event names only: never exception text, webhook settings or stage output.
    with (run_dir / 'worker.log').open('a') as out:
        out.write(now() + ' ' + event + '\n')


def group_exists(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def age_seconds(started, fallback):
    try:
        return time.time() - datetime.datetime.fromisoformat(started).timestamp()
    except (ValueError, TypeError):
        return time.time() - fallback


def post_alert(args, payload):
    # Same ops-system webhook protocol as heartbeat-watch.sh. No shell sourcing.
    cfg = {}
    try:
        for line in (args.webhook_dir / 'ops-system.env').read_text().splitlines():
            match = re.fullmatch(r'\s*(?:export\s+)?(URL|KEY)\s*=\s*(.*?)\s*', line)
            if match:
                cfg[match[1]] = match[2].strip('\'"')
        if not all(cfg.get(k) for k in ('URL', 'KEY')):
            return False, 'config_unavailable'
        if any('\n' in v or '\r' in v for v in cfg.values()):
            return False, 'config_invalid'
        esc = lambda value: value.replace('\\', '\\\\').replace('"', '\\"')
        config = ('url = "' + esc(cfg['URL']) + '"\nheader = "Content-Type: application/json"\n'
                  + 'header = "Authorization: Bearer ' + esc(cfg['KEY']) + '"\n')
        with tempfile.NamedTemporaryFile('w', encoding='utf-8') as body:
            json.dump(payload, body)
            body.flush()
            p = subprocess.run(['curl', '-q', '-sS', '-o', '/dev/null', '-w', '%{http_code}',
                                '--connect-timeout', str(args.alert_timeout), '--max-time',
                                str(args.alert_timeout), '-X', 'POST', '--data-binary',
                                '@' + body.name, '-K', '-'], input=config, capture_output=True,
                               text=True, timeout=args.alert_timeout + 2, close_fds=True)
        if p.returncode == 0 and re.fullmatch(r'2\d\d', p.stdout.strip()):
            return True, None
        return False, 'delivery_failed'  # Discard stderr: curl errors can contain credentials.
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False, 'transport_unavailable'


def notify_once(args, run_dir, kind, result):
    # Pending is durable before sending. Concurrent triggers cannot double-send it.
    # HTTP success followed by a crash before sent_at can still cause redelivery.
    with (run_dir / ('alert-' + kind + '.lock')).open('a+') as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        path = run_dir / ('alert-' + kind + '.json')
        state = load_json(path)
        if state.get('sent_at'):
            return True
        state.update(attempts=state.get('attempts', 0) + 1, last_attempt_at=now())
        write_json(path, state)
        codes = {key: result.get(key) for key in ('status', 'rc', 'sha_rc', 'dry_run_rc', 'execute_rc')}
        payload = dict(bot='ops-system', task='夜间清理异常', kind='ws_cleanup_' + kind,
                       source='ws-cleanup-nightly', run_dir=str(run_dir), **codes)
        payload['status'] = 'stuck' if kind in ('stuck', 'stale_owner', 'missing_rc') else 'failed'
        payload['note'] = json.dumps(dict(run_dir=str(run_dir), **codes), ensure_ascii=False)
        sent, error = post_alert(args, payload)
        if sent:
            state.update(sent_at=now(), last_error=None)
            log(run_dir, 'alert_sent_' + kind)
        else:
            state['last_error'] = error
            log(run_dir, 'alert_send_failed_' + kind + '_' + error)
        write_json(path, state)
        return sent


def needs_alert(result):
    if result.get('status') == 'already_running':
        return bool(result.get('stale_owner'))  # Young busy owners are expected contention.
    return (result.get('status') != 'completed' or result.get('rc') != 0
            or result.get('execute_rc') not in (None, 0) or result.get('result_errors'))


def report_result(args, run_dir, result):
    if needs_alert(result):
        kind = ('stale_owner' if result.get('status') == 'already_running' else
                'stuck' if result.get('status') == 'stuck' else 'failed')
        target = run_dir
        alert_result = result
        if kind == 'stale_owner' and result.get('owner_run_dir'):
            owner_dir = Path(result['owner_run_dir']).resolve()
            if owner_dir.parent == args.archive and owner_dir.is_dir():
                target = owner_dir
                progress = load_json(owner_dir / 'progress.json')
                alert_result = dict(result, **{key: progress.get(key) for key in
                                    ('sha_rc', 'dry_run_rc', 'execute_rc')})
        return notify_once(args, target, kind, alert_result)
    return True


def recover_previous(args, current, lock_free):
    blocked = False
    for previous in sorted(args.archive.iterdir()):
        if not previous.is_dir() or previous == current:
            continue
        record = load_json(previous / 'rc.txt')
        progress = load_json(previous / 'progress.json')
        if record:
            report_result(args, previous, record)
        elif lock_free and (progress.get('lock_acquired') or
                            age_seconds(load_json(previous / 'run.json').get('started_at'),
                                        previous.stat().st_mtime) > 10):
            notify_once(args, previous, 'missing_rc', dict(status='missing_rc', rc=None,
                        sha_rc=progress.get('sha_rc'), dry_run_rc=progress.get('dry_run_rc'),
                        execute_rc=progress.get('execute_rc')))
        # Worker-only locking avoids descriptor leaks. A known stage group left by a
        # crashed worker blocks overlap; never kill an old PID just because it is recorded.
        if lock_free and (not record or record.get('status') == 'stuck'):
            pgid = progress.get('stage_pgid')
            if pgid and group_exists(pgid):
                blocked = True
    return blocked


def result_errors(run_dir):
    # Never include generated output text in an alert, only the fact of an error.
    for path in [run_dir / 'execute.log', *sorted((run_dir / 'exec').glob('*'))]:
        if not path.is_file():
            continue
        text = path.read_text(errors='replace')
        if re.search(r'BACKUP_FAIL|ERROR|rm[^\n]*失败', text):
            return True
        if path.name == 'journal.tsv':
            for row in csv.reader(text.splitlines(), delimiter='\t'):
                if len(row) >= 4 and row[1] == 'rm-end' and row[3] not in ('', '0'):
                    return True
    return False


class StageStuck(Exception):
    pass


def worker(args, run_dir):
    result = dict(started_at=now(), pid=os.getpid(), ppid=os.getppid(), sid=os.getsid(0),
                  pgid=os.getpgrp(), dry_run_only=args.dry_run_only, sha_rc=None,
                  dry_run_rc=None, execute_rc=None, rc=1, status='failed')
    lock = None
    locked = False

    def interrupted(signum, frame):
        raise SystemExit(128 + signum)

    def stop_group(process):
        # One finite budget covers TERM, KILL, reaping and group-disappearance checks.
        deadline = time.monotonic() + args.stop_seconds
        if group_exists(process.pid):
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
        until = min(deadline, time.monotonic() + min(10, args.stop_seconds / 2))
        while group_exists(process.pid) and time.monotonic() < until:
            process.poll()
            time.sleep(min(.05, max(0, until - time.monotonic())))
        if group_exists(process.pid):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        while time.monotonic() < deadline:
            process.poll()
            if process.returncode is not None and not group_exists(process.pid):
                return True
            time.sleep(.02)
        process.poll()
        return process.returncode is not None and not group_exists(process.pid)

    def stage(name, command):
        result[name + '_started_at'] = now()
        child = None
        with (run_dir / (name + '.log')).open('wb') as output:
            try:
                # Only the worker owns the lock. No child/escaped descendant gets its fd.
                child = subprocess.Popen(command, cwd=args.workspace, stdin=subprocess.DEVNULL,
                                         stdout=output, stderr=subprocess.STDOUT, close_fds=True,
                                         start_new_session=True)
                result['stage_pgid'] = child.pid
                write_json(run_dir / 'progress.json', result)
                child.wait()
            finally:
                for sig in SIGNALS:
                    signal.signal(sig, signal.SIG_IGN)
                try:
                    if child is not None:
                        # Also clean up descendants after a successful parent exits.
                        stopped = stop_group(child)
                        result[name + '_rc'] = child.returncode
                        result[name + '_finished_at'] = now()
                        write_json(run_dir / 'progress.json', result)
                        if not stopped:
                            raise StageStuck()
                finally:
                    for sig in SIGNALS:
                        signal.signal(sig, interrupted)
        return result[name + '_rc']

    for sig in SIGNALS:
        signal.signal(sig, interrupted)
    try:
        lock = (args.archive / '.nightly.lock').open('a+')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            owner = load_json(args.archive / '.nightly.lock')
            stale = age_seconds(owner.get('started_at'), (args.archive / '.nightly.lock').stat().st_mtime) >= args.stale_seconds
            result.update(rc=75, status='already_running', stale_owner=stale,
                          owner_run_dir=owner.get('run_dir'))
            log(run_dir, 'already_running_stale' if stale else 'already_running')
            recover_previous(args, run_dir, False)
            return
        locked = True
        previous = load_json(args.archive / '.nightly.lock')
        if previous.get('status') == 'running':
            result['stale_lock_recovered'] = True
            log(run_dir, 'stale_lock_recovered')
        result['lock_acquired'] = True
        lock.seek(0)
        lock.truncate()
        json.dump(dict(pid=os.getpid(), started_at=result['started_at'], status='running',
                       run_dir=str(run_dir)), lock)
        lock.flush()
        write_json(run_dir / 'progress.json', result)
        if recover_previous(args, run_dir, True):
            raise StageStuck()
        os.chdir(args.workspace)
        result['sha_started_at'] = now()
        manifest = {}
        for line in (args.bundle / 'SHA256SUMS').read_text().splitlines():
            digest, name = line.split(None, 1)
            manifest[name.lstrip('*')] = digest
        for name in ('scripts/ws-cleanup.sh', 'scripts/ws-cleanup-nightly.sh'):
            if manifest.get(name) != hashlib.sha256((args.bundle / name).read_bytes()).hexdigest():
                raise ValueError('sha_mismatch')
        result.update(sha_rc=0, sha_finished_at=now())
        cleanup = ['/bin/bash', str(args.bundle / 'scripts/ws-cleanup.sh')]
        if args.no_issue_reviews is not None:
            cleanup += ['--no-issue-reviews', str(args.no_issue_reviews)]
        result['rc'] = stage('dry_run', cleanup + ['--dry-run', '--out', str(run_dir / 'dryrun')])
        if result['rc'] != 0:
            return
        if not args.dry_run_only:
            result['rc'] = stage('execute', cleanup + ['--execute', '--only-from',
                                      str(run_dir / 'dryrun/worktrees.tsv'), '--out', str(run_dir / 'exec')])
        result['result_errors'] = result_errors(run_dir)
        if result['result_errors'] and result['rc'] == 0:
            result['rc'] = 3
        result['status'] = 'completed' if result['rc'] == 0 else 'failed'
    except BaseException as exc:
        if result.get('sha_started_at') and result['sha_rc'] is None:
            result.update(sha_rc=1, sha_finished_at=now())
        result['rc'] = 70 if isinstance(exc, StageStuck) else (
            exc.code if isinstance(exc, SystemExit) and isinstance(exc.code, int) else 1)
        result.update(status='stuck' if isinstance(exc, StageStuck) else 'failed', error=type(exc).__name__)
        log(run_dir, 'failed_' + type(exc).__name__)
    finally:
        for sig in SIGNALS:
            signal.signal(sig, signal.SIG_IGN)
        result['finished_at'] = now()
        try:
            write_json(run_dir / 'rc.txt', result)
            report_result(args, run_dir, result)
        finally:
            if locked:
                lock.seek(0)
                lock.truncate()
                json.dump(dict(pid=os.getpid(), status='finished'), lock)
                lock.flush()
            if lock is not None:
                lock.close()


def trigger(args):
    os.umask(0o077)
    args.archive.mkdir(parents=True, exist_ok=True)
    run_dir = args.archive / (datetime.datetime.now().strftime('%Y%m%d-%H%M%S-') + uuid.uuid4().hex[:12])
    run_dir.mkdir()
    write_json(run_dir / 'run.json', dict(started_at=now()))
    read_fd, write_fd = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            os.close(read_fd)
            os.setsid()
            if os.fork() != 0:
                os._exit(0)
            os.chdir('/')
            null = os.open('/dev/null', os.O_RDONLY)
            output = os.open(run_dir / 'worker.log', os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            os.dup2(null, 0)
            os.dup2(output, 1)
            os.dup2(output, 2)
            for name in os.listdir('/dev/fd'):
                fd = int(name)
                if fd > 2 and fd != write_fd:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
            os.environ.clear()
            os.environ.update(HOME=str(args.home), PATH=args.path, LANG='en_US.UTF-8')
            os.write(write_fd, b'1')
            os.close(write_fd)
            worker(args, run_dir)
        finally:
            os._exit(0)
    os.close(write_fd)
    try:
        ready, _, _ = select.select([read_fd], [], [], 10)
        launched = bool(ready and os.read(read_fd, 1) == b'1')
    finally:
        os.close(read_fd)
    os.waitpid(pid, 0)
    print('ws-cleanup-nightly:', 'detached' if launched else 'launch_unconfirmed', run_dir, flush=True)
    return 1


try:
    launcher = Path(sys.argv.pop(1)).resolve()
    parser = argparse.ArgumentParser(description='Detached nightly cleanup; trigger always exits nonzero.')
    parser.add_argument('mode', choices=['trigger'])
    parser.add_argument('--dry-run-only', action='store_true')
    parser.add_argument('--bundle', type=Path, default=launcher.parent.parent)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--no-issue-reviews', type=Path)
    parser.add_argument('--archive', type=Path, default=Path.home() / 'ops-archive/ws-cleanup/nightly')
    options = parser.parse_args()
    for key in ('bundle', 'workspace', 'archive'):
        setattr(options, key, getattr(options, key).resolve())
    if options.no_issue_reviews is not None:
        options.no_issue_reviews = options.no_issue_reviews.resolve()
    options.home = Path.home()
    options.webhook_dir = Path(os.environ.get('WS_NIGHTLY_WEBHOOK_DIR') or
                               options.home / '.config/grokbot/webhooks').resolve()
    options.stale_seconds = float(os.environ.get('WS_NIGHTLY_STALE_SECONDS', '21600'))
    options.stop_seconds = float(os.environ.get('WS_NIGHTLY_STOP_SECONDS', '600'))
    options.alert_timeout = float(os.environ.get('WS_NIGHTLY_ALERT_TIMEOUT', '5'))
    if options.stale_seconds < 0 or options.stop_seconds <= 0 or options.alert_timeout <= 0:
        raise ValueError('invalid_timeout')
    options.path = os.environ.get('PATH', '/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin')
    sys.exit(trigger(options))
except SystemExit:
    sys.exit(1)
except Exception as exc:
    print('ws-cleanup-nightly: trigger_failed', type(exc).__name__, file=sys.stderr)
    sys.exit(1)
PYEOF
exit 1
