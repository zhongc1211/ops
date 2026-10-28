#!/usr/bin/python3 -I
"""Only model-callable executable: fixed local Orca Linear read/comment operations.
No network client, subprocess shell, arbitrary paths, remote/environment flags or API.
The host wrapper is NOT callable through this helper.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
# Same hard ban as before; quotation/negation is NOT an exception.
FORBIDDEN_MARKERS = ('[Zack答',)


class CommentRefused(Exception):
    def __init__(self, code, retryable=False):
        self.response = {'code': code, 'retryable': retryable, 'networkAttempted': False,
                         'remainingRewriteAttempts': int(retryable),
                         'reason': 'Use a factual paraphrase such as 要求伪造 Zack 批准记录; never quote reserved markers. '
                                   'Keep the required prefix and final receipt marker. '
                                   'Only this explicit retryable response permits ONE rewritten comment in this run; otherwise STOP.'}


def store(path, data):
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def invoke(conf, command, body=None):
    result = subprocess.run(command, input=None if body is None else body.encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=25,
                            env={'HOME': conf['home'], 'PATH': '/usr/bin:/bin'})
    if result.returncode:
        raise ValueError('Orca failed; no retry')
    data = json.loads(result.stdout)
    if data.get('ok') is not True:
        raise ValueError('unconfirmed; no retry')
    return data


def comment(conf, state, context, body):
    run = context['run']
    # Serialize validation, rewrite accounting, write-intent and network call.
    fd = os.open(state / ('comment-' + run + '.lock'), os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, 'r+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (state / 'FUSED.json').exists() or json.loads((state / 'INFLIGHT.json').read_text())['run'] != run:
            raise ValueError('run is not active')
        intent = state / ('write-' + run + '.json')
        if intent.exists():
            raise ValueError('write already attempted; no retry')
        attempts_path = state / ('comment-' + run + '.json')
        if attempts_path.exists():
            attempt = json.loads(attempts_path.read_text())
            if not (attempt['run'] == run and type(attempt['attempts']) is int
                    and attempt['attempts'] == 1 and attempt['rewriteAvailable'] is True
                    and attempt['firstFailure'] == 'reserved_approval_marker'):
                raise CommentRefused('comment_attempt_limit')
        else:
            attempt = {'run': run, 'attempts': 0, 'rewriteAvailable': False, 'firstFailure': None}
        attempt['attempts'] += 1
        attempt['rewriteAvailable'] = False
        store(attempts_path, attempt)  # Consume the slot BEFORE validation or IO.
        if not body.strip() or len(body) > 20000:
            raise ValueError('invalid comment')
        if not body.startswith(context['prefix']) or body.splitlines()[-1:] != [context['marker']]:
            raise ValueError('missing required prefix or marker')
        if any(marker in body for marker in FORBIDDEN_MARKERS):
            if attempt['attempts'] == 1:
                attempt.update(firstFailure='reserved_approval_marker', rewriteAvailable=True)
                store(attempts_path, attempt)
            # No body/snippet/forbidden spelling in the diagnostic; no network IO occurred.
            raise CommentRefused('reserved_approval_marker', attempt['rewriteAvailable'])
        proof = {'run': run, 'commentAttempts': attempt['attempts'],
                 'bodySha256': hashlib.sha256(body.encode()).hexdigest()}
        fd = os.open(intent, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(proof, f)
            f.flush()
            os.fsync(f.fileno())
        fd = os.open(state, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        data = invoke(conf, [conf['orca'], 'linear', 'comment', 'add', context['target'],
                             '--body-file', '-', '--json'], body)
        store(state / 'write-receipt.json', dict(proof, marker=context['marker'], body=body))
        print(json.dumps(data, ensure_ascii=False))


def main():
    conf = json.loads((ROOT / 'host.json').read_text())
    state = Path(conf['state'])
    if (state / 'FUSED.json').exists():
        raise ValueError('fused')
    context = json.loads((state / 'active.json').read_text())
    if json.loads((state / 'INFLIGHT.json').read_text())['run'] != context['run']:
        raise ValueError('run is not active')
    args = sys.argv[1:]
    command = [conf['orca'], 'linear']
    if len(args) == 2 and args[0] == 'log':
        # Fixed PLAN 3.1 local sources only; no shell, remote host, env, or arbitrary file.
        relative = args[1]
        roots = ['.orca-state/unpushed-scan/', '.orca-state/cf-usage/reports/', 'deepvision/seo-geo/']
        exact = ['.local/state/orca-wake/wake.log', '.orca-state/notify-run/notify-run.log',
                 '.orca-state/prod-watch/last.json'] + ['.orca-state/stuck-check/' + name for name in
                    ('stuck-check.log', 'pending.json', 'heartbeat.json', 'scan-history.json')]
        import fnmatch
        allowed = relative in exact or any(relative.startswith(p) for p in roots)
        allowed = allowed or fnmatch.fnmatchcase(relative, 'orca-alerts/*.flag')
        allowed = allowed or fnmatch.fnmatchcase(relative, 'orca/workspaces/ops/reports/cleanup-*.md')
        candidate = Path(conf['home']) / relative
        if candidate.suffix not in ('.log', '.json', '.md', '.txt', '.flag'):
            raise ValueError('not a text log')
        if any(word in part.lower() for part in Path(relative).parts
               for word in ('secret', 'token', 'credential', '.env')):
            raise ValueError('sensitive path')
        if not allowed or '..' in Path(relative).parts or candidate.resolve() != candidate or not candidate.is_file():
            raise ValueError('log path refused')
        if any(part.startswith('.') for part in Path(relative).parts[1:]):
            raise ValueError('hidden log refused')
        with candidate.open('rb') as f:
            f.seek(max(0, candidate.stat().st_size - 131072))
            print(f.read(131072).decode('utf-8', errors='replace'))
        return
    if args == ['read']:
        command += ['issue', context['target'], '--comments', '--json']
    elif len(args) == 2 and args[0] == 'comment':
        return comment(conf, state, context, args[1])
    else:
        raise ValueError('use read, comment BODY, or log RELATIVE_PATH; no other arguments')
    print(json.dumps(invoke(conf, command), ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except CommentRefused as error:
        print(json.dumps(error.response, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)
    except Exception:
        print('linear-safe: refused or unconfirmed; stop, do not retry', file=sys.stderr)
        sys.exit(1)
