# CLI and MCP validation — 2026-11-24

The CLI and MCP were exercised against disposable fixtures and separate, hidden
QA processes. Four defects were reproduced and fixed in source. The installed
applications and frozen 0.3.0 packages were not replaced.

## Results

| Check | Result |
|---|---|
| macOS legacy headless CLI | 27/27 functional cases passed |
| CLI argument/configuration unit tests | 4/4 passed |
| MCP bridge/transport unit tests | 16 passed locally; Windows run exited 0 |
| GPUI Rust unit tests | Mac 30/30, Windows 31/31 |
| Clippy, QA feature, all targets, warnings denied | Passed on both platforms |
| GPUI terminal options | Help, short help, version, explicit unsupported CLI: 4/4 on each platform |
| Real STDIO MCP, Mac | 14/14 scenario groups, 95 RPC requests, 20 tool types exercised |
| Real STDIO MCP, Windows | 13 scenario groups verified, plus stop-request exercise; active cancellation unproven. Raw artifact retrieval pending |
| Official MCP Python SDK 2.3.0, Mac | Auto/2026-07-28 and legacy/2025-11-25 both passed |

These are functional results, not scan-speed measurements. They do not change
the deferred performance acceptance or approve the 168B engine candidate.

## Defects and changes

### Invalid CLI options were silently accepted

The frozen Swift reference CLI returned success for an unknown option, a missing
`--filter` value, duplicate inputs, and simultaneous `--scan`/`--load` inputs.
`HeadlessArguments` now validates the command before scanning or loading. It also
rejects load-only options on a scan and combinations whose options were ignored.

CLI exports previously replaced existing output. TXT, SNS and configured exports
now use the existing atomic publication mechanism with `replaceExisting: false`.
Tests check that an existing file, including an SNS also used as input, keeps its
original bytes. A configured export exceeding its byte cap leaves no final file.

### The GPUI executable treated terminal options as paths

The previous argument loop had no headless CLI dispatch and treated unknown
arguments as initial paths. New terminal-only handling returns help/version
without creating a GPUI application and rejects `--cli` with exit 64.

**The GPUI package still does not contain the legacy headless scan/export CLI.**
The 27 CLI cases above use the separately built macOS Swift reference executable.
This does not establish a Windows headless CLI. Providing that interface in both
production packages remains separate work.

### Windows MCP output used the console encoding

The real Windows STDIO run returned Korean text in its default console code
page. A UTF-8 client failed to decode the response. The bridge now writes UTF-8
JSON bytes directly to stdout, with LF framing, regardless of the console locale.
A regression test forces `PYTHONIOENCODING=ascii`; the Windows real-tool run also
passed Unicode queries and exports after the change.

Falsey non-object `params` are now rejected instead of becoming `{}`. Non-string
tool/resource names return invalid-params errors rather than internal errors.
Pre-initialization ping is accepted; tools still require initialization. Malformed
JSON, an oversized line and invalid requests are followed by a successful request
on the same connection to check recovery.

### An import error remained after a successful operation

Opening malformed SNS data and then starting a valid scan reproduced a completed
scan reported as `failed` on both platforms: `error_dialog` still held the import
error. Starting a scan and successfully installing a snapshot now clear that old
error. Both QA builds passed the failed-load → successful-load/scan sequence.

## What the real MCP scenarios cover

The main fixture has six files, three folders and **8,297 logical bytes**, including
Unicode names, spaces, a hidden file and an empty file. The runner checks the file
oracle rather than trusting the displayed total alone.

- Discovery and the 21-tool catalog; tokens are absent from public descriptors.
- A wrong control token rejects a mutation and leaves the document unchanged.
- Node details, empty-file pagination, stale revisions, top-K and native filters.
- Bounded subtree pagination, cursor cancellation and rejection of a cancelled
  cursor, followed by a working fresh query.
- Navigation, view weights and same-color tag toggling.
- Metrics, volume information and MCP resources. Global resource URIs reject
  ambiguous instances; scoped tool calls use the owned PID/window explicitly.
- SNS inspection/save/load, report jobs, overwrite refusal and failed-load rollback.
- Configured Unicode report export, inspection without view changes and atomic
  cleanup after a byte-cap failure.
