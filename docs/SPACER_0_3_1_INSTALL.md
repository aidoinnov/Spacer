# Spacer 0.3.1 — installed 2026-11-25

Spacer 0.3.1 is installed and running on the Mac and Windows 132. Both use
optimized production builds, the shared GPUI interface, the console companion,
and the previously validated 184B native engines. The unadopted 168B engine was
not included.

| Item | macOS arm64 | Windows x64 |
|---|---|---|
| App | `~/Applications/Spacer.app` | `%LOCALAPPDATA%\Programs\Spacer\0.3.1\Spacer.exe` |
| Executable | `Contents/MacOS/Spacer` | `Spacer.exe` |
| Console | `Contents/MacOS/SpacerCLI` | `SpacerCLI.exe` |
| Version | 0.3.1, bundle build 301 | 0.3.1.0 |
| Display identity | Spacer | Spacer, window title Spacer |
| Installed CLI cases | 27/27 passed | 27/27 passed |
| Installed GUI oracle | 2 files, 50 logical bytes, 0 issues | 2 files, 50 logical bytes, 0 issues |
| Bundled real STDIO MCP | Server `spacer`, 22 tools, actual scan/capture | Server `spacer`, 22 tools, actual scan/capture |
| Installer | DMG mounted, payload verified, installed bytes/signature verified | Installer extracted/verified, installed, uninstalled, then installed to final path |

The Mac app was left displaying `~/Applications`; the Windows app was left
showing its installed Spacer directory. Rendered captures confirmed the Spacer
header and treemap. No mouse or keyboard input automation was used.

## Naming and compatibility

`gpui-app/product.json` is the packaging/build metadata source. The Rust build
asserts agreement with the Cargo version, generates the Windows version resource,
and supplies the shared displayed product name. The GUI and console both report
0.3.1. Packagers reject mismatched version inputs.

The bundle ID `local.macspacesniffer.app`, controller resource namespace, and
existing settings/recovery directories remain compatible. Renaming the visible
app did not move or delete user analysis data. The local Codex MCP configuration
now points to the installed Spacer bridge.

The historical frozen 0.3.0 packager retains its original NSIS template under
`installer-windows-legacy-0.3.0.nsi`. New installers are composed by
`prepare-spacer-installers.py`; they verify the payload manifests and reject a
backend whose SHA-256 differs from the pinned 184B baseline.

## Installation and cleanup

The Windows installer was first installed into an owned smoke directory. An
unknown sentinel file was added, then the uninstaller was run. Managed payload
files were removed and the sentinel remained unchanged. The smoke directory was
cleaned and the same installer installed the final production location. The
Start Menu entry belongs to Spacer 0.3.1. No elevation was required.

Old Mac app bundles were byte-verified into ZIP archives before removal:
**51 old bundles**, including QA, candidate, reference and previous rollback
copies. The pre-upgrade installed 0.3.0 app was archived separately before its
bundle was renamed/replaced. Old Windows GPUI executables and the former managed
UI/launcher were also archived before removal: **41 executable copies** in the
known application/QA locations. Old shortcuts were removed by exact target path.
A further 32 standalone old QA executables/helpers in the owned audit folders
were archived by SHA-256 before removal. Relocation notices accompany affected
older evidence deliveries. The new installed applications were preserved and
confirmed still running.

Archives are under `~/Library/Application Support/Spacer/Legacy App Archives`
on Mac and `%LOCALAPPDATA%\Spacer\Legacy App Archives` on Windows. Existing
recovery documents and other projects' apps/caches were preserved. Historical
release ZIPs and recorded hashes were not rewritten.

## Artifacts and evidence

Local delivery: `~/Downloads/Spacer-0.3.1-20261125/`.

- `Spacer-0.3.1-macos-arm64.dmg` and `.zip`.
- `Spacer-0.3.1-windows-x64-setup.exe` and portable `.zip`.
- Mac/Windows payload manifests and installer extraction/hash verification.
- Installed CLI JSON results, real GUI/MCP scan oracle, captures and cleanup logs.

Mac signing is ad-hoc; Windows is unsigned. These facts do not change the
installation and functional results above. The earlier [CLI/MCP audit](CLI_MCP_FOLLOWUP.md)
records the broader 22-tool and cancellation coverage. No formal throughput
admission or historical exit-delay root-cause conclusion is made by this install.

## MCP cache and post-run signature check

A final post-launch check found that importing the bundled transport created a
`__pycache__` file inside the Mac app and invalidated its sealed resources. The
owned cache was removed and the bundled MCP resource directory made read-only
(mode 0555). The packager now applies that mode before signing. Local MCP client
configuration and QA/SDK launchers also pass Python `-B`.

The running Mac analysis was preserved: the process was not restarted or
cancelled. Actual bundled STDIO MCP communication succeeded afterward without
recreating bytecode, and strict deep signature verification passed again. An
independent official SDK 2.3.0 connection without `-B` also passed against the
read-only bundle with all 22 tools listed and no bytecode created. The
updated DMG/ZIP retain the resource-directory mode. This post-run integrity check
is part of the installation evidence, not just the pre-launch signing check.
