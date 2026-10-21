# G1a: old and new night-review-gate.sh, nothing store-related set (store host box, ~/xinyue-deploy/nightly-review)

- old: /private/tmp/claude-501/-Users-jiawenwang-orca-workspaces-ops-ops-migration-nobox-b2a-1021/ab93b969-c8ee-4fc6-8748-adf58cc346ca/scratchpad/e2e-20261022-005430/post/base/scripts/night-review-gate.sh sha256 68cc20386f421ae322fbb9c557858638ace3d0b4225ea38c8fb978a3ceadb1dc
- new: /Users/jiawenwang/orca/workspaces/ops/ops-migration-nobox-b2a-1021/scripts/night-review-gate.sh sha256 eda734d078a393fc3cbd29d38cc5805900dcbb1093721656c3e67adb01165dcc
- 44 scenarios, 48 gate calls per version, 17 s; ssh = fake-ssh.py (connects nowhere), wakes = mock_webhook.py on 127.0.0.1 (8 received, 0 with a wrong KEY)
- result: no counted difference

| scenario | exit codes old | exit codes new | differing fields |
|---|---|---|---|
| primary-store-done | 1 | 1 | - |
| primary-started-1h-ago | 1 | 1 | - |
| primary-checking-10min-ago | 1 | 1 | - |
| primary-outside-window | 1 | 1 | - |
| primary-on-battery | 1 | 1 | - |
| primary-lid-closed | 1 | 1 | - |
| primary-lid-closed-sleepdisabled | 0 | 0 | - |
| primary-lock-busy | 1 | 1 | - |
| primary-own-lock | 1 | 1 | - |
| primary-normal-then-retry | 0 1 | 0 1 | - |
| primary-store-down | 0 | 0 | - |
| watch-store-done | 1 | 1 | - |
| watch-mba-offline | 1 | 1 | - |
| watch-mba-no-state | 1 | 1 | - |
| watch-mba-lock-busy | 1 | 1 | - |
| watch-mba-running | 1 | 1 | - |
| watch-mba-stalled | 1 | 1 | - |
| watch-mba-done-not-in-store | 1 | 1 | - |
| watch-store-down-mba-done | 1 | 1 | - |
| backup-before-window | 1 | 1 | - |
| backup-after-window | 1 | 1 | - |
| backup-store-done | 1 | 1 | - |
| backup-mba-running | 1 | 1 | - |
| backup-mba-offline-takes-over | 0 1 | 0 1 | - |
| backup-already-started | 1 | 1 | - |
| backup-lock-busy-under-60min | 1 | 1 | - |
| backup-lock-busy-over-60min | 1 1 | 1 1 | - |
| backup-synced-marker | 0 | 0 | - |
| box-watch-store-done | 1 | 1 | - |
| box-watch-already-escalated | 1 | 1 | - |
| box-watch-imac-running | 1 | 1 | - |
| box-watch-nobody | 1 1 | 1 1 | - |
| box-watch-imac-down | 1 | 1 | - |
| finish-no-done-line | 3 | 3 | - |
| finish-ok | 0 | 0 | - |
| finish-store-down | 4 | 4 | - |
| reason-no-takeover | 0 | 0 | - |
| reason-takeover | 0 | 0 | - |
| keepawake | 1 | 1 | - |
| xinyue-primary-normal | 0 | 0 | - |
| xinyue-watch-mba-offline | 1 | 1 | - |
| xinyue-backup-mba-offline | 0 | 0 | - |
| xinyue-finish-ok | 0 | 0 | - |
| xinyue-box-watch-nobody | 1 | 1 | - |

## Counted differences

none

## Listed, not counted (the intended changes: ~ no longer expanded here, stuck wakes say machine=imac)

- primary-store-done: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-started-1h-ago: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-checking-10min-ago: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-outside-window: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-on-battery: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-lid-closed: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-lid-closed-sleepdisabled: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-lock-busy: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-own-lock: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- primary-normal-then-retry: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- watch-store-done: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- watch-mba-offline: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- watch-mba-no-state: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]]
- watch-mba-lock-busy: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]]
- watch-mba-running: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]]
- watch-mba-stalled: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]]
- watch-mba-done-not-in-store: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"], ["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"], ["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- backup-store-done: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- backup-mba-running: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["mba", "cat", "~/.orca-state/night-review/vllm-omni/2099-02-01.status"]]
- backup-mba-offline-takes-over: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- backup-already-started: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- backup-lock-busy-under-60min: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- backup-lock-busy-over-60min: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"], ["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- backup-lock-busy-over-60min: wake_machine_note: old [["box", "machine=box reason=lock_busy MBA missed (offline), iMac heavy-lock busy > 60 min; run the disabled box task by hand (README §回滚)"]] / new [["imac", "machine=imac reason=lock_busy MBA missed (offline), iMac heavy-lock busy > 60 min; the iMac backup takes the night once the lock is free (it retries every 10 min until MBA time +240 min): check what holds the iMac lock, or run the iMac backup task by hand"]]
- backup-lock-busy-over-60min: escalated: old ["escalated=box"] / new ["escalated=imac"]
- backup-synced-marker: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- box-watch-nobody: wake_machine_note: old [["box", "machine=box reason=imac_missed neither MBA nor iMac finished by +150 min; run the disabled box task by hand"]] / new [["imac", "machine=imac reason=imac_missed neither MBA nor iMac finished by +150 min; check the iMac backup (night-review-gate.sh backup) and run the iMac backup task by hand"]]
- box-watch-nobody: escalated: old ["escalated=box"] / new ["escalated=imac"]
- box-watch-imac-down: wake_machine_note: old [["box", "machine=box reason=imac_missed neither MBA nor iMac finished by +150 min; run the disabled box task by hand"]] / new [["imac", "machine=imac reason=imac_missed neither MBA nor iMac finished by +150 min; check the iMac backup (night-review-gate.sh backup) and run the iMac backup task by hand"]]
- box-watch-imac-down: escalated: old ["escalated=box"] / new ["escalated=imac"]
- finish-ok: ssh_path: old [["box", "tar", "<SB>/home/xinyue-deploy/nightly-review"], ["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]] / new [["box", "tar", "~/xinyue-deploy/nightly-review"], ["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-vllm-omni.md"]]
- xinyue-primary-normal: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]]
- xinyue-watch-mba-offline: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]]
- xinyue-backup-mba-offline: ssh_path: old [["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]] / new [["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]]
- xinyue-finish-ok: ssh_path: old [["box", "tar", "<SB>/home/xinyue-deploy/nightly-review"], ["box", "grep", "<SB>/home/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]] / new [["box", "tar", "~/xinyue-deploy/nightly-review"], ["box", "grep", "~/xinyue-deploy/nightly-review/2099-02-01-xinyue.md"]]
- xinyue-box-watch-nobody: wake_machine_note: old [["box", "machine=box reason=imac_missed neither MBA nor iMac finished by +150 min; run the disabled box task by hand"]] / new [["imac", "machine=imac reason=imac_missed neither MBA nor iMac finished by +150 min; check the iMac backup (night-review-gate.sh backup) and run the iMac backup task by hand"]]
- xinyue-box-watch-nobody: escalated: old ["escalated=box"] / new ["escalated=imac"]