- A real PNG image block from the app renderer.
- Live scan, scoped rescan and stop. Mac refreshes the subtree; Windows reports
  its full-root refresh policy.
- Request validation and continued operation after errors.
- Active scan cancellation on an owned 65,536-file fixture.

Mac cancellation was observed while scanning and settled with `cancelled=true`.
Windows accepted stop but settled as completed, so **active filesystem cancellation
was not proved**. That is not counted as a cancellation pass. An optional large-SNS
import cancellation case was added, but the subsequent Windows connection failed
before it could be run.

`window_new` was listed and schema-checked but not executed: it activates a visible
window. This run deliberately avoided taking focus from the user. The suite is not
a claim of exhaustive MCP conformance or every possible file-format combination.

The cancelled-cursor test initially expected the legacy controller's `stale_cursor`
code. The GPUI native document stream carries its explanatory message instead.
The test now checks rejection plus a successful fresh query. Earlier harness errors
around zero-weight pagination, resource field names, Windows-invalid filenames and
projection readiness are retained with the failed attempts; they are not product
failures or silently rewritten passes.

## Independent client check

The official Python SDK was used as a separate client implementation, not as a
server dependency. Both connection modes negotiated their expected version and
validated the catalog, Unicode structured results, an image block and tool errors.
The server ran with an ASCII console setting for this check.

Reference: [official SDK client API](https://py.sdk.modelcontextprotocol.io/client/),
[protocol negotiation](https://py.sdk.modelcontextprotocol.io/protocol-versions/),
and [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle).

## Reproduction

```sh
python3 -m unittest discover -s scripts/mcp -p 'test_*.py' -v

python3 scripts/gpui-app/check-cli.py \
  --binary /path/to/Swift-reference/MacSpaceSniffer \
  --output /new/cli-evidence

python3 scripts/mcp/acceptance.py \
  --gui /path/to/owned-qa/space-sniffer-gpui \
  --backend /path/to/MacScanBridge \
  --output /new/mcp-evidence

uv run --no-project --with 'mcp==2.3.0' python scripts/mcp/check_sdk.py \
  --gui /path/to/owned-qa/space-sniffer-gpui \
  --backend /path/to/MacScanBridge \
  --output /new/sdk-evidence
```

For Windows acceptance, pass a QA-enabled EXE and `ExplorerBackend.exe` beside its
matching Swift DLLs. The runner copies them to its own temporary directory. Run in
the interactive user's session; it does not use mouse or keyboard input. Embedded
Python distributions may need the script directory added to `sys.path` explicitly.

The GUI fixtures use the validated **184B backends**. The separately rebuilt legacy
CLI uses current source, including the unadopted scan-engine candidate; its results
establish CLI correctness only. No engine change was installed or adopted.

## Cleanup and remaining work

Mac GUI/MCP processes exited 0, fixtures were removed and no owned native process
remained. The Windows accepted suite reported the same, with its production app
still present at the last connected check. Mac build caches created for this run
were removed after preserving the tested binaries and logs.

Windows became unreachable while collecting its final artifacts. Bounded connection
retries and one wake packet did not restore SSH. The last task state was **Ready**,
not running, but final removal was not confirmed. At the next connection:

- Retrieve `~/spacer-cli-mcp-20261124` results/logs and verify the recorded hashes.
- Remove only the owned `Spacer-MCP-Acceptance-20261124` scheduled task from its
  registration context; its in-task cleanup did not remove the entry.
- Check/remove the earlier failed harness directory
  `%TEMP%\spacer-mcp-owned-dfp7m13e` after confirming no process uses it.
- Finish the Windows cancellation proof. Do not substitute an idle stop or a scan
  that completed before cancellation was observed.
- Repackage/retest these fixes before updating installed apps. Existing 0.3.0
  bundles still contain the previous UI/MCP files.
- Finish strict validation of GUI startup arguments together with the missing
  packaged headless interface. Only help/version and explicit `--cli` rejection
  were added here; the GUI argument loop is not a full CLI parser.

Private evidence is retained outside Git under
`~/Downloads/Spacer-CLI-MCP-Validation-20261124/`; old failed attempts remain intact.
