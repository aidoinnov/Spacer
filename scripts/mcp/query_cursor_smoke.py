#!/usr/bin/env python3
"""Exercise R15 against an already-running fixture QA window, without scanning."""
import argparse
import json
import time
from pathlib import Path
from space_sniffer_mcp import Bridge

p = argparse.ArgumentParser()
p.add_argument('--bundle-id', required=True)
p.add_argument('--output', required=True)
p.add_argument('--window-id')
p.add_argument('--path')
p.add_argument('--maximum-pages', type=int, default=200)
p.add_argument('--verify-revision-reset', action='store_true')
a = p.parse_args()
assert 1 <= a.maximum_pages <= 10000
out = Path(a.output); out.mkdir(parents=True, exist_ok=False)
b = Bridge(a.bundle_id)
initial = b.call_app('app_status', {})
windows = initial['windows']
window = next(w for w in windows if w['window_id'] == a.window_id) if a.window_id else windows[0]
assert a.window_id or len(windows) == 1, 'Pass --window-id when multiple QA windows exist'
assert window['root'] and not window['projection_pending'], 'Load a small QA fixture first'
assert window['query_session']['cursors'] == 0, 'Use a fixture window without existing cursor clients'
target = {'window_id': window['window_id']}
scope = a.path or window['root']
events = []
def call(command, **args):
    value = b.call_app(command, target | args)
    events.append({'command': command, 'arguments': args, 'result': value})
    return value
def state():
    return call('app_status')
def expected_error(command, expected, **args):
    try: call(command, **args)
    except RuntimeError as e:
        assert str(e).startswith(expected+':'), str(e)
        events.append({'command': command, 'arguments': args, 'error': str(e)})
    else: raise AssertionError('Expected '+expected)
def collect(traversal):
    args = {'path': scope, 'traversal': traversal, 'budget': 7, 'limit': 3}
    result = []; first_token = None; pinned = None
    for _ in range(a.maximum_pages):
        page = call('query_nodes', **args); result.extend(row['path'] for row in page['items'])
        assert page['inspected_nodes'] <= 7
        args['revision'] = page['revision']
        if traversal == 'subtree':
            assert page['traversal_steps'] <= 7 and page['next_offset'] is None
            if pinned is None: pinned = page['evaluated_at']
            else: assert page['evaluated_at'] == pinned
            token = page['next_cursor']
            if first_token is None: first_token = token
            if token is None: return result, first_token
            args['cursor'] = token
        else:
            if page['next_offset'] is None: return result, None
            args['offset'] = page['next_offset']
    if args.get('cursor'): call('query_nodes', traversal='subtree', cursor=args['cursor'], cancel_cursor=True)
    raise AssertionError('Choose a smaller fixture scope or an explicit page cap')

old, _ = collect('snapshot')
new, consumed = collect('subtree')
assert sorted(old) == sorted(new) and len(new) == len(set(new))
if consumed: expected_error('query_nodes', 'stale_cursor', traversal='subtree', cursor=consumed)
tokens = []
for _ in range(10):
    page = call('query_nodes', path=scope, traversal='subtree', budget=1)
    tokens.append(page['next_cursor'])
assert all(tokens), 'Fixture must contain a folder or file visit plus final unwind'
assert state()['query_session']['cursors'] == 8
expected_error('query_nodes', 'stale_cursor', traversal='subtree', cursor=tokens[0])
for token in tokens[-8:]:
    cancelled = call('query_nodes', traversal='subtree', cursor=token, cancel_cursor=True)
    assert cancelled['cancelled'] and cancelled['next_cursor'] is None
assert state()['query_session']['cursors'] == 0
if a.verify_revision_reset:
    previous_expression = state()['filter']
    token = call('query_nodes', path=scope, traversal='subtree', budget=1)['next_cursor']
    before_revision = state()['snapshot_revision']
    try:
        # A semantically equivalent extra empty token still changes the input and
        # public revision; use only an explicitly selected QA fixture window.
        call('view_set', expression=previous_expression+';')
        deadline = time.monotonic()+30
        while time.monotonic() < deadline:
            changed = state()
            if not changed['projection_pending'] and changed['snapshot_revision'] != before_revision: break
            time.sleep(.01)
        else: raise AssertionError('New projection revision was not observed')
        assert changed['query_session']['cursors'] == 0
        expected_error('query_nodes', 'stale_revision', traversal='subtree', cursor=token, revision=before_revision)
    finally:
        call('view_set', expression=previous_expression)
report = {'passed': True, 'scope': scope, 'queries': len(events), 'matched_paths': len(new),
          'revision_reset_verified': a.verify_revision_reset, 'events': events,
          'note': 'Actual fixture app IPC; no scan or disk mutation requested. revision-reset option temporarily changes then restores the UI filter.'}
(out/'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='events'}, ensure_ascii=False))
