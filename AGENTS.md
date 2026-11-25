# Spacer — current handoff

The project/repository and installed app are **Spacer** (`aidoinnov/Spacer`).
Current installed release: **0.3.2**, optimized production GPUI/CLI with rebuilt
184B native engines. Read `docs/SPACER_0_3_2_INSTALL.md` and `docs/WORK_HANDOFF.md`.

- Mac: `~/Applications/Spacer.app` (`Contents/MacOS/Spacer`).
- Windows 132: `%LOCALAPPDATA%\Programs\Spacer\0.3.2\Spacer.exe`.
- `gpui-app/product.json` owns release display metadata. Cargo versions and the
  generated Windows resource must agree. Package composition validates versions.
- Packaged MCP resources on Mac must remain read-only (0555); launch Python
  bridges with `-B`. Verify the app signature after real MCP use as well as before.
  Never let `__pycache__` modify sealed bundle resources.
- The legacy bundle ID, controller namespace and settings/recovery locations
  deliberately remain compatible. Do not rename user data along with the UI.
- The user authorized the 0.3.2 follow-up deployment on 2026-11-25. Both installed
  apps passed actual CLI/MCP/navigation/capture checks. Keep their current processes
  and document services running; old managed copies and owned QA tasks are removed.
- The user explicitly authorized the 0.3.1 rename/install and removal of old test
  apps on 2026-11-25. Old executable bundles were archived with byte verification
  before removal. Preserve the new running installed apps and recovery data.
- Frozen November 24 release archives remain historical; do not rewrite hashes.

Latest CLI/MCP audit: `docs/CLI_MCP_FOLLOWUP.md` (2026-11-25).
Progress overview follow-up: `docs/PROGRESS_OVERVIEW_CONSISTENCY_RESULTS.md` and
`docs/PROGRESS_OVERVIEW_CONSISTENCY_TODO.md`. The fix is installed in **0.3.2**
with the retained 184B layout; earlier 168B candidate evidence is historical.
Keep overview heartbeat updates separate from full snapshot publication throttling.
Native adapters share `ScanOverviewPolicy`; Rust ranks bounded candidates for the
selected size mode and validates overview v1 before rendering. Preserve old wire
compatibility and never mix global large-file rankings into folder totals.
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
- The current 0.3.2 installation retains the 2026-11-24 **184B**
  engine. Source defaults were restored to this 184B layout for the 0.3.2 fix.
  The **unadopted 168B candidate** is preserved as
  `docs/pending/node-storage-168.patch`; it is no longer in the normal build.
  Reapplying it requires separate performance acceptance and refreshing the
  canonical shared-source manifest. Do not describe old 168B probe evidence as
  the newly rebuilt 184B release evidence.
- Use the current release manifests and the pinned backend hashes recorded in
  the handoff. Do not silently rebuild, replace installed apps, or
  modify earlier frozen evidence deliveries.
- Rebuilt-engine installer composition requires `--engine-evidence`: exact
  backend hashes, retained model-source hashes and both runtime layout logs.
  Without that argument the packager still accepts only the frozen 0.3.1 hashes.
- `product.json` supplies the default runtime controller namespace as well as
  display metadata. Preserve explicit QA namespace overrides. Use production
  `--background` for non-activating installed checks; do not steal user focus.
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
