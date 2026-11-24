"""Discovery must not resurrect a stale descriptor when Windows reuses its PID."""
import ctypes
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('control_transport_tested', Path(__file__).with_name('control_transport.py'))
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


class WindowsDiscoveryTests(unittest.TestCase):
    def test_pipe_replacement_gap_is_not_a_stale_controller(self):
        kernel = Mock()
        kernel.WaitNamedPipeW.side_effect = [False, False, True]
        with patch.object(ctypes, 'get_last_error', return_value=2, create=True), patch.object(transport.time, 'sleep'):
            self.assertTrue(transport._pipe_available(kernel, 'owned-fixture', 200, busy_is_live=True))
        self.assertEqual(kernel.WaitNamedPipeW.call_count, 3)

    def test_connection_race_retries_before_writing_and_never_replays_request(self):
        kernel = Mock()
        kernel.WaitNamedPipeW.return_value = True
        busy = OSError('another client acquired the pipe')
        busy.winerror = 231
        client = Mock()
        client.__enter__ = Mock(return_value=client)
        client.__exit__ = Mock(return_value=False)
        client.read.return_value = b'{"result":{}}\n'
        request = {'id': 'owned-fixture', 'command': 'scan_start'}
        with patch.object(ctypes, 'WinDLL', return_value=kernel, create=True), patch('builtins.open', side_effect=[busy, client]) as acquire, patch.object(transport.time, 'sleep'):
            self.assertEqual(transport.windows_exchange({'pipe': 'owned-fixture'}, request), b'{"result":{}}\n')
        self.assertEqual(acquire.call_count, 2)
        client.write.assert_called_once_with(json.dumps(request, separators=(',', ':')).encode() + b'\n')

    def test_alive_reused_pid_requires_a_live_pipe_but_busy_is_not_stale(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '3450-abcdef01.json'
            path.write_text(json.dumps({'pid': 3450, 'version': 1, 'bundle_id': 'fixture',
                                        'pipe': '\\\\.\\pipe\\space-sniffer-' + path.stem, 'token': 'a' * 64}))
            kernel = Mock()
            kernel.OpenProcess.return_value = 123  # PID exists, possibly reused.
            with patch.object(ctypes, 'WinDLL', return_value=kernel, create=True), patch.object(ctypes, 'get_last_error', create=True) as error:
                for available, code, expected in [(False, 2, 0), (False, 5, 0), (False, 121, 1), (False, 231, 1), (True, 0, 1)]:
                    with self.subTest(available=available, error=code):
                        kernel.WaitNamedPipeW.return_value = available
                        error.return_value = code
                        found = transport.windows_instances(Path(directory), 'fixture')
                        self.assertEqual(len(found), expected)
                        if found:
                            self.assertNotIn('token', found[0])
                            self.assertNotIn('pipe', found[0])


if __name__ == '__main__':
    unittest.main()
