#!/usr/bin/python3 -I
"""One incident only: pre-model unsupported_cli_flag E2E, OPS-1.
Default: print plan, no API/filesystem inspection or mutation (besides imports).
--apply requires operator approval and a private incident JSON; never resume/fire.
This is an operator tool, never installed as or permitted to a model tool.
"""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import host

# Exact reviewed pre-spawn implementation, not a user-selectable trust assertion.
FAILED_HOST_SHA256 = 'fff5c562dfe33752b9ca1a8773b4e574e54ed93bf7436986cbc1d38a5bccc186'
# Canonical JSON digest pins this ONE incident without committing private IDs.
INCIDENT_SHA256 = 'e13df6dab9364972f4e990912cfe2db08e14fed4aca331615589d686f65b7d4a'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_regular(path):
    host.require(path.resolve(strict=True) == path, 'cleanup_symlink_refused')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as f:
        s = os.fstat(f.fileno())
        host.require(stat.S_ISREG(s.st_mode) and s.st_uid == os.getuid()
                     and s.st_nlink == 1, 'cleanup_not_owned_regular_file')
        data = f.read(1024 * 1024 + 1)
    host.require(len(data) <= 1024 * 1024, 'cleanup_file_too_large')
    return data


def private_directory(path):
    host.require(path.is_absolute() and path.resolve(strict=True) == path, 'cleanup_directory_symlink')
    info = path.stat()
    host.require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
                 and stat.S_IMODE(info.st_mode) == 0o700, 'cleanup_directory_not_private')


def timestamp(value):
    result = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    host.require(result.tzinfo is not None, 'cleanup_naive_timestamp')
    return result


def incident(path):
    return validate_incident(json.loads(read_regular(path.resolve(strict=True))))


def validate_incident(value):
    host.require(sha(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()) == INCIDENT_SHA256,
                 'wrong_incident_digest')
    host.require(value['schema'] == 1 and value['issueIdentifier'] == 'OPS-1', 'wrong_incident')
    for key in ('company', 'agent', 'routine', 'trigger', 'issue', 'run'):
        host.require(re.fullmatch(r'[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}', value[key]), 'bad_incident_id')
    host.require(re.fullmatch(r'[0-9]{4}-[0-9]{2}', value['month']), 'bad_incident_month')
    host.require(value['fuse']['reason'] == 'unsupported_cli_flag'
                 and set(value['fuse']) == {'reason', 'at'}, 'wrong_incident_fuse')
    host.require(timestamp(value['fuse']['at']).astimezone(dt.timezone.utc).strftime('%Y-%m') == value['month'],
                 'wrong_incident_month')
    return value


def no_process(pid, group=False):
    host.require(type(pid) is int and pid > 1, 'missing_process_evidence')
    try:
        (os.killpg if group else os.kill)(pid, 0)
    except ProcessLookupError:
        return
    # PermissionError or even an unrelated process reusing the PID is a refusal.
    raise RuntimeError('incident_process_not_confirmed_absent')


