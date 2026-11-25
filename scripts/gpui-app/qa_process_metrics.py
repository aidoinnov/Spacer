"""Read-only process metrics adapters for owned GUI/native QA children."""
import ctypes
import os
import subprocess
import sys


class DarwinProbe:
    class Usage(ctypes.Structure):
        _fields_ = [('uuid', ctypes.c_ubyte * 16), ('values', ctypes.c_uint64 * 18)]

    def __init__(self):
        assert ctypes.sizeof(self.Usage) == 160
        self.lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
        self.lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]

    def processes(self):
        rows = {}
        for line in subprocess.check_output(['ps', '-axo', 'pid=,ppid=,comm='], text=True).splitlines():
            fields = line.strip().split(None, 2)
            if len(fields) == 3:
                rows[int(fields[0])] = (int(fields[1]), fields[2])
        return rows

    def info(self, pid):
        value = self.Usage()
        if self.lib.proc_pid_rusage(pid, 2, ctypes.byref(value)):
            raise ProcessLookupError(pid)
        return {'pid': pid, 'resident_bytes': value.values[6],
                'footprint_bytes': value.values[7], 'creation_token': value.values[8]}


class WindowsProbe:
    class Entry(ctypes.Structure):
        _fields_ = [('size', ctypes.c_uint32), ('usage', ctypes.c_uint32),
                    ('pid', ctypes.c_uint32), ('heap', ctypes.c_size_t),
                    ('module', ctypes.c_uint32), ('threads', ctypes.c_uint32),
                    ('parent', ctypes.c_uint32), ('priority', ctypes.c_int32),
                    ('flags', ctypes.c_uint32), ('name', ctypes.c_wchar * 260)]

    class Memory(ctypes.Structure):
        _fields_ = [('cb', ctypes.c_uint32), ('faults', ctypes.c_uint32)] + [
            (name, ctypes.c_size_t) for name in
            ('peak', 'resident', 'peak_paged', 'paged', 'peak_nonpaged',
             'nonpaged', 'pagefile', 'peak_pagefile', 'private')]

    def __init__(self):
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.psapi = ctypes.WinDLL('psapi', use_last_error=True)
        self.kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
        self.kernel.OpenProcess.restype = ctypes.c_void_p
        self.kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        self.kernel.CreateToolhelp32Snapshot.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
        self.kernel.CreateToolhelp32Snapshot.restype = ctypes.c_void_p
        self.kernel.Process32FirstW.argtypes = [ctypes.c_void_p, ctypes.POINTER(self.Entry)]
        self.kernel.Process32NextW.argtypes = [ctypes.c_void_p, ctypes.POINTER(self.Entry)]
        self.kernel.QueryFullProcessImageNameW.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint32)]
        self.kernel.GetProcessTimes.argtypes = [ctypes.c_void_p] + [ctypes.c_void_p] * 4
        self.psapi.GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32]
        assert ctypes.sizeof(self.Memory) == 80

    def handle(self, pid):
        handle = self.kernel.OpenProcess(0x410, False, pid)
        if not handle:
            raise ProcessLookupError(pid)
        return handle

    def processes(self):
        snapshot = self.kernel.CreateToolhelp32Snapshot(2, 0)
        if snapshot in (None, ctypes.c_void_p(-1).value):
            raise OSError(ctypes.get_last_error(), 'Process snapshot failed')
        rows = {}
        try:
            entry = self.Entry(); entry.size = ctypes.sizeof(entry)
            more = self.kernel.Process32FirstW(snapshot, ctypes.byref(entry))
            while more:
                rows[entry.pid] = (entry.parent, entry.name)
                more = self.kernel.Process32NextW(snapshot, ctypes.byref(entry))
        finally:
            self.kernel.CloseHandle(snapshot)
        return rows

    def path(self, pid):
        handle = self.handle(pid)
        try:
            text = ctypes.create_unicode_buffer(32768); size = ctypes.c_uint32(len(text))
            if not self.kernel.QueryFullProcessImageNameW(handle, 0, text, ctypes.byref(size)):
                raise ProcessLookupError(pid)
            return text.value
        finally:
            self.kernel.CloseHandle(handle)

    def info(self, pid):
        handle = self.handle(pid)
        try:
            memory = self.Memory(); memory.cb = ctypes.sizeof(memory)
            if not self.psapi.GetProcessMemoryInfo(handle, ctypes.byref(memory), memory.cb):
                raise ProcessLookupError(pid)
            times = [ctypes.c_uint64() for _ in range(4)]
            if not self.kernel.GetProcessTimes(handle, *(ctypes.byref(t) for t in times)):
                raise ProcessLookupError(pid)
            return {'pid': pid, 'resident_bytes': memory.resident,
                    'private_commit_bytes': memory.private, 'creation_token': times[0].value}
        finally:
            self.kernel.CloseHandle(handle)


