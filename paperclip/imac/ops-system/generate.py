#!/usr/bin/env python3
"""Deterministically generate the permission file; no live system access."""
import argparse
import json
from pathlib import Path


def settings(home):
    root = str(Path(home) / '.local/share/paperclip-ops/ops-system-host')
    helper = root + '/linear-safe.py'
    return {
        'disableAllHooks': True,
        'permissions': {
            'defaultMode': 'dontAsk',
            'disableBypassPermissionsMode': 'disable',
            'allow': ['Bash(' + helper + ' read)', 'Bash(' + helper + ' log *)',
                      'Bash(' + helper + ' comment *)'],
            # Read is denied too: its default behavior is not a path sandbox.
            'deny': ['Read', 'Glob', 'Grep', 'Edit', 'Write', 'NotebookEdit', 'WebFetch', 'WebSearch',
                     'Agent', 'Task', 'mcp__*', 'Bash(curl *)', 'Bash(python*)', 'Bash(node *)',
                     'Bash(ssh *)', 'Bash(gh *)', 'Bash(git *)', 'Bash(orca *)',
                     'Bash(orca-agent-launch *)', 'Bash(' + root + '/host.py*)',
                     'Bash(' + root + '/install*)'] +
                    [tool + '(' + path + ')' for tool in ('Read', 'Write', 'Edit') for path in (
                        root + '/**', str(Path(home) / '.paperclip/**'),
                        str(Path(home) / 'ops-archive/travel-1026/**'),
                        str(Path(home) / '.config/paperclip-ops/triggers/**'),
                        str(Path(home) / '.config/grokbot/**'))],
        },
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--home', default='/Users/jiawenwang')
    parser.add_argument('--output', type=Path, default=Path(__file__).with_name('settings.json'))
    args = parser.parse_args()
    args.output.write_text(json.dumps(settings(args.home), indent=2, ensure_ascii=False) + '\n')
