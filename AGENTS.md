# Space Sniffer — current handoff

Read `docs/WORK_HANDOFF.md` before changing or packaging the product. It is the
current completion/deferred-work record; older dated reports are historical.

- Product UI is common Rust/GPUI for Mac and Windows. Keep OS branches in
  platform adapters/native ports; preserve the existing shared scan engine.
- The approved 2026-11-24 packaging baseline is GPUI 0.3.0 with the **184B**
  engine. The working tree also contains an **unadopted 168B candidate**.
  A normal rebuild can include that candidate: never label it the validated
  release or install it without its separate performance acceptance.
- Use the pinned release payloads/manifests recorded in the handoff for the
  current installers. Do not silently rebuild, replace installed apps, or
  modify earlier frozen evidence deliveries.
- Formal speed acceptance and historical eight-second exit-delay root cause
  are deferred by the user because other projects occupy the host. They are
  not passed/resolved. Do not interrupt other projects or keep retrying until
  an admission sample happens to pass.
- Preserve the user's running preview, analysis/recovery data and rollback
  apps. Cleanup must identify owned QA processes by executable path and
  creation identity, not by broad process-name matches.
- Check resource release in success/error/cancel paths. Close process/file/
  pipe/observer handles, reap owned children, and always resume leased VM
  pauses. Do not steal mouse/keyboard focus for further QA by default.
- New installer runtime checks and public signing requirements must be
  reported separately from the already-validated application behavior.