def create_probe():
    if sys.platform == 'darwin':
        return DarwinProbe()
    if sys.platform == 'win32':
        return WindowsProbe()
    raise RuntimeError('Unsupported QA metrics host')


def foreground_pid():
    """Observe focus without UI input; a locked Windows desktop may return zero."""
    if sys.platform == 'darwin':
        text = subprocess.check_output(['/usr/bin/osascript','-l','JavaScript','-e',
            "ObjC.import('AppKit'); $.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier"],text=True,timeout=5)
        return int(text.strip())
    if sys.platform == 'win32':
        user=ctypes.WinDLL('user32',use_last_error=True)
        user.GetForegroundWindow.restype=ctypes.c_void_p
        user.GetWindowThreadProcessId.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint32)]
        pid=ctypes.c_uint32()
        user.GetWindowThreadProcessId(user.GetForegroundWindow(),ctypes.byref(pid))
        return pid.value
    raise RuntimeError('Unsupported foreground observation host')


def hidden_process_options():
    """Keep console QA children from creating a Windows console window."""
    return {'creationflags':subprocess.CREATE_NO_WINDOW} if sys.platform=='win32' else {}


def mark_fixture_hidden(path):
    """A leading dot is not FILE_ATTRIBUTE_HIDDEN on Windows."""
    if sys.platform=='win32':
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.GetFileAttributesW.argtypes=[ctypes.c_wchar_p]
        kernel.GetFileAttributesW.restype=ctypes.c_uint32
        kernel.SetFileAttributesW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32]
        flags=kernel.GetFileAttributesW(str(path))
        if flags==0xFFFFFFFF or not kernel.SetFileAttributesW(str(path),flags|2):
            raise OSError(ctypes.get_last_error(),'Cannot mark owned fixture hidden')


def same_path(left, right):
    return os.path.normcase(os.path.realpath(left)) == os.path.normcase(os.path.realpath(right))


def owned_snapshot(probe, gui_pid, native_path):
    rows = probe.processes(); native = []
    for pid, (parent, path) in rows.items():
        if parent != gui_pid:
            continue
        try:
            path = probe.path(pid) if hasattr(probe, 'path') else path
            if same_path(path, native_path):
                native.append(dict(probe.info(pid), path=path))
        except ProcessLookupError:
            continue
    gui = probe.info(gui_pid)
    return {'gui': gui, 'native': native,
            'summed_resident_bytes': gui['resident_bytes'] + sum(p['resident_bytes'] for p in native)}


class ExitWitness:
    """Observe kernel exit without reaping Popen's child or changing its state."""
    def __init__(self, probe, pid):
        import threading
        import time
        self.probe = probe; self.pid = pid; self.result = None
        self.started = time.monotonic(); self.stop = threading.Event()
        if isinstance(probe, DarwinProbe):
            import select
            self.queue = select.kqueue()
            self.queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                fflags=select.KQ_NOTE_EXIT | 0x04000000)], 0, 0)
            self.handle = None
        else:
            self.queue = None
            self.handle = probe.kernel.OpenProcess(0x100000 | 0x1000, False, pid)
            if not self.handle: raise ProcessLookupError(pid)
            probe.kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
            probe.kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
        def observe():
            try:
                while not self.stop.is_set():
                    if self.queue is not None:
                        events = self.queue.control([], 1, .1)
                        if not events: continue
                        event = events[0]
                        self.result = {'exitCode': os.waitstatus_to_exitcode(event.data),
                            'statusPresent': bool(event.fflags & 0x04000000),
                            'observedSeconds': time.monotonic()-self.started}
                        return
                    if probe.kernel.WaitForSingleObject(self.handle, 100) == 0:
                        code = ctypes.c_uint32()
                        if not probe.kernel.GetExitCodeProcess(self.handle, ctypes.byref(code)):
                            raise OSError('Exit code observation failed')
                        self.result = {'exitCode': code.value, 'statusPresent': True,
                            'observedSeconds': time.monotonic()-self.started}
                        return
            except BaseException as error:
                self.result = {'error': repr(error)}
        self.thread = threading.Thread(target=observe, daemon=True); self.thread.start()

    def close(self):
        self.stop.set(); self.thread.join(timeout=2)
        if self.queue is not None:
            self.queue.close(); self.queue=None
        if self.handle:
            self.probe.kernel.CloseHandle(self.handle); self.handle=None


