# V03 same-scope comparison

The commands below describe the frozen November19 sources. Current development
Core has an independent shared dependency: use `scripts/bench/scan-platform/build_probe.py`
with an explicit matching profile. Do not compile current Core with only a flat
`swiftc Sources/SpaceSnifferCore/*.swift` command. The old concurrency1 description
below is historical, not the current development or installed default.

The retained `before` and `prototype-v3-fixed` sources are same-module release
engine probes, not GUI builds. The public scanner still uses concurrency1.
Rebuild from retained sources using the same optimization settings:

```sh
swiftc -O -whole-module-optimization \
  docs/validation/scan-parallel-2026-11-19/before/core/*.swift \
  docs/validation/scan-parallel-2026-11-19/before/profile.swift \
  -o /private/tmp/sniffer-parallel-before
swiftc -O -whole-module-optimization \
  docs/validation/scan-parallel-2026-11-19/prototype-v3-fixed/core/*.swift \
  docs/validation/scan-parallel-2026-11-19/prototype-v3-fixed/profile.swift \
  -o /private/tmp/sniffer-parallel-v3
```

The manifest records measured executable hashes; rebuilding is a new artifact,
not a guarantee of byte-identical compiler output. Do not overwrite measured
executables during an active collection.

```sh
python3 scripts/bench/scan-parallel/compare.py \
  --before /private/tmp/sniffer-parallel-before \
  --candidate /private/tmp/sniffer-parallel-v3 \
  --output docs/validation/scan-parallel-2026-11-19/comparison-v3-100.json \
  --pairs 100 --scenarios small1000 normal10000 wide4100 wide100000 \
  overbudget131073 tinyfolders1000 deep200
python3 scripts/bench/scan-parallel/report.py \
  --raw docs/validation/scan-parallel-2026-11-19/comparison-v3-100.json \
  --output docs/SCAN_PARALLEL_RESULTS.md
python3 -m unittest discover -s scripts/bench/scan-parallel -p test_report.py
```

The harness creates and removes only its own temporary fixture. It reserves
2GiB of backing space, rotates variant order, retains every failed or slow run,
and saves each quartet. Do not run heavy builds during timed collection.
Fixtures are processed sequentially. Processes start fresh; filesystem cache is
warm/unknown. Raw summaries are convenient only: report.py recomputes all gates
and exactness from individual attempts and rejects duplicate/missing pairs.

Canonical digest compares path/identity/size/native attributes/mtime, independent
of enumeration order. Native Swift regression tests separately require exact
node IDs, child order, all DiskNode fields, TXT and SNS bytes, cancellation/FD
settlement and bounded simultaneous directory sections. These are different
contracts and neither replaces the other.

V1/V2/V3 exploration files and compile failures remain evidence. The fixed
100-pair plan was written before formal collection. The default application and
the Scope candidate are retained until adoption gates and application checks
justify a separate package.


`compare.py --warmup-pairs N` (default0) retains every warmup separately in
`warmup_rows`; all variants receive the same rotated cycles after fixture setup.
Warmup oracle/digest failure aborts measured collection. The reporter independently
checks warmup completeness and correctness. Never pool warmed and unwarmed runs;
the adoption merge tool rejects warmup collections rather than losing their audit
rows. See the rolling candidate plans and HOLD results in
`docs/validation/continuous-read-ahead-2026-11-21`.
