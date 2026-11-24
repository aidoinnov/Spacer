#!/usr/bin/env python3
"""Run against a dedicated QA instance. Replaces its document with an owned fixture."""
import argparse
import base64
import json
import pathlib
import sys
import tempfile
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'mcp'))
from space_sniffer_mcp import Bridge

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--instance', type=int, required=True)
parser.add_argument('--bundle-id', default='local.macspacesniffer.gpui')
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
bridge = Bridge(args.bundle_id)
checks = []


def call(command, **values):
    return bridge.call_app(command, dict(instance_id=args.instance, **values))


def wait(predicate):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.1)
    raise TimeoutError('Controller acceptance gate timed out')


def ready():
    state = call('app_status')['windows'][0]
    return state if state['phase'] in ('completed', 'completed_with_issues', 'offline') and not state['projection_pending'] else None


def task(command, **values):
    job = call(command, **values)['job_id']

    def finished():
        result = call('task_status', job_id=job)
        return result if result['phase'] not in ('pending', 'running') else None

    result = wait(finished)
    assert result['phase'] == 'completed', result
    checks.append({'command': command, 'result': result})
    return result


with tempfile.TemporaryDirectory(prefix='sniffer-control-acceptance-') as directory:
    output = pathlib.Path(directory)
    fixture = output / 'input'
    (fixture / 'branch').mkdir(parents=True)
    (fixture / 'branch/sample.zip').write_bytes(b'owned verification fixture' * 200)
    (fixture / 'second.txt').write_text('owned verification fixture')
    call('scan_start', path=str(fixture))
    state = wait(ready)
    root = state['root']  # Native canonicalization may resolve /private/tmp to /tmp.
    assert state['files'] == 2, state
    for command in ['node_info', 'tree_children', 'query_nodes', 'largest_nodes', 'scan_issues']:
        assert isinstance(call(command, path=root, limit=1), dict)
        checks.append(command)
    call('node_tag', path=str(pathlib.Path(root) / 'branch'), color=1)
    sns = str(output / 'roundtrip.sns')
    task('snapshot_save', output=sns)
    task('report_export', output=str(output / 'simple.txt'))
    try:
        call('snapshot_save', output=sns)
    except RuntimeError as error:
        assert 'output_exists' in str(error), error
        checks.append('existing_output_preserved')
    else:
        raise AssertionError('Existing output was accepted')
    template = '<%pathfile%>{&br}'
    encoded = base64.b64encode(template.encode('utf-16le')).decode()
    config = output / 'format.xml'
    config.write_text(f'<exportConfig version="3"><description>Owned QA format</description><detailFormat>{encoded}</detailFormat><blockSorting>files</blockSorting><fineSorting>size</fineSorting><fineSortingDirection>desc</fineSortingDirection></exportConfig>')
    task('report_export', configuration_path=str(config), inspect_only=True, config_xml_code_page=65001)
    task('report_export', output=str(output / 'configured.txt'), configuration_path=str(config), configuration_index=0, config_xml_code_page=65001)
    assert 'sample.zip' in (output / 'configured.txt').read_text()
    task('snapshot_load', path=sns, inspect_only=True)
    task('snapshot_load', path=sns)
    state = wait(ready)
    assert state['offline'] and not state['watch_active'], state
    for mode in ['minimized', 'hidden', 'normal']:
        call('view_set', window_state=mode)
        state = call('app_status')['windows'][0]
        if mode == 'minimized':
            assert state['window_minimized'], state
        if mode == 'normal':
            assert state['window_visible'] and not state['window_minimized'], state
        checks.append({'windowState': mode, 'visible': state['window_visible'], 'minimized': state['window_minimized']})
    second = call('window_new')['window_id']
    assert len(call('app_status')['windows']) == 2
    call('window_close', window_id=second)
    assert len(call('app_status')['windows']) == 1
    checks.append('new_window_close_preserves_first')
    image = call('view_capture')['image']
    args.output.with_suffix('.png').write_bytes(base64.b64decode(image['data']))
    checks.append('capture_after_restore_and_second_window_close')
    report = {'passed': True, 'instance': args.instance, 'checks': checks, 'resources': call('app_resources')}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    # End the owned native document before removing its input fixture.
    last = call('app_status')['windows'][0]['window_id']
    call('window_close', window_id=last)
print(json.dumps(report))
