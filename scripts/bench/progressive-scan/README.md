# Progressive scan measurements

This harness compares the actual release `DiskScanner`, not a substitute `du`
implementation. `posix` is the current app backend, `bulk` the older bounded
candidate, and `stream` the new opt-in batch candidate. Production defaults are
unchanged. A separate Python Darwin `searchfs` probe tests catalog feasibility.

```sh
swiftc -O -whole-module-optimization Sources/SpaceSnifferCore/*.swift \
  scripts/bench/progressive-scan/profile.swift -o /private/tmp/sniffer-progressive-profile
python3 scripts/bench/progressive-scan/test_report.py
python3 scripts/bench/progressive-scan/run.py \
  --binary /private/tmp/sniffer-progressive-profile \
  --output /private/tmp/sniffer-progressive-results-UNIQUE \
  --fixture-parent /private/tmp --pairs 20 --scenarios S01 S03-4095 S03-4096 S03-4097 S03-4100 S04
```

Run from the repository root. Output paths must be new; prior runs are never
overwritten. Fixtures are owned temporary directories removed on normal exit or
Python exceptions; a forced process kill can leave an owned directory to inspect.
Never point cleanup at a user folder. At least 700 MiB free is required for the
small suite and 1 GiB for the large-file fixtures; large fixtures are processed
sequentially. `S02/S03-100000/S05/S06/S07` create 100,000 physical files and may take
minutes to generate on a busy system. No root privileges, user-file deletions,
cache purge, or Spotlight rebuild are used.

For catalog comparison use an **isolated, disposable APFS test volume** as both
`--fixture-parent` and `--catalog-volume`. `searchfs` always visits the entire
volume: a folder on the busy system Data volume is not an isolated catalog
benchmark. The 2026-11-16 experiment used a 2 GiB sparse APFS image in `/private/tmp`,
mounted with `hdiutil attach -nobrowse` and a `.metadata_never_index` marker on that
new test volume. Detach after the run; remove only the image created by the run.
A production volume is read-only to the catalog probe, but may change and cause
explicit `EBUSY` failures or repeated aliases. No automatic infinite restart is allowed.

`report.json` includes every attempted run, independent oracle checks,
publication quality samples, p50/p95, paired median improvement and bootstrap CI.
`summary.md` is the short numeric scorecard. API fields and final aggregate totals
are checked separately; a catalog aggregate match is not full metadata equality.

Important limits:

- The POSIX oracle warms filesystem metadata. These are warm/unknown OS-cache
  runs, even though every scanner starts in a fresh process.
- Callback-ready latency is an engine proxy. It does not measure UI draw,
  projection cost, launch latency, a one-second visible hold, cache restore, or
  FSEvents convergence. GUI gates remain pending.
- RSS and CPU are sampled immediately after scanning, before validation and
  checksum sorting; they include actual retained scan publications.
- `paired_improvement_pct` is the median of per-pair changes, not the percentage
  calculated from the two independent medians. Both are useful but different.
- A shared development machine can have substantial unrelated CPU/I/O load.
  Preserve host context and confidence intervals; do not infer device-independent
  speedup or whole-volume performance from these fixtures.
- Failed, timed-out, inaccurate and changed-fixture runs remain visible. Missing
  measurements are `null`/N/A and never zero. Final adoption remains pending the
  full test plan, regardless of a passing engine checksum.
- Streaming IDs/enumeration order can differ from POSIX. Path-normalized field
  equality does not prove tied treemap ordering or byte-identical SNS/TXT export.
  This is another integration gate before changing the app default.

`--backing-parent` defaults to `/private/tmp`. The runner checks both virtual
fixture free space and its physical backing filesystem before each scenario,
and rechecks a 1 GiB backing reserve every 256 created files. ENOSPC/interruption
preserves completed results and reports an incomplete run. The 2026-11-16 image
run was explicitly stopped when host free space dropped to 1.2 GiB; its completed
pairs were retained and only the owned test image was detached/deleted.

A real isolated APFS field probe is available with:

```sh
python3 scripts/bench/progressive-scan/test_catalog.py /YOUR/DISPOSABLE/APFS/VOLUME
```

On the measured macOS/APFS environment it found that `searchfs` reported symlink
and FIFO entries as regular files. The failed field comparison is retained; a
successful aggregate on regular-file fixtures does not override this evidence.
The production volume probe also detected identical repeated aliases.

Generate the human-readable scorecard from saved reports without re-running I/O:

```sh
python3 scripts/bench/progressive-scan/analyze.py \
  --reports docs/validation/progressive-scan-2026-11-16/exploratory/report.json \
            docs/validation/progressive-scan-2026-11-16/paired-20/report.json \
  --output docs/PROGRESSIVE_SCAN_RESULTS.md
```

Instrumented profiles additionally report scanner API counts and physical
process disk I/O (`proc_pid_rusage` V2). Cached reads may be zero; this does not
mean no metadata was read. `readdir` call counts are not kernel syscall counts.
Supplemental instrumented results from the system volume must stay separate
from image-volume results unless they are explicitly grouped by filesystem and
binary revision. Each series includes its own baseline.