def diagnose_exit_timeout(probe, pid, prefix):
    """Best-effort evidence for a still-owned GUI; never signal another process."""
    import pathlib
    prefix = pathlib.Path(prefix)
    result = {'pid': pid}
    def metrics():
        try: result['metrics'] = probe.info(pid)
        except (ProcessLookupError, OSError) as error:
            # Missing RSS is not evidence that the process has disappeared.
            result['metricsUnavailable'] = repr(error)
    if isinstance(probe, DarwinProbe):
        try:
            state = subprocess.run(['ps','-p',str(pid),'-o','pid=,ppid=,stat=,wchan=,etime=,rss=,comm='],capture_output=True,text=True,timeout=5)
            result['processState'] = state.stdout
            if not state.stdout.strip() and state.returncode == 1:
                result['alreadyExited'] = True
                return result
            fields = state.stdout.split()
            if len(fields) >= 3 and 'E' in fields[2]:
                result['exitInProgress'] = True
        except (OSError, subprocess.TimeoutExpired) as error:
            result['processStateError'] = repr(error)
        if result.get('exitInProgress'):
            result['metricsSkipped'] = 'OS reports exit in progress; preserve state before querying optional metrics'
        else:
            metrics()
        path = str(prefix)+'.sample.txt'
        result['sampleCommandDeadlineSeconds'] = 15
        try:
            # Sampling takes one second; debugger setup/reporting has its own cap.
            # This does not change the separate eight-second GUI close deadline.
            sampled = subprocess.run(['/usr/bin/sample',str(pid),'1','1','-file',path],capture_output=True,text=True,timeout=15)
            result.update(sample=path, sampleExit=sampled.returncode,
                          sampleMessage=(sampled.stdout+sampled.stderr)[-1500:])
        except (OSError, subprocess.TimeoutExpired) as error:
            result['sampleError'] = repr(error)
            if isinstance(error, subprocess.TimeoutExpired):
                def decoded(value):
                    return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
                result['sampleMessage'] = (decoded(error.stdout)+decoded(error.stderr))[-2000:]
    else:
        try:
            if pid not in probe.processes():
                result['alreadyExited'] = True
                return result
            metrics()
            # MiniDumpNormal for this owned PID only; no full heap dump.
            dbg = ctypes.WinDLL('dbghelp', use_last_error=True)
            probe.kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
            probe.kernel.CreateFileW.restype = ctypes.c_void_p
            dbg.MiniDumpWriteDump.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
            path = str(prefix)+'.dmp'; process = probe.handle(pid); file = None
            try:
                file = probe.kernel.CreateFileW(path, 0x40000000, 0, None, 2, 0x80, None)
                if file in (None, ctypes.c_void_p(-1).value): raise OSError('Owned dump file open failed')
                okay = dbg.MiniDumpWriteDump(process, pid, file, 0, None, None, None)
                result.update(dump=path, dumpSucceeded=bool(okay), dumpError=ctypes.get_last_error() if not okay else 0)
            finally:
                if file not in (None, ctypes.c_void_p(-1).value): probe.kernel.CloseHandle(file)
                probe.kernel.CloseHandle(process)
        except (OSError, ProcessLookupError) as error:
            result['dumpError'] = repr(error)
    return result


def start_installed_app(path, log):
    """Launch one user-authorized installed app without mouse/keyboard input."""
    if sys.platform=='darwin':
        subprocess.run(['open','-a',str(path)],check=True)
        return None
    if sys.platform=='win32':
        return subprocess.Popen([str(path)],stdout=log,stderr=log)
    raise RuntimeError('Unsupported installed app host')


def verify_installed_resources(app, server):
    """Check integrity after bundled Python has actually run."""
    from pathlib import Path
    cache=list(Path(server).parent.glob('__pycache__/*.pyc'))
    if cache:raise AssertionError('Bundled MCP wrote bytecode: '+str(cache))
    result={'bundledBytecodeRemaining':[]}
    if sys.platform=='darwin':
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
        result['signatureVerifiedAfterMCP']=True
    return result
