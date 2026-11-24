# disktree adoption probes

These scripts inspect fixed release engine sources. They do not replace the installed app.
`prepare.py` freezes the delivered V9 Core and creates control/phase-only/bulk-first
experimental variants. Compile each with `swiftc -O -whole-module-optimization`.
`measure.py` runs a fixed five-pair exploratory ablation, including instrumentation-off
controls. Phase values are nested wall-time sums, not additive CPU attribution.
The bulk-first experiment omits a namespace contract and is not a product candidate.

The safe name-decoding candidate retains ordered validation. Use the existing
`../scan-parallel/compare.py --before-mode parallel2` to compare against delivered V9
at its actual default concurrency. The default before mode remains `automatic` for
older probes. Freeze both Core trees and binary hashes first. A fixed precision
supplement must be declared before collection; `merge.py` retains every attempt,
rejects changed binary/mode/storage/fixture identities and remaps pair IDs. Recompute
all adoption gates with `../scan-parallel/report.py`, not stored summary flags.

`memory_probe.rs` is a separate example wrapper for pinned disktree Core; its source
is unchanged. macOS SDK `rusage_info_v2` (160 bytes) reports resident/footprint before
and after scanning. The Swift wrapper uses the same SDK API before checksum and
validation. `measure_memory.py` runs 100k and 1M independently written files in owned
`/private/tmp` fixtures, restores no unrelated paths, and cleans up in `finally`.
It enforces a 5 GiB setup reserve. Three pairs are exploratory; they do not establish
whole-volume performance or isolate nodes from runtime/allocator caches.

Keep compilation, correctness tests and timed collection sequential. Preserve failed
attempts. Outputs refuse overwrite. No fixture count or cache assumption should be
silently changed after collection begins.

## Current Core memory wrapper (2026-11-24)

`memory_probe.swift` is the maintained scan-boundary wrapper for current Core.
The older profiles under `docs/validation` are frozen historical evidence; do not
edit them to follow resource-owner changes. Build the maintained wrapper with:

```sh
python3 scripts/bench/scan-platform/build_probe.py \
  --profile scripts/bench/disktree-adoption/memory_probe.swift \
  --output /private/tmp/sniffer-memory-current
```

Use a fresh output path (the builder refuses overwrite). Build `memory_probe.rs`
as a separate Cargo executable depending on the pinned local `disktree-core` path;
keep its package, Cargo.lock, checkout commit and source hashes with the result.
Do not add an example or modify source inside the reference checkout. The 2026-11-24
standalone Cargo package and both compiled-wrapper manifests are retained in the
linked evidence `probe-sources` directory.

After all of your builds and functional checks finish, run the unchanged
`../scan-review/host_preflight.py` first. If it fails, retain the failure and leave
comparative performance on HOLD. Otherwise run `measure_memory.py --swift ...
--swift-name swift-current --swift-mode parallel4 --rust ... --output ...` with a
fresh result path. Keep the 100k/1M inputs, three pairs, reserve and all oracles.
The engine samples memory before validation/checksum; repeated digests compare
Swift repetitions, while both engines must match file/folder/allocated totals.

The first 2026-11-24 run overlapped our own build/functional checks and other work.
Its raw RSS readings are exploratory diagnostics, not a sequential collection or
an adoption benchmark; its timing fields must not be used for speed claims.
