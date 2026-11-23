#!/usr/bin/env python3
"""Summarise a docker/harness/run.sh output directory; exit 1 unless everything passed.

  report.py <out-dir>
"""
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
failed = False

vt_rc = (out / 'gamedata-vtables.rc').read_text().strip() if (out / 'gamedata-vtables.rc').exists() else '?'
vt_text = (out / 'gamedata-vtables.txt').read_text().strip() if (out / 'gamedata-vtables.txt').exists() else ''
# rc "skip": the runner can't do this check (Windows: server.dll has no symbols)
vt_status = {'0': 'PASS', 'skip': 'SKIP'}.get(vt_rc, 'FAIL')
print(f"gamedata vtables (offline): {vt_status}  {vt_text.splitlines()[-1] if vt_text else 'no output'}")
for line in vt_text.splitlines()[:-1]:
    print('    ' + line.strip())
failed |= vt_status == 'FAIL'

srcds_rc = (out / 'srcds.rc').read_text().strip() if (out / 'srcds.rc').exists() else '?'
if (out / 'srcds.exitcode').exists():        # Windows: the full exit code
    srcds_rc += f" = {(out / 'srcds.exitcode').read_text().strip()}"


def print_crash():
    """The report written when the server crashes: by tools/srcds-gdb.sh (Linux) or from
    Windows Error Reporting's dump (run-windows.sh, CRASH_DUMPS=1)."""
    crash = out / 'crash.txt'
    if crash.exists():
        lines = crash.read_text(errors='replace').splitlines()
        print(f'\n--- crash.txt ({len(lines)} lines, first 120)')
        print('\n'.join(lines[:120]))


results_file = out / 'results.json'
if not results_file.exists():
    print(f'\nFAIL: no results.json (srcds exit {srcds_rc}). Last console lines:')
    for name in ('console.log', 'srcds_run.log'):
        path = out / name
        if path.exists():
            print(f'--- {name}'); print('\n'.join(path.read_text(errors='replace').splitlines()[-25:]))
    print_crash()
    sys.exit(1)

results = json.loads(results_file.read_text())
print(f"\n{results.get('game')} / engine {results.get('engine')} / branch {results.get('branch')}"
      f"  (srcds exit {srcds_rc}{', 124 = timeout' if srcds_rc == '124' else ''})")
counts = {'pass': 0, 'fail': 0, 'skip': 0, 'xfail': 0, 'xpass': 0}
for name, entry in results['checks'].items():
    status = entry['status']
    counts[status] += 1
    print(f"  {status.upper():5} {name:42} {entry.get('value') or ''}")
    if entry.get('reason'):
        print(f"        known issue: {entry['reason']}")
    if entry.get('error') and status == 'fail':
        print('        ' + entry['error'].strip().replace('\n', '\n        '))
if results.get('running'):
    print(f"\nFAIL: server stopped while running {results['running']!r} (crash?)")
    print_crash()
    failed = True
elif not results.get('finished'):
    print('\nFAIL: run did not finish (timeout?)')
    failed = True
elif (out / 'crash.txt').exists():
    # every check ran; the server crashed while shutting down (not counted as a failure yet)
    print('\nWARNING: the server crashed after the checks had finished (shutting down)')
    print_crash()
failed |= counts['fail'] > 0
print(f"\n{counts['pass']} passed, {counts['fail']} failed, {counts['skip']} skipped, "
      f"{counts['xfail']} known issues, {counts['xpass']} known issues now passing"
      f" -> {'FAIL' if failed else 'PASS'}")
sys.exit(1 if failed else 0)
