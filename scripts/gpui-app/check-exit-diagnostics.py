#!/usr/bin/env python3
"""Exercise exit evidence on an owned sleeping child; no GUI input or failure injection in product."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time

from qa_process_metrics import create_probe, ExitWitness, diagnose_exit_timeout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists(), 'Refusing evidence overwrite'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items()
           if key.upper() in {'PATH', 'SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP', 'HOME'}}
    child = subprocess.Popen([sys.executable, '-I', '-c',
                              'import time; print("owned-diagnostic-ready", flush=True); time.sleep(120)'],
                             env=env, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    witness = None
    report = {'passed': False, 'platform': sys.platform, 'ownedPid': child.pid,
              'scope': 'Synthetic wait deadline on owned sleeping Python; diagnostic port test, not a product hang or historical root-cause reproduction'}
    try:
        probe = create_probe()
        witness = ExitWitness(probe, child.pid)
        ready = threading.Event()
        def await_ready():
            if child.stdout.readline().rstrip(b'\r\n') == b'owned-diagnostic-ready':
                ready.set()
        reader = threading.Thread(target=await_ready, daemon=True)
        reader.start()
        assert ready.wait(15), 'Owned diagnostic child did not finish startup'
        report['childStartupReady'] = True
        try:
            child.wait(timeout=.2)
            raise AssertionError('Sleeping child exited before deliberate deadline')
        except subprocess.TimeoutExpired:
            report['deliberateDeadlineObserved'] = True
        report['diagnostic'] = diagnose_exit_timeout(probe, child.pid, args.output.with_suffix('.owned'))
        diagnostic = report['diagnostic']
        if sys.platform == 'darwin':
            assert diagnostic.get('sampleExit') == 0 and Path(diagnostic['sample']).stat().st_size, diagnostic
        else:
            assert diagnostic.get('dumpSucceeded') and Path(diagnostic['dump']).stat().st_size, diagnostic
        # Exercise the degraded-metrics path on this same live, owned process.
        original_info = probe.info
        def unavailable_metrics(pid):
            raise ProcessLookupError('Deliberate metric-port failure on owned diagnostic child')
        try:
            probe.info = unavailable_metrics
            degraded = diagnose_exit_timeout(probe, child.pid, args.output.with_suffix('.missing-metrics'))
        finally:
            probe.info = original_info
        report['missingMetricsDiagnostic'] = degraded
        assert degraded.get('metricsUnavailable') and not degraded.get('alreadyExited'), degraded
        if sys.platform == 'darwin':
            assert degraded.get('processState', '').strip() and degraded.get('sampleExit') == 0, degraded
        else:
            assert degraded.get('dumpSucceeded'), degraded
        child.terminate()
        child.wait(timeout=8)
        deadline = time.monotonic()+2
        while witness.result is None and time.monotonic() < deadline:
            time.sleep(.02)
        report.update(exitCode=child.returncode, exitWitness=witness.result)
        assert witness.result and witness.result.get('statusPresent'), witness.result
        assert witness.result['exitCode'] == child.returncode, report
        report['passed'] = True
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=8)
        if witness:
            witness.close()
        if child.stdout:
            child.stdout.close()
        args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'passed': report['passed'], 'exitCode': report['exitCode']}))


if __name__ == '__main__':
    main()