def guard(m, issue_status, original=None):
    api = host.api
    a = api('GET', '/agents/' + m['agent'])
    host.require(a['id'] == m['agent'] and a['companyId'] == m['company']
                 and a['status'] == 'paused' and a['adapterType'] == 'claude_local'
                 and a['adapterConfig'].get('engine') == 'cli'
                 and a['adapterConfig'].get('command') == str(Path(host.CONF['state']).parent / 'host.py'),
                 'cleanup_agent_not_safe')
    host.require(a['spentMonthlyCents'] == 0, 'cleanup_spend_changed')
    rows = api('GET', '/companies/' + m['company'] + '/heartbeat-runs?agentId=' + m['agent'] + '&limit=1000')
    host.require(isinstance(rows, list) and len(rows) == 1 and rows[0]['id'] == m['run']
                 and rows[0]['status'] == 'cancelled', 'cleanup_run_set_changed')
    run = api('GET', '/heartbeat-runs/' + m['run'])
    context = run.get('contextSnapshot') or {}
    host.require(run['id'] == m['run'] and run['agentId'] == m['agent'] and run['companyId'] == m['company']
                 and (context.get('issueId') or context.get('taskId')) == m['issue'], 'cleanup_run_binding_changed')
    host.require(run['status'] == 'cancelled' and run['errorCode'] == 'agent_paused'
                 and run['scheduledRetryAt'] is None and run['retryOfRunId'] is None
                 and run['usageJson'] is None, 'cleanup_run_evidence_changed')
    no_process(run['processPid'])
    no_process(run['processGroupId'], group=True)
    issue = api('GET', '/issues/' + m['issue'])
    host.require(issue['id'] == m['issue'] and issue['identifier'] == 'OPS-1'
                 and issue['companyId'] == m['company'] and issue['assigneeAgentId'] == m['agent']
                 and issue['originKind'] == 'routine_execution' and issue['originId'] == m['routine']
                 and issue['status'] == issue_status and issue['executionRunId'] is None
                 and issue['parentId'] is None and not issue.get('conversationAgentId'), 'cleanup_issue_not_safe')
    goal = api('GET', '/issues/' + m['issue'] + '/runner-goal?agentId=' + m['agent'])
    host.require(goal['issueId'] == m['issue'] and goal['agentId'] == m['agent']
                 and goal['adapterType'] == 'claude_local' and goal['goal'] is None
                 and goal['pendingAction'] is None, 'cleanup_goal_not_empty')
    cost = api('GET', '/issues/' + m['issue'] + '/cost-summary')
    host.require(cost['issueId'] == m['issue'] and cost['costCents'] == 0 and cost['runCount'] == 1
                 and all(cost[k] == 0 for k in ('inputTokens', 'cachedInputTokens', 'outputTokens')),
                 'cleanup_cost_evidence_changed')
    routine = api('GET', '/routines/' + m['routine'])
    host.require(routine['id'] == m['routine'] and routine['companyId'] == m['company']
                 and len(routine['triggers']) == 1, 'cleanup_routine_changed')
    trigger = routine['triggers'][0]
    host.require(trigger['id'] == m['trigger'] and trigger['enabled'] is False
                 and trigger['setupPending'] is False, 'cleanup_trigger_not_disabled')
    formal = [x for x in host.CONF['routines'] if x != m['routine']]
    host.require(len(formal) == 1, 'cleanup_formal_routine_unknown')
    formal_sha = sha(json.dumps(api('GET', '/routines/' + formal[0]), sort_keys=True).encode())
    if original is not None:
        host.require(trigger == original['trigger'] and formal_sha == original['formalSha256'],
                     'cleanup_routine_snapshot_changed')
    # No env, prompt, MCP config, bearer or agent config is backed up or printed.
    return {'trigger': trigger, 'formalSha256': formal_sha,
            'issue': {k: issue[k] for k in ('id', 'identifier', 'status', 'executionRunId', 'parentId')},
            'run': {k: run[k] for k in ('id', 'status', 'errorCode', 'startedAt', 'finishedAt',
                                       'processPid', 'processGroupId')}, 'costCents': cost['costCents']}


def state_snapshot(state, claim_name, m, run):
    names = {'host.lock', 'FUSED.json', 'reservations.json', claim_name}
    host.require({p.name for p in state.iterdir()} == names, 'cleanup_unexpected_state_files')
    data = {name: read_regular(state / name) for name in names}
    host.require(data['host.lock'] == b'', 'cleanup_lock_contents_changed')
    host.require(json.loads(data['FUSED.json']) == m['fuse'], 'cleanup_fuse_changed')
    # The isolated incident had exactly this ledger. Never subtract from a changed
    # ledger, another month, or another run; this is NOT a general refund feature.
    host.require(json.loads(data['reservations.json']) == {m['month']: 200}, 'cleanup_ledger_changed')
    claim = json.loads(data[claim_name])
    host.require(set(claim) == {'run', 'started'} and claim['run'] == m['run'], 'cleanup_claim_changed')
    start = timestamp(claim['started'])
    host.require(start.astimezone(dt.timezone.utc).strftime('%Y-%m') == m['month']
                 and timestamp(run['startedAt']) <= start <= timestamp(m['fuse']['at'])
                 <= timestamp(run['finishedAt']), 'cleanup_claim_time_changed')
    return data


