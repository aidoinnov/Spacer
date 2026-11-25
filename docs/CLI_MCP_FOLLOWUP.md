# CLI and MCP follow-up — 2026-11-25

New source builds include a headless console companion for macOS and Windows.
The GUI forwards `--cli` before initializing GPUI. Both hosts use the existing
native document transport, filter grammar and atomic output writer. There is no
new scan-engine implementation in this change.

The installed applications and frozen November 24 packages remain unchanged.
Functional packages for this audit reuse the installed **184B backends**, not the
unadopted 168B source candidate. These results do not admit a performance change.
See [CLI usage and compatibility limits](HEADLESS_CLI.md).

## Completed checks

| Check | macOS arm64 | Windows 132 x64 |
|---|---:|---:|
| Console CLI functional cases | 27/27 | 27/27 |
| GPUI forwarding functional cases | 27/27 | 27/27 |
| Console unit tests | 7/7 | 7/7 |
| GUI unit tests | 31/31 | 32/32 |
| MCP protocol/transport unit tests | 18/18 | 18/18 |
| Real STDIO MCP | 16/16 scenario groups, 22 tool types | 17/17 scenario groups, 22 tool types |
| Console clippy, warnings denied | Passed | Passed |
| GUI clippy, warnings denied | Passed | Passed |
| Packaged console without backend override | Passed | Passed |

The CLI scenarios cover scan counts and bytes, Unicode paths, native filtering,
hidden attributes, SNS save/load/root inspection, TXT and configured exports,
invalid inputs, and preservation of existing destinations. The Windows fixture
explicitly sets FILE_ATTRIBUTE_HIDDEN; a dot-prefixed name alone is not hidden on
Windows. The initial fixture-only failure is preserved in the raw evidence.

## Cancellation and process release

`check-cli-lifecycle.py` exercises a real native child on success, invalid-filter
failure and private-parent-stdin EOF; macOS additionally receives SIGINT. Each
case checks the CLI exit code, kernel exit notification and process identity.
macOS passed four paths and Windows passed three. All observed native children
exited with code 0; no owned native process or scratch directory remained.

Windows can still return information about an already-terminated process object.
The initial assertion treated a successful OpenProcess call as proof that the
process was still running; that was insufficient. The final check uses kernel
exit observation and a bounded process-list settling check. Test observer handles are closed idempotently.

Windows filesystem cancellation was tested separately from immediate start/stop:
a disposable input contained **524,288 files in 16,384 branches**. MCP status
reported **98,336 files read**, phase `scanning`, and 13,311 pending folders
before stop. The final state was `cancelled` with 161,888 partial files. This
proves cancellation during actual file reading, not an idle stop. This fixture
is a functional cancellation probe, not a throughput benchmark.

Mac separately observed 6,752 files read in a 131,072-file
fixture, then settled cancelled with 52,288 partial files.

The separate Windows large-SNS import was observed `running`, cancelled through MCP,
and ended `cancelled` with the previous document revision preserved.

## Scratch-file lifetime correction

The final audit found a normal-exit race: native processes exited, but the GUI
could end before its detached stdout reader removed `snapshot.ssw`. The CLI had
the same risk immediately before returning its exit code. Earlier fixture cleanup
could hide this because it removed the outer temporary directory afterward.

`session_lifecycle` now registers exact owned child handles, command channels and
scratch paths. Normal exit requests stop for all owned engines, waits with one
shared grace budget, reaps remaining children and removes scratch directories
before the host exits. Registration during shutdown is immediately drained.
Reader completion unregisters finished sessions; the registry does not retain
GUI documents. No OS-specific branch was added to the common lifecycle.

GPUI's upstream quit futures have a 200 ms polling budget. Required cleanup runs
inside the quit callback before returning its ready future. Final tests inspect
scratch paths **before** deleting the outer fixture, and close the last window
while file reading is active. Forced OS termination remains a separate case.

## Window lifecycle and user input

`window_new(background=true)` creates a hidden, non-activating idle window.
`window_close` requires both `instance_id` and `window_id`, so a client must name
the window it intends to close. The acceptance run creates and closes a second
window while checking the original document revision. Windows foreground PID
was unchanged before and after; no mouse or keyboard automation was used.

One Windows cursor run failed when the default filesystem watcher initiated a
rescan during pagination. A separate 30-iteration trace captured phase changing
from scanning to completed and a different revision; one request received the
expected `projection_pending` rejection. The original suite wrongly assumed an
immutable revision while watching was enabled. Stable-query setup now explicitly
starts its owned scan with `watching=false` and asserts the watcher is inactive.
It does not retry a consumed cursor. Failed runs and traces remain in the evidence.

Final last-window close checks began while files were being read. The Mac GUI
exited 0 in 81.52 ms and Windows in 134.13 ms; owned native processes and scratch
directories were empty afterward.
These are functional exit probes, not a resolution of the historical delay.

The STDIO suite also covers authenticated controller access, discovery without
credentials, pagination/revisions, bounded cursor release, navigation/filtering,
tag toggles, resources, atomic artifact jobs, malformed-load rollback, configured
export limits, PNG capture, scoped rescan and recovery after malformed requests.

## Packaging, evidence and remaining scope

Windows composition includes the console companion alongside the production GUI,
installed 184B backend, preview helper, Swift DLLs and MCP scripts. The 39-file
manifest records SHA-256 for each file. The production binary rejects QA-only
launch options before creating a window. No installation was replaced.

The Mac functional bundle has 10 manifested files, passes ad-hoc signature
verification and rejects QA-only options. Its console and GUI forwarding paths
both pass the functional suite without a backend override. The Mac GUI/CLI use
`dev` profile with debug information disabled; Windows binaries use `release`.
These are audit artifacts, not a new optimized Mac release or public installer.
The official Python MCP SDK 2.3.0 independently passed modern `2026-07-28` and
legacy `2025-11-25` negotiation, the 22-tool catalog, Unicode structured content,
PNG content and tool-error envelopes on Mac.

Raw evidence is retained under
`~/Downloads/Spacer-CLI-MCP-Followup-20261125/` from the isolated audit workspace.
The owned Windows scheduled task was removed from its registering session; all
final fixtures were removed and zero QA executables remained. The installed
backend SHA-256 still matches the pinned baseline.

The earlier November 24 evidence remains historical and unchanged. Failed and
superseded attempts are retained with their original results.

Formal speed admission, latest disktree comparison, the historical eight-second
exit-delay root cause, clean installer upgrade/uninstall and public signing are
still separate deferred work. This audit does not resolve them. Full historical
Swift CLI settings metadata and distinct XML/legacy configuration code pages are
not implemented by the normalized native-document CLI.
