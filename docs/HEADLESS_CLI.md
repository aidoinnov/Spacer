# Headless CLI

Spacer 0.3.1 and new source builds include a console companion named `SpacerCLI` on macOS and
`SpacerCLI.exe` on Windows. The GPUI executable forwards `--cli` commands to that
companion before initializing a window. Frozen 0.3.0 downloads from November 24
predate this addition; they have not been replaced.

The console host uses the GUI's native transport, document implementation,
filter grammar and output writer. It does not run a second directory walker.
Backend discovery and path normalization live in the shared platform adapters.

## Run

```sh
# macOS bundle, with paths containing spaces quoted
APP="$HOME/Applications/Spacer.app/Contents/MacOS"
"$APP/SpacerCLI" --scan "$HOME/Downloads" --issues
"$APP/Spacer" --cli --scan "$HOME/Downloads" --filter '*.zip' --logical

# Save a new SNS snapshot, then export its paths without scanning the filesystem
"$APP/SpacerCLI" --scan "$HOME/Downloads" --output downloads.sns
"$APP/SpacerCLI" --load downloads.sns --output files.txt
"$APP/SpacerCLI" --load downloads.sns --list-roots
```

On Windows, run `SpacerCLI.exe` directly from PowerShell to obtain ordinary
console output and `$LASTEXITCODE`:

```powershell
.\SpacerCLI.exe --scan "$env:USERPROFILE\Downloads" --issues
.\SpacerCLI.exe --load .\downloads.sns --filter '*.zip' --logical
```

`--cli` is optional when invoking the console companion directly. Use `--help`
for the full option list. The GPUI host exposes it through `--cli --help`.
`SNIFFER_SCAN_BACKEND` can select a native backend for development; packaged
builds discover the backend beside the executable.

## Output and errors

A completed scan or load prints one UTF-8 JSON object. Its fields include
`root`, `files`, `folders`, `logicalBytes`, `allocatedBytes`, `matchedBytes`,
`issues`, `cancelled`, `volume_traversal` and `excluded_boundary_count`.
`--issues` adds retained issue details. Counts describe the input; `matchedBytes`
describes the current filter and size mode. Filesystem allocation and volume
used space measure different things.

| Exit code | Meaning |
|---|---|
| 0 | Completed successfully |
| 1 | Invalid arguments, input, backend or export failure |
| 2 | Scan completed with filesystem issues |
| 130 | Cancelled |

Errors go to stderr. TXT, SNS and configured reports refuse to replace an
existing destination, including the loaded input file. A failed streamed export
removes its staging file. Ctrl+C cancels the console host; the GPUI forwarding
path keeps a private stdin lease so that terminating the forwarder cancels its
console child as well. The native child is shut down and reaped before the CLI
returns. `--parent-stdio` is internal and is not needed for terminal use.

## Documents and export templates

SNS and DU imports use the same native document protocol as the GUI. Use
`--legacy-code-page N` when an import requires an explicit legacy encoding, and
`--snapshot-root-index N` for a multi-root document. `--list-roots` inspects the
available roots without exporting them.

```sh
SpacerCLI --inspect-config format.xml
SpacerCLI --load downloads.sns --export-config format.xml \
  --export-config-index 0 --output report.txt --max-output-bytes 1048576
```

Configuration inspection returns `{"exports":[...]}` using native template
metadata. This is intentionally a normalized contract, not the full settings
object returned by the historical Swift reference CLI. Template selection defaults
to index 0. The native protocol currently accepts one configuration code page;
requests specifying different `--config-xml-code-page` and
`--config-legacy-code-page` values are rejected explicitly. Configured exports
require TXT output. These limits should not be described as complete legacy CLI
compatibility.

## Repeatable checks

```sh
python3 scripts/gpui-app/check-cli.py --portable --binary /path/SpacerCLI \
  --output /new/cli-evidence
python3 scripts/gpui-app/check-cli.py --portable --gui \
  --binary /path/Spacer --output /new/forwarding-evidence
python3 scripts/gpui-app/check-cli-lifecycle.py --binary /path/SpacerCLI \
  --backend /path/MacScanBridge --output /new/lifecycle-evidence
```

Use `ExplorerBackend.exe` on Windows. These checks operate on disposable fixtures
and produce JSON results and raw stdout/stderr. They establish functional
behavior, not scan-speed acceptance.