def fsync_directory(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def backup_bytes(path, content):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    host.require(read_regular(path) == content, 'cleanup_backup_mismatch')


def install_source_hashes():
    """Bind cleanup completion to the exact reviewed next installer/payload."""
    here = Path(__file__).resolve().parent
    names = ('host.py', 'install.py', 'install.sh', 'close-failed-e2e.py', 'generate.py',
             'linear-safe.py', 'settings.json', 'AGENTS.md')
    result = {name: sha(read_regular(here / name)) for name in names}
    for name in ('provision.py', 'config.sh', 'key-fill.sh', 'key-fill.py'):
        result['../' + name] = sha(read_regular(here.parent / name))
    return result


def verify_completed(root, backup, aid, cid, after_install=False):
    """Installer's read-only order gate; no installed-code imports or repairs."""
    private_directory(root)
    private_directory(backup)
    host.require(backup.parent == root / 'backups', 'cleanup_receipt_outside_backups')
    snapshot_bytes = read_regular(backup / 'snapshot.json')
    saved = json.loads(snapshot_bytes)
    progress = json.loads(read_regular(backup / 'progress.json'))
    m = validate_incident(saved['incident'])
    host.require(m['agent'] == aid and m['company'] == cid, 'cleanup_receipt_wrong_owner')
    host.require(saved['hostSha256'] == FAILED_HOST_SHA256
                 and saved['nextInstallSha256'] == install_source_hashes(), 'cleanup_install_source_changed')
    host.require(progress['phase'] == 'complete' and progress['snapshotSha256'] == sha(snapshot_bytes),
                 'cleanup_not_complete')
    claim = 'issue-' + sha(m['issue'].encode()) + '.json'
    host.require(set(saved['sha256']) == {'host.lock', 'FUSED.json', 'reservations.json', claim},
                 'cleanup_backup_incomplete')
    for name, expected in saved['sha256'].items():
        host.require(sha(read_regular(backup / name)) == expected, 'cleanup_backup_changed')
    host.require(json.loads(read_regular(backup / 'FUSED.json')) == m['fuse']
                 and json.loads(read_regular(backup / 'reservations.json')) == {m['month']: 200}
                 and json.loads(read_regular(backup / claim))['run'] == m['run'], 'cleanup_backup_not_incident')
    conf = json.loads(read_regular(root / 'host.json'))
    previous = host.CONF
    host.require(conf['api'] == previous['api'] and conf['agent'] == aid and conf['company'] == cid
                 and conf['state'] == str(root / 'state') and conf['drillRoutine'] == m['routine'],
                 'cleanup_receipt_host_changed')
    try:
        host.CONF = conf
        current = guard(m, 'cancelled', None if after_install else saved['before'])
        # Installation may legitimately update routine description timestamps;
        # its own full settings readback covers those. Triggers must never change.
        host.require(current['trigger'] == saved['before']['trigger'], 'cleanup_trigger_changed')
    finally:
        host.CONF = previous
    state = root / 'state'
    private_directory(state)
    host.require({p.name for p in state.iterdir()} == {'host.lock', 'reservations.json'}
                 and json.loads(read_regular(state / 'reservations.json')) == {m['month']: 0},
                 'cleanup_completed_state_changed')
    return sha(snapshot_bytes)


def apply(root, evidence):
    m = incident(evidence)
    next_install = install_source_hashes()
    private_directory(root)
    host.require(sha(read_regular(root / 'host.py')) == FAILED_HOST_SHA256, 'cleanup_not_failed_host_version')
    conf = json.loads(read_regular(root / 'host.json'))
    state = root / 'state'
    private_directory(state)
    host.require(conf['api'] == 'http://127.0.0.1:3110' and conf['agent'] == m['agent']
                 and conf['company'] == m['company'] and conf['drillRoutine'] == m['routine']
                 and conf['state'] == str(state) and len(conf['routines']) == 2
                 and state.resolve(strict=True) == state, 'cleanup_host_binding_changed')
    host.CONF = conf
    claim_name = 'issue-' + sha(m['issue'].encode()) + '.json'
    # Existing lock only, never truncate/create it before backup.
    read_regular(state / 'host.lock')
    fd = os.open(state / 'host.lock', os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = guard(m, 'blocked')
        originals = state_snapshot(state, claim_name, m, before['run'])
        parent = root / 'backups'
        private_directory(parent)
        backup = parent / ('failed-e2e-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
        backup.mkdir(mode=0o700)
        for name, content in originals.items():
            backup_bytes(backup / name, content)
        host.store(backup / 'snapshot.json', {'incident': m, 'before': before,
                   'hostSha256': FAILED_HOST_SHA256, 'nextInstallSha256': next_install,
                   'sha256': {n: sha(b) for n, b in originals.items()}})
        fsync_directory(backup)
        fsync_directory(parent)
        print('BACKUP:', backup, flush=True)
        # Recheck after backup, before the first API/state mutation.
        guard(m, 'blocked', before)
        host.require(state_snapshot(state, claim_name, m, before['run']) == originals, 'cleanup_state_changed')
        try:
            # v2026.1012.0 routes/issues.ts:12803+,12925,13843+,14877+.
            # cancelled is a supported terminal status; never claim failed work done.
            result = host.api('PATCH', '/issues/' + m['issue'], {'status': 'cancelled'})
            host.require(result['id'] == m['issue'] and result['status'] == 'cancelled', 'cleanup_close_unconfirmed')
            guard(m, 'cancelled', before)
            host.store(backup / 'progress.json', {'phase': 'issue_cancelled'})
            host.require(state_snapshot(state, claim_name, m, before['run']) == originals, 'cleanup_state_changed')
            # Release ONLY the unused 200-cent reservation; leave the UTC month at
            # zero. No Paperclip cost/budget records or other reservations are edited.
            host.store(state / 'reservations.json', {m['month']: 0})
            host.store(backup / 'progress.json', {'phase': 'reservation_released'})
            (state / claim_name).unlink()
            fsync_directory(state)
            host.store(backup / 'progress.json', {'phase': 'claim_removed'})
            guard(m, 'cancelled', before)
            host.require(read_regular(state / 'FUSED.json') == originals['FUSED.json'], 'cleanup_fuse_changed')
            (state / 'FUSED.json').unlink()  # last: closed issue + paused + disabled
            fsync_directory(state)
            after = guard(m, 'cancelled', before)
            host.require({p.name for p in state.iterdir()} == {'host.lock', 'reservations.json'}
                         and json.loads(read_regular(state / 'reservations.json')) == {m['month']: 0},
                         'cleanup_final_state_mismatch')
            host.require(install_source_hashes() == next_install, 'cleanup_install_source_changed')
            host.store(backup / 'progress.json', {'phase': 'complete', 'after': after,
                       'snapshotSha256': sha(read_regular(backup / 'snapshot.json'))})
        except BaseException:
            # Never automatically reopen OPS-1 or restore/reapply the reservation.
            # A partial transaction needs manual inspection of backup + progress.
            host.store(state / 'FUSED.json', {'reason': 'cleanup_incomplete',
                       'at': dt.datetime.now(dt.timezone.utc).isoformat()})
            raise
        print('PASS: OPS-1 cancelled; agent paused; test trigger remains disabled; formal routine unchanged')
        print('Only incident fuse/claim/reservation cleared; history, host.lock and E2E-FIRE-CLAIM retained; no rerun authorized')
        print('NEXT: reviewed install.py with --cleanup-backup', backup, '; do not change the source bundle')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apply', action='store_true')
    p.add_argument('--incident', type=Path, help='Private non-secret binding/evidence JSON; required with --apply')
    p.add_argument('--root', type=Path, default=Path.home() / '.local/share/paperclip-ops/ops-system-host')
    a = p.parse_args()
    print('PLAN: FIRST cleanup on old host; THEN reinstall from this same source bundle with --cleanup-backup receipt')
    print('PLAN: require exact pre-model failure evidence, old host hash, exclusive lock, one cancelled heartbeat, paused agent')
    print('PLAN: require test trigger already enabled=false/setupPending=false; no trigger/config/resume/fire writes')
    print('PLAN: back up FUSED, exact issue claim, reservations and host.lock with hashes and API safety snapshot')
    print('PLAN: PATCH only OPS-1 status=cancelled; read back; release exactly 200 reserved cents to month=0')
    print('PLAN: remove only incident claim, then FUSED last; read back; retain histories and E2E-FIRE-CLAIM')
    if not a.apply:
        print('DRY RUN: no incident/installed-state reads, API calls, writes or subprocesses; execution approval is checked by operator')
        return
    host.require(a.incident is not None, 'cleanup_incident_required')
    apply(a.root, a.incident)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        code = str(error) if isinstance(error, RuntimeError) and re.fullmatch(r'[a-z_]+', str(error)) else 'cleanup_check_failed'
        print('REFUSED/INCOMPLETE: ' + code + '; inspect backup/progress, do not blindly retry', file=sys.stderr)
        sys.exit(70)
