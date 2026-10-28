#!/usr/bin/python3 -I
"""OPS-6 only: offline plan unless --apply. Cleanup OLD deployment before reinstall.
Paid failure: retain all 800 cents of reservations; never refund as a zero-cost run.
"""
import argparse
import datetime as dt
from decimal import Decimal
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

spec = importlib.util.spec_from_file_location('ops3_cleanup', HERE / 'close-precheck.py')
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
common, read, sha, claim = previous.common, previous.read, previous.sha, previous.claim
FAILED_HOST_SHA256 = '930695fd656fce4b3f50fa932a696af23dc980de8f2f770899e37a8358bed33e'
FAILED_HELPER_SHA256 = '24936970c67e96f0f74a9f73e26c5592f2348705f22f56e20b1a198d126ba27c'
INCIDENT_SHA256 = '14cc7e79b9568998d4f22ca6c23daa79d119301ead34975e00bb094ff65d0b8c'
RUN_SHA256 = '153e18fcda88e6d2dc36e3156cc9e3571a0f110cc40276815603e11f8fc86298'


def validate(m):
    host.require(sha(json.dumps(m, sort_keys=True, separators=(',', ':')).encode()) == INCIDENT_SHA256,
                 'wrong_injection_incident')
    return m


def source_hashes():
    return {**previous.source_hashes(), 'close-injection.py': sha(read(HERE / 'close-injection.py'))}


def needs_receipt(installed_sha, runs):
    return installed_sha == FAILED_HOST_SHA256 and any(sha(r['id'].encode()) == RUN_SHA256 for r in runs)


