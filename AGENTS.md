# Spacer — current handoff

The project/repository and installed app are **Spacer** (`aidoinnov/Spacer`).
Current installed release: **0.3.1**, optimized production GPUI/CLI with the pinned
184B native engines. Read `docs/SPACER_0_3_1_INSTALL.md` and `docs/WORK_HANDOFF.md`.

- Mac: `~/Applications/Spacer.app` (`Contents/MacOS/Spacer`).
- Windows 132: `%LOCALAPPDATA%\Programs\Spacer\0.3.1\Spacer.exe`.
- `gpui-app/product.json` owns release display metadata. Cargo versions and the
  generated Windows resource must agree. Package composition validates versions.
- Packaged MCP resources on Mac must remain read-only (0555); launch Python
  bridges with `-B`. Verify the app signature after real MCP use as well as before.
  Never let `__pycache__` modify sealed bundle resources.
- The legacy bundle ID, controller namespace and settings/recovery locations
  deliberately remain compatible. Do not rename user data along with the UI.
- The user explicitly authorized the 0.3.1 rename/install and removal of old test
  apps on 2026-11-25. Old executable bundles were archived with byte verification
  before removal. Preserve the new running installed apps and recovery data.
- Frozen November 24 release archives remain historical; do not rewrite hashes.

Latest CLI/MCP audit: `docs/CLI_MCP_FOLLOWUP.md` (2026-11-25).
New source builds include `SpacerCLI` / `SpacerCLI.exe`, using canonical GPUI
transport/document/model code. GUI `--cli` forwards before window initialization.
See `docs/HEADLESS_CLI.md` for normalized output and legacy compatibility limits.
The process/path adapters are shared by both hosts; `session_lifecycle` owns the
normal-exit native/scratch cleanup barrier. GPUI only polls quit futures for
200 ms, so do not move required cleanup into a detached reader or an unawaited
quit future. Preserve the shared grace budget and exact owned-child handles.
The November 25 CLI/MCP audit used separate dev-profile Mac and release-profile
Windows builds. The subsequent installed 0.3.1 packages use optimized release
builds on both platforms. Their installation/identity checks are recorded
separately; neither record admits the unadopted 168B engine candidate.

- Product UI is common Rust/GPUI for Mac and Windows. Keep OS branches in
  platform adapters/native ports; preserve the existing shared scan engine.
- The current 0.3.1 installation retains the 2026-11-24 **184B**
  engine. The working tree also contains an **unadopted 168B candidate**.
  A normal rebuild can include that candidate: never label it the validated
  release or install it without its separate performance acceptance.
- Use the current release manifests and the pinned backend hashes recorded in
  the handoff. Do not silently rebuild, replace installed apps, or
  modify earlier frozen evidence deliveries.
- Formal speed acceptance and historical eight-second exit-delay root cause
  are deferred by the user because other projects occupy the host. They are
  not passed/resolved. Do not interrupt other projects or keep retrying until
  an admission sample happens to pass.
- Preserve the user's running preview, analysis/recovery data and rollback
  archives. Cleanup must identify owned QA processes by executable path and
  creation identity, not by broad process-name matches.
- Check resource release in success/error/cancel paths. Close process/file/
  pipe/observer handles, reap owned children, and always resume leased VM
  pauses. Do not steal mouse/keyboard focus for further QA by default.
- New installer runtime checks and public signing requirements must be
  reported separately from the already-validated application behavior.
