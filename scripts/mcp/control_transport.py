"""Windows named-pipe transport; Mac keeps its existing UID-checked Unix port."""
import json
import os
import time
from pathlib import Path


def _pipe_available(kernel, name, timeout_ms, busy_is_live=False):
    """The server briefly has no pipe instance while replacing a used handle."""
    import ctypes
    deadline = time.monotonic() + timeout_ms / 1000
    while True:
        if kernel.WaitNamedPipeW(name, 1 if busy_is_live else 50):
            return True
        error = ctypes.get_last_error()
        if busy_is_live and error in (121, 231):
            return True
        if error not in (2, 121, 231) or time.monotonic() >= deadline:
            return False
        time.sleep(.01)


def windows_directory():
    return Path(os.environ['LOCALAPPDATA']) / 'SpaceSniffer' / 'control'


def windows_instances(directory, bundle_id, private=False):
    import ctypes
    result = []
    for path in directory.glob('*.json'):
        try:
            info = path.lstat()
            if not path.is_file() or info.st_size > 16384 or getattr(info, 'st_file_attributes', 0) & 0x400:
                continue
            descriptor = json.loads(path.read_text(encoding='utf-8-sig'))
            if descriptor.get('bundle_id') != bundle_id or descriptor.get('version') != 1:
                continue
            pid = int(descriptor['pid'])
            # A query-only process handle establishes liveness without os.kill on Windows.
            kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            kernel.OpenProcess.restype = ctypes.c_void_p
            kernel.CloseHandle.argtypes = [ctypes.c_void_p]
            process = kernel.OpenProcess(0x1000, False, pid)
            if not process:
                continue
            kernel.CloseHandle(process)
            expected = '\\\\.\\pipe\\space-sniffer-' + path.stem
            if descriptor.get('pipe') != expected or len(descriptor.get('token', '')) != 64:
                continue
            # A PID can be reused after a crash/reboot while its descriptor remains.
            # A busy existing pipe is live; a missing/inaccessible pipe is stale.
            kernel.WaitNamedPipeW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint]
            if not _pipe_available(kernel, expected, 200, busy_is_live=True):
                continue
            if not private:
                descriptor = {key: value for key, value in descriptor.items() if key not in ('token', 'pipe')}
            result.append(descriptor)
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return sorted(result, key=lambda item: item['pid'])


def windows_exchange(descriptor, request):
    import ctypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.WaitNamedPipeW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint]
    deadline = time.monotonic() + 5
    while True:
        if not _pipe_available(kernel, descriptor['pipe'], max(1, int((deadline - time.monotonic()) * 1000))):
            raise OSError(ctypes.get_last_error(), 'Named pipe unavailable')
        try:
            client = open(descriptor['pipe'], 'r+b', buffering=0)
            break
        except OSError as error:
            # Retry connection acquisition only: never replay a written command.
            if getattr(error, 'winerror', None) not in (2, 121, 231) or time.monotonic() >= deadline:
                raise
            time.sleep(.01)
    data = bytearray()
    with client:
        client.write(json.dumps(request, separators=(',', ':')).encode() + b'\n')
        while b'\n' not in data:
            part = client.read(65536)
            if not part:
                raise RuntimeError('App disconnected before responding')
            data.extend(part)
            if len(data) > 16777216:
                raise RuntimeError('App response exceeds 16 MiB')
    return data