def guard(m, status, before=None, after_install=False):
    api = host.api
    a = api('GET', '/agents/' + m['agent'])
    spent = a['spentMonthlyCents']  # Baseline only, NOT evidence this paid run cost zero.
    host.require(a['id'] == m['agent'] and a['companyId'] == m['company'] and a['status'] == 'paused'
                 and a['adapterType'] == 'claude_local' and a['adapterConfig'].get('engine') == 'cli'
                 and a['adapterConfig'].get('command') == str(Path(host.CONF['state']).parent / 'host.py')
                 and a['budgetMonthlyCents'] == 20000 and type(spent) is int and 0 <= spent <= 800,
                 'ops6_agent_not_safe')
    rows = api('GET', '/companies/' + m['company'] + '/heartbeat-runs?agentId=' + m['agent'] + '&limit=1000')
    host.require(isinstance(rows, list) and len(rows) == 6, 'ops6_history_changed')
    host.require(all(r['companyId'] == m['company'] and r['agentId'] == m['agent']
                     and r.get('retryOfRunId') is None and r.get('scheduledRetryAt') is None for r in rows),
                 'ops6_history_owner_or_retry_changed')
    history = sorted(({'id': r['id'], 'status': r['status']} for r in rows), key=lambda r: r['id'])
    host.require(history == m['history'], 'ops6_history_changed')
    run = api('GET', '/heartbeat-runs/' + m['run'])
    ctx = run.get('contextSnapshot') or {}
    host.require(run['id'] == m['run'] and run['agentId'] == m['agent'] and run['companyId'] == m['company']
                 and (ctx.get('issueId') or ctx.get('taskId')) == m['issue']
                 and run['status'] == 'cancelled' and run['errorCode'] == 'agent_paused'
                 and run['usageJson'] is None and run['retryOfRunId'] is None and run['scheduledRetryAt'] is None
                 and run['startedAt'] == m['startedAt'] and run['finishedAt'] == m['finishedAt'], 'ops6_run_changed')
    common.no_process(run['processPid'])
    common.no_process(run['processGroupId'], group=True)
    issue = api('GET', '/issues/' + m['issue'])
    host.require(issue['id'] == m['issue'] and issue['identifier'] == 'OPS-6' and issue['status'] == status
                 and issue['companyId'] == m['company'] and issue['assigneeAgentId'] == m['agent']
                 and issue['originKind'] == 'routine_execution' and issue['originId'] == m['routine']
                 and issue['originRunId'] == m['routineRun'] and issue['executionRunId'] is None and issue['parentId'] is None
                 and not issue.get('conversationAgentId'), 'ops6_issue_changed')
    goal = api('GET', '/issues/' + m['issue'] + '/runner-goal?agentId=' + m['agent'])
    host.require(goal['issueId'] == m['issue'] and goal['agentId'] == m['agent']
                 and goal['adapterType'] == 'claude_local' and goal['goal'] is None
                 and goal['pendingAction'] is None, 'ops6_goal_not_empty')
    cost = api('GET', '/issues/' + m['issue'] + '/cost-summary')
    host.require(cost['issueId'] == m['issue'] and cost['runCount'] == 1
                 and all(cost[k] == 0 for k in ('costCents', 'inputTokens', 'cachedInputTokens', 'outputTokens')),
                 'ops6_paperclip_baseline_changed')  # Known missing accounting, never a refund basis.
    routine = api('GET', '/routines/' + m['routine'])
    host.require(routine['id'] == m['routine'] and routine['companyId'] == m['company']
                 and len(routine['triggers']) == 1, 'ops6_routine_changed')
    trigger = routine['triggers'][0]
    host.require(trigger['id'] == m['trigger'] and trigger['enabled'] is False
                 and trigger['setupPending'] is False, 'ops6_trigger_not_disabled')
    rr = api('GET', '/routines/' + m['routine'] + '/runs?limit=200')
    host.require(isinstance(rr, list) and sorted(r['id'] for r in rr) == m['routineRunIds'], 'ops6_routine_runs_changed')
    primary = next(r for r in rr if r['id'] == m['routineRun'])
    merged = next(r for r in rr if r['id'] == m['coalescedRun'])
    host.require(primary['linkedIssueId'] == m['issue'] and primary['status'] in ('issue_created', 'failed')
                 and merged['linkedIssueId'] == m['issue']
                 and merged['status'] == 'coalesced' and merged['coalescedIntoRunId'] == m['routineRun'],
                 'ops6_coalesced_binding_changed')
    old_rr = sorted(({k: r[k] for k in ('id', 'status', 'linkedIssueId')}
                     for r in rr if r['id'] != m['routineRun']), key=lambda r: r['id'])
    formal = [r for r in host.CONF['routines'] if r != m['routine']]
    host.require(len(formal) == 1, 'ops6_formal_unknown')
    formal_sha = sha(json.dumps(api('GET', '/routines/' + formal[0]), sort_keys=True).encode())
    if not after_install:
        host.require(formal_sha == m['formalSha256'], 'ops6_formal_changed')
    if before is not None:
        host.require(trigger == before['trigger'] and spent == before['spentMonthlyCents']
                     and old_rr == before['historicalRoutineRuns'], 'ops6_baseline_changed')
    return {'history': history, 'trigger': trigger, 'formalSha256': formal_sha,
            'spentMonthlyCents': spent, 'historicalRoutineRuns': old_rr, 'issueStatus': status}


def state_files(state, m, backup=False):
    names = {'host.lock', 'FUSED.json', 'INFLIGHT.json', 'reservations.json', 'mcp-filter.json',
             'active.json', 'write-receipt.json', 'last-invocation.json', 'last-model-result.json',
             'last-success.json', claim(m['issue'])}
    for old in m['historicalSuccesses']:
        names.update((claim(old['issue']), 'write-' + old['run'] + '.json'))
    if not backup:
        host.require({p.name for p in state.iterdir()} == names, 'ops6_unexpected_state')
    data = {n: read(state / n) for n in names}
    j = lambda n: json.loads(data[n])
    host.require(data['host.lock'] == b'' and j('FUSED.json') == m['fuse']
                 and j('INFLIGHT.json') == m['inflight'] and j('reservations.json') == {m['month']: 800}
                 and j('last-model-result.json') == m['result'] and j('last-success.json') == m['success']
                 and j('mcp-filter.json') == {'run': m['run'], 'discardedServers': 2}, 'ops6_state_changed')
    claimed = j(claim(m['issue']))
    host.require(claimed == {'run': m['run'], 'started': m['inflight']['at']}
                 and j('active.json')['run'] == m['run'] and j('last-invocation.json')['run'] == m['run']
                 and j('last-invocation.json')['started'] == claimed['started'], 'ops6_current_binding_changed')
    t = common.timestamp(claimed['started'])
    host.require(t.astimezone(dt.timezone.utc).strftime('%Y-%m') == m['month']
                 and common.timestamp(m['startedAt']) <= t <= common.timestamp(m['fuse']['at'])
                 <= common.timestamp(m['finishedAt']), 'ops6_time_changed')
    host.require(j('write-receipt.json')['run'] == m['success']['run'], 'ops6_receipt_changed')
    for old in m['historicalSuccesses']:
        host.require(j(claim(old['issue']))['run'] == old['run']
                     and j('write-' + old['run'] + '.json')['run'] == old['run'], 'ops6_old_evidence_changed')
    # Exact set excludes a current-run write-intent: the rejection was pre-network.
    return data


