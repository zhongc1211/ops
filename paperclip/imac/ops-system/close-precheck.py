#!/usr/bin/python3 -I
"""OPS-3 only. Offline plan by default. Cleanup FIRST, reinstall SECOND.
Never a model tool. No resume/fire/secret reads; --apply needs operator approval.
"""
import argparse
import datetime as dt
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import host

spec = importlib.util.spec_from_file_location('cleanup_common', HERE / 'close-failed-e2e.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
sha = common.sha
read = common.read_regular
FAILED_HOST_SHA256 = '5d8fdd9ae5901949830543c2c846ba86654c92b8c4e8f0791f7a31daff19312c'
INCIDENT_SHA256 = '22befa1992b21fe764a95f5c547f6021085d29bde39bf74c3be90518a0e87080'
RUN_SHA256 = '2a9ae0613588360a760555b998de2cd7ba681a7118fd5495bdc23f2a70e9628b'


def validate(value):
    host.require(sha(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()) == INCIDENT_SHA256,
                 'wrong_precheck_incident')
    return value


def source_hashes():
    return {**common.install_source_hashes(), 'close-precheck.py': sha(read(HERE / 'close-precheck.py'))}


def needs_receipt(installed_sha, runs):
    return installed_sha == FAILED_HOST_SHA256 and any(sha(r['id'].encode()) == RUN_SHA256 for r in runs)


def claim(issue):
    return 'issue-' + sha(issue.encode()) + '.json'


def bind(root, m):
    common.private_directory(root)
    common.private_directory(root / 'state')
    conf = json.loads(read(root / 'host.json'))
    host.require(conf['api'] == 'http://127.0.0.1:3110' and conf['company'] == m['company']
                 and conf['agent'] == m['agent'] and conf['drillRoutine'] == m['routine']
                 and conf['state'] == str(root / 'state'), 'precheck_binding_changed')
    return conf


def guard(m, status, before=None, after_install=False):
    api = host.api
    a = api('GET', '/agents/' + m['agent'])
    spent = a['spentMonthlyCents']
    host.require(a['id'] == m['agent'] and a['companyId'] == m['company'] and a['status'] == 'paused'
                 and a['adapterType'] == 'claude_local' and a['adapterConfig'].get('engine') == 'cli'
                 and a['adapterConfig'].get('command') == str(Path(host.CONF['state']).parent / 'host.py')
                 and a['budgetMonthlyCents'] == 20000 and type(spent) is int and 0 <= spent <= 200,
                 'precheck_agent_not_safe')
    rows = api('GET', '/companies/' + m['company'] + '/heartbeat-runs?agentId=' + m['agent'] + '&limit=1000')
    host.require(isinstance(rows, list) and len(rows) == 3, 'precheck_history_changed')
    host.require(all(r['companyId'] == m['company'] and r['agentId'] == m['agent'] for r in rows),
                 'precheck_history_owner_changed')
    history = sorted(({'id': r['id'], 'status': r['status']} for r in rows), key=lambda r: r['id'])
    host.require(history == m['history'], 'precheck_history_changed')
    run = api('GET', '/heartbeat-runs/' + m['run'])
    ctx = run.get('contextSnapshot') or {}
    host.require(run['id'] == m['run'] and run['agentId'] == m['agent'] and run['companyId'] == m['company']
                 and (ctx.get('issueId') or ctx.get('taskId')) == m['issue']
                 and run['status'] == 'cancelled' and run['errorCode'] == 'agent_paused'
                 and run['usageJson'] is None and run['retryOfRunId'] is None
                 and run['scheduledRetryAt'] is None, 'precheck_run_changed')
    common.no_process(run['processPid'])
    common.no_process(run['processGroupId'], group=True)
    issue = api('GET', '/issues/' + m['issue'])
    host.require(issue['id'] == m['issue'] and issue['identifier'] == 'OPS-3' and issue['status'] == status
                 and issue['companyId'] == m['company'] and issue['assigneeAgentId'] == m['agent']
                 and issue['originKind'] == 'routine_execution' and issue['originId'] == m['routine']
                 and issue['executionRunId'] is None and issue['parentId'] is None
                 and not issue.get('conversationAgentId'), 'precheck_issue_changed')
    goal = api('GET', '/issues/' + m['issue'] + '/runner-goal?agentId=' + m['agent'])
    host.require(goal['issueId'] == m['issue'] and goal['agentId'] == m['agent']
                 and goal['adapterType'] == 'claude_local' and goal['goal'] is None
                 and goal['pendingAction'] is None, 'precheck_goal_not_empty')
    cost = api('GET', '/issues/' + m['issue'] + '/cost-summary')
    host.require(cost['issueId'] == m['issue'] and cost['runCount'] == 1
                 and all(cost[k] == 0 for k in ('costCents', 'inputTokens', 'cachedInputTokens', 'outputTokens')),
                 'precheck_cost_changed')
    routine = api('GET', '/routines/' + m['routine'])
    host.require(routine['id'] == m['routine'] and routine['companyId'] == m['company']
                 and len(routine['triggers']) == 1, 'precheck_routine_changed')
    trigger = routine['triggers'][0]
    host.require(trigger['id'] == m['trigger'] and trigger['enabled'] is False
                 and trigger['setupPending'] is False, 'precheck_trigger_not_disabled')
    rr = api('GET', '/routines/' + m['routine'] + '/runs?limit=200')
    host.require(isinstance(rr, list) and sorted(r['id'] for r in rr) == m['routineRunIds'],
                 'precheck_routine_runs_changed')
    current = next(r for r in rr if r['id'] == m['routineRun'])
    host.require(current['linkedIssueId'] == m['issue'], 'precheck_routine_run_binding_changed')
    old_rr = sorted(({k: r[k] for k in ('id', 'status', 'linkedIssueId')}
                     for r in rr if r['id'] != m['routineRun']), key=lambda r: r['id'])
    formal = [r for r in host.CONF['routines'] if r != m['routine']]
    host.require(len(formal) == 1, 'precheck_formal_unknown')
    formal_sha = sha(json.dumps(api('GET', '/routines/' + formal[0]), sort_keys=True).encode())
    if not after_install:
        host.require(formal_sha == m['formalSha256'], 'precheck_formal_changed')
    if before is not None:
        host.require(trigger == before['trigger'] and spent == before['spentMonthlyCents']
                     and old_rr == before['historicalRoutineRuns'], 'precheck_baseline_changed')
    return {'history': history, 'trigger': trigger, 'formalSha256': formal_sha,
            'spentMonthlyCents': spent, 'historicalRoutineRuns': old_rr,
            'run': {k: run[k] for k in ('id', 'startedAt', 'finishedAt')}, 'issueStatus': status}


def state_files(state, m, run, backup=False):
    names = {'host.lock', 'FUSED.json', 'reservations.json', 'mcp-filter.json', 'active.json',
             'write-receipt.json', 'last-invocation.json', 'last-model-result.json', 'last-success.json',
             'write-' + m['previousRun'] + '.json', claim(m['previousIssue']), claim(m['issue'])}
    if not backup:
        host.require({p.name for p in state.iterdir()} == names, 'precheck_unexpected_state')
    data = {n: read(state / n) for n in names}
    host.require(data['host.lock'] == b'' and json.loads(data['FUSED.json']) == m['fuse']
                 and json.loads(data['reservations.json']) == {m['month']: 400}, 'precheck_state_changed')
    claimed = json.loads(data[claim(m['issue'])])
    host.require(set(claimed) == {'run', 'started'} and claimed['run'] == m['run'], 'precheck_claim_changed')
    t = common.timestamp(claimed['started'])
    host.require(t.astimezone(dt.timezone.utc).strftime('%Y-%m') == m['month']
                 and common.timestamp(run['startedAt']) <= t <= common.timestamp(m['fuse']['at'])
                 <= common.timestamp(run['finishedAt']), 'precheck_claim_time_changed')
    host.require(json.loads(data['mcp-filter.json']) == {'run': m['run'], 'discardedServers': 2},
                 'precheck_mcp_audit_changed')
    for n in names - {'host.lock', 'FUSED.json', 'reservations.json', 'mcp-filter.json', claim(m['issue'])}:
        host.require(json.loads(data[n])['run'] == m['previousRun'], 'precheck_old_evidence_binding_changed')
    success = json.loads(data['last-success.json'])
    result = json.loads(data['last-model-result.json'])
    host.require(success['issue'] == m['previousIssue'] and success['costUsd'] == m['previousCostUsd']
                 and result['costUsd'] == m['previousCostUsd'] and result['exitCode'] == 0
                 and result['isError'] is False, 'precheck_old_success_changed')
    return data


def verify_completed(root, backup, aid, cid, after_install=False):
    common.private_directory(backup)
    host.require(backup.parent == root / 'backups', 'precheck_receipt_wrong_path')
    raw = read(backup / 'snapshot.json')
    saved = json.loads(raw)
    progress = json.loads(read(backup / 'progress.json'))
    m = validate(saved['incident'])
    host.require(m['agent'] == aid and m['company'] == cid and saved['hostSha256'] == FAILED_HOST_SHA256
                 and saved['nextInstallSha256'] == source_hashes(), 'precheck_receipt_changed')
    host.require(progress['phase'] == 'complete' and progress['snapshotSha256'] == sha(raw),
                 'precheck_cleanup_incomplete')
    # Verify all original bytes and all retained bytes, not just absence of fuse.
    originals = state_files(backup, m, saved['before']['run'], backup=True)
    host.require(set(saved['sha256']) == set(originals)
                 and all(sha(b) == saved['sha256'][n] for n, b in originals.items()), 'precheck_backup_changed')
    host.require(saved['before']['history'] == m['history'] and saved['before']['issueStatus'] == 'blocked',
                 'precheck_backup_not_incident')
    conf = bind(root, m)
    previous = host.CONF
    host.require(conf['api'] == previous['api'], 'precheck_origin_changed')
    try:
        host.CONF = conf
        current = guard(m, 'cancelled', saved['before'], after_install=after_install)
        host.require(current['run'] == saved['before']['run'], 'precheck_run_times_changed')
    finally:
        host.CONF = previous
    verify_retained(root / 'state', m, originals)
    return sha(raw)


def verify_retained(state, m, originals):
    retained = set(originals) - {'FUSED.json', claim(m['issue'])}
    host.require({p.name for p in state.iterdir()} == retained, 'precheck_retained_set_changed')
    for n in retained - {'reservations.json'}:
        host.require(read(state / n) == originals[n], 'precheck_retained_bytes_changed')
    host.require(json.loads(read(state / 'reservations.json')) == {m['month']: 200}, 'precheck_reservation_changed')


def apply(root, evidence):
    m = validate(json.loads(read(evidence.resolve(strict=True))))
    host.CONF = bind(root, m)
    host.require(sha(read(root / 'host.py')) == FAILED_HOST_SHA256, 'precheck_requires_old_host_first')
    hashes = source_hashes()
    state = root / 'state'
    read(state / 'host.lock')
    fd = os.open(state / 'host.lock', os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = guard(m, 'blocked')
        originals = state_files(state, m, before['run'])
        common.private_directory(root / 'backups')
        backup = root / 'backups' / ('ops3-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
        backup.mkdir(mode=0o700)
        for name, content in originals.items():
            common.backup_bytes(backup / name, content)
        host.store(backup / 'snapshot.json', {'incident': m, 'before': before, 'hostSha256': FAILED_HOST_SHA256,
                   'nextInstallSha256': hashes, 'sha256': {n: sha(b) for n, b in originals.items()}})
        common.fsync_directory(backup)
        common.fsync_directory(backup.parent)
        print('BACKUP:', backup, flush=True)
        guard(m, 'blocked', before)
        host.require(state_files(state, m, before['run']) == originals, 'precheck_state_changed')
        try:
            # Fixed-version issues PATCH supports cancelled; do not fake success/done.
            updated = host.api('PATCH', '/issues/' + m['issue'], {'status': 'cancelled'})
            host.require(updated['id'] == m['issue'] and updated['status'] == 'cancelled', 'precheck_close_unconfirmed')
            guard(m, 'cancelled', before)
            host.store(backup / 'progress.json', {'phase': 'issue_cancelled'})
            host.require(state_files(state, m, before['run']) == originals, 'precheck_state_changed')
            host.store(state / 'reservations.json', {m['month']: 200})  # retain prior E2E reservation
            host.store(backup / 'progress.json', {'phase': 'reservation_released'})
            (state / claim(m['issue'])).unlink()
            common.fsync_directory(state)
            host.store(backup / 'progress.json', {'phase': 'claim_removed'})
            guard(m, 'cancelled', before)
            host.require(read(state / 'FUSED.json') == originals['FUSED.json'], 'precheck_fuse_changed')
            (state / 'FUSED.json').unlink()
            common.fsync_directory(state)
            after = guard(m, 'cancelled', before)
            verify_retained(state, m, originals)
            host.require(source_hashes() == hashes, 'precheck_source_changed')
            host.store(backup / 'progress.json', {'phase': 'complete', 'after': after,
                       'snapshotSha256': sha(read(backup / 'snapshot.json'))})
        except BaseException:
            host.store(state / 'FUSED.json', {'reason': 'precheck_cleanup_incomplete',
                       'at': dt.datetime.now(dt.timezone.utc).isoformat()})
            raise
        print('PASS: OPS-3 cancelled; paused/disabled; history and prior receipts retained; reservation 400 -> 200')
        print('NEXT: same source installer --precheck-cleanup-backup', backup, '; no automatic resume/fire')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apply', action='store_true')
    p.add_argument('--incident', type=Path)
    p.add_argument('--root', type=Path, default=Path.home() / '.local/share/paperclip-ops/ops-system-host')
    a = p.parse_args()
    print('PLAN: OPS-3 only; old failed host FIRST; require paused, disabled trigger, exact three terminal runs')
    print('PLAN: lock and back up all known state; cancel OPS-3; reservation 400 -> 200; remove only its claim, then fuse')
    print('PLAN: preserve prior E2E receipts/claim/reservation, all history, MCP audit and one-shot trigger locks')
    print('PLAN: complete receipt binds same source installer via --precheck-cleanup-backup; no resume/fire')
    if not a.apply:
        print('DRY RUN: no installed state, incident, API or process access; no writes')
        return
    host.require(a.incident is not None, 'precheck_incident_required')
    apply(a.root, a.incident)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        reason = str(error) if isinstance(error, RuntimeError) and re.fullmatch(r'[a-z_]+', str(error)) else 'precheck_cleanup_failed'
        print('REFUSED/INCOMPLETE: ' + reason + '; inspect backup, never blindly retry', file=sys.stderr)
        sys.exit(70)
