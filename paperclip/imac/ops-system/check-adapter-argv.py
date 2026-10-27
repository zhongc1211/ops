#!/usr/bin/python3 -I
"""Offline captured-argv contract check, NOT a permissions probe or adapter E2E.
Only reads this repository's example and calls the pure argument filter.
Does not read a real MCP config, import installed code, call APIs or spawn anything.
"""
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import host


def main():
    example = json.loads((HERE / 'adapter-argv.example.json').read_text())
    incoming = example['commandArgs']
    host.CONF = {'settings': incoming[incoming.index('--settings') + 1]}
    outgoing = host.args_checked(incoming)
    retained = incoming.copy()
    pos = retained.index('--mcp-config')
    discarded_path = retained[pos + 1]
    del retained[pos:pos + 2]
    retained.remove('--strict-mcp-config')
    expected = retained + ['--max-budget-usd', '2', '--tools', 'Bash', '--setting-sources', '',
                           '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}']
    host.require(outgoing == expected, 'captured_argv_contract_changed')
    host.require(outgoing.count('--mcp-config') == 1 and outgoing.count('--strict-mcp-config') == 1
                 and discarded_path not in outgoing, 'adapter_mcp_not_discarded')
    print('PASS: full captured adapter argv recognized; only strict empty MCP forwarded')
    print('No model/API/permissions probe/real MCP file access; server counting is not runtime-verified')


if __name__ == '__main__':
    main()