def imported_cost(m):
    return host.cost_record(m['run'], 'cli_reported', Decimal(str(m['result']['costUsd'])),
                           source='legacy_last_model_result', outcome='failed', reason='no_helper_receipt',
                           exitCode=m['result']['exitCode'], isError=m['result']['isError'],
                           reservationCentsRetained=200, month=m['month'], ledgerCentsUnchanged=800,
                           startedAt=m['startedAt'], finishedAt=m['finishedAt'])


def verify_retained(state, m, originals):
    retained = set(originals) - {'FUSED.json', 'INFLIGHT.json', claim(m['issue'])}
    cost_name = 'cost-' + m['run'] + '.json'
    host.require({p.name for p in state.iterdir()} == retained | {cost_name}, 'ops6_retained_set_changed')
    host.require(all(read(state / n) == originals[n] for n in retained), 'ops6_retained_bytes_changed')
    host.require(json.loads(read(state / cost_name)) == imported_cost(m), 'ops6_imported_cost_changed')


def verify_completed(root, backup, aid, cid, after_install=False):
    common.private_directory(backup)
    host.require(backup.parent == root / 'backups', 'ops6_receipt_wrong_path')
    raw = read(backup / 'snapshot.json')
    saved = json.loads(raw)
    progress = json.loads(read(backup / 'progress.json'))
    m = validate(saved['incident'])
    host.require(m['agent'] == aid and m['company'] == cid and saved['hostSha256'] == FAILED_HOST_SHA256
                 and saved['helperSha256'] == FAILED_HELPER_SHA256
                 and saved['nextInstallSha256'] == source_hashes(), 'ops6_receipt_changed')
    host.require(progress['phase'] == 'complete' and progress['snapshotSha256'] == sha(raw), 'ops6_cleanup_incomplete')
    originals = state_files(backup, m, backup=True)
    host.require(set(saved['sha256']) == set(originals)
                 and all(sha(b) == saved['sha256'][n] for n, b in originals.items()), 'ops6_backup_changed')
    host.require(saved['before']['history'] == m['history'] and saved['before']['issueStatus'] == 'blocked',
                 'ops6_backup_not_incident')
    conf = previous.bind(root, m)
    saved_conf = host.CONF
    host.require(conf['api'] == saved_conf['api'], 'ops6_origin_changed')
    try:
        host.CONF = conf
        guard(m, 'cancelled', saved['before'], after_install=after_install)
    finally:
        host.CONF = saved_conf
    verify_retained(root / 'state', m, originals)
    return sha(raw)


def apply(root, evidence):
    m = validate(json.loads(read(evidence.resolve(strict=True))))
    host.CONF = previous.bind(root, m)
    host.require(sha(read(root / 'host.py')) == FAILED_HOST_SHA256
                 and sha(read(root / 'linear-safe.py')) == FAILED_HELPER_SHA256, 'ops6_requires_old_deployment_first')
    hashes = source_hashes()
    state = root / 'state'
    read(state / 'host.lock')
    fd = os.open(state / 'host.lock', os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = guard(m, 'blocked')
        originals = state_files(state, m)
        common.private_directory(root / 'backups')
        backup = root / 'backups' / ('ops6-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
        backup.mkdir(mode=0o700)
        for name, content in originals.items():
            common.backup_bytes(backup / name, content)
        host.store(backup / 'snapshot.json', {'incident': m, 'before': before, 'hostSha256': FAILED_HOST_SHA256,
                   'helperSha256': FAILED_HELPER_SHA256, 'nextInstallSha256': hashes,
                   'sha256': {n: sha(b) for n, b in originals.items()}})
        common.fsync_directory(backup)
        common.fsync_directory(backup.parent)
        print('BACKUP:', backup, flush=True)
        guard(m, 'blocked', before)
        host.require(state_files(state, m) == originals, 'ops6_state_changed')
        try:
            updated = host.api('PATCH', '/issues/' + m['issue'], {'status': 'cancelled'})
            host.require(updated['id'] == m['issue'] and updated['status'] == 'cancelled', 'ops6_close_unconfirmed')
            guard(m, 'cancelled', before)
            host.store(backup / 'progress.json', {'phase': 'issue_cancelled'})
            host.require(state_files(state, m) == originals, 'ops6_state_changed')
            cost = imported_cost(m)
            host.store(state / ('cost-' + m['run'] + '.json'), cost)
            print('ops-host: cost_snapshot ' + json.dumps(cost), flush=True)
            host.store(backup / 'progress.json', {'phase': 'paid_cost_imported_reservation_retained'})
            (state / claim(m['issue'])).unlink()
            host.require(read(state / 'INFLIGHT.json') == originals['INFLIGHT.json'], 'ops6_lease_changed')
            (state / 'INFLIGHT.json').unlink()
            common.fsync_directory(state)
            host.store(backup / 'progress.json', {'phase': 'claim_and_lease_removed'})
            guard(m, 'cancelled', before)
            host.require(read(state / 'FUSED.json') == originals['FUSED.json'], 'ops6_fuse_changed')
            (state / 'FUSED.json').unlink()
            common.fsync_directory(state)
            after = guard(m, 'cancelled', before)
            verify_retained(state, m, originals)
            host.require(source_hashes() == hashes, 'ops6_source_changed')
            host.store(backup / 'progress.json', {'phase': 'complete', 'after': after,
                       'snapshotSha256': sha(read(backup / 'snapshot.json'))})
        except BaseException:
            host.store(state / 'FUSED.json', {'reason': 'ops6_cleanup_incomplete',
                       'at': dt.datetime.now(dt.timezone.utc).isoformat()})
            raise
        print('PASS: OPS-6 cancelled; lease/claim/fuse removed; actual CLI $0.064206 imported; reservation 800 unchanged')
        print('NEXT: same source installer --injection-cleanup-backup', backup, '; no automatic resume/fire')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apply', action='store_true')
    p.add_argument('--incident', type=Path)
    p.add_argument('--root', type=Path, default=Path.home() / '.local/share/paperclip-ops/ops-system-host')
    a = p.parse_args()
    print('PLAN: OPS-6 only; old deployment FIRST; paused/disabled; exact six terminal heartbeats, seven routine audit rows')
    print('PLAN: lock/back up 17 state files; cancel OPS-6; import actual CLI $0.064206; retain reservation 800 (including this 200)')
    print('PLAN: remove only this claim/INFLIGHT/FUSED; preserve history, receipts, invocation/result, locks and formal configuration')
    print('PLAN: completion receipt binds same source installer --injection-cleanup-backup; no resume/fire')
    if not a.apply:
        print('DRY RUN: no installed state, incident, API or process access; no writes')
        return
    host.require(a.incident is not None, 'ops6_incident_required')
    apply(a.root, a.incident)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        reason = str(error) if isinstance(error, RuntimeError) and re.fullmatch(r'[a-z_]+', str(error)) else 'ops6_cleanup_failed'
        print('REFUSED/INCOMPLETE: ' + reason + '; inspect backup, never blindly retry', file=sys.stderr)
        sys.exit(70)
