# V02 ordered metadata checks

`compare.py` creates only its own `/private/tmp/sniffer-bulk-*` tree, restores
its denied-folder permissions and removes the fixture in `finally`. Requires a
non-root user, 2 GiB free reserve, and a new output path. Writes each attempt to
JSON, alternates execution order by cyclic rotation, verifies expected file,
directory, issue and byte totals, then compares normalized field digests.

Freeze all Core sources and `profile.swift` before compilation. Do not edit a
source tree while compiling it. Build flags for both compared scanners are
`-O -whole-module-optimization`. The three variants isolate V02 (same binary
POSIX vs automatic) and combine V01+V02 against the frozen original POSIX binary.

```sh
swiftc -O -whole-module-optimization \
  docs/validation/scan-bulk-2026-11-19/automatic-v4/core/*.swift \
  docs/validation/scan-bulk-2026-11-19/automatic-v4/profile.swift \
  -o /private/tmp/sniffer-automatic-v4
swiftc -O -whole-module-optimization \
  docs/validation/scan-retry-2026-11-19/before/core/*.swift \
  docs/validation/scan-retry-2026-11-19/before/profile.swift \
  -o /private/tmp/sniffer-retry-before-fixed
python3 scripts/bench/scan-bulk/compare.py \
  --binary /private/tmp/sniffer-automatic-v4 --mode automatic \
  --baseline /private/tmp/sniffer-retry-before-fixed \
  --output /private/tmp/sniffer-bulk-UNIQUE.json --pairs 20 \
  --scenarios small1000 normal10000 wide4100 wide100000 \
              overbudget131073 denied20 tinyfolders1000 deep200
python3 scripts/bench/scan-bulk/report.py \
  --raw /private/tmp/sniffer-bulk-UNIQUE.json \
  --output /private/tmp/sniffer-bulk-scorecard.md
python3 scripts/bench/scan-bulk/test_report.py
```

Reporter requires all eight scenarios, 20+ complete unique pairs, matching
digests and no failed attempts. It recomputes metrics and gates from raw rows;
cached summary booleans are not authority. The runner exit status concerns
correctness/cleanup; use the scorecard's `passed` for performance adoption.

V4's initial small1000 cell had a wide CI with passing CPU, so one fixed80-pair
supplement was declared in `v4-small-supplement-plan.json`. Pool all100 pairs
using `report.py --raw comparison-v4-20.json --supplement comparison-v4-small80.json
--output SCORECARD.md`. No further unchanged repeats. Merge rejects changed
binary/mode identities and retains initial failures. The isolated V02 gates
pass; original-app small p95 remains over this collection's stricter10% margin.
The older S01 product plan allows50ms absolute overhead; it was not substituted
after seeing the results to flip this strict candidate decision.

Time is engine completion with an immutable snapshot reader. RSS and CPU are
sampled before checksum/export work. `stat`/`getattrlistbulk` API counts are not
literal kernel syscall counts; process physical bytes use proc_pid_rusage V2.
Fresh processes do not imply cold filesystem cache. Do not run compilers or
other controlled heavy jobs concurrently with the final measurement. A shared
host and existing user app can still add noise. Do not discard slow rows.

Correctness suite compares exact node fields, IDs, parent/child order, TXT and
SNS bytes (only filesystem free-space volatility normalized). Includes native
4095/4096/4097/4100 boundaries, hardlinks, Unicode, flags, resource forks, sparse
files, partial fields, denied access, malformed/unsupported/later batch failure,
cancellation/FD cleanup and rename-between-listings followed by convergence.
An estimated memory budget does not establish a hard allocator limit.

```sh
swift test --scratch-path /private/tmp/sniffer-progressive-build --jobs 2
swift test --sanitize=thread --scratch-path /private/tmp/sniffer-v02-tsan \
  --jobs 2 --filter 'NativeDirectoryMetadataTests|ScanRetryTests|ScanAdmissionTests|ScanSchedulingTests'
```

If the macOS platform-signed SwiftPM discovery helper rejects sanitizer loading
before tests, retain that failure and run the same instrumented XCTest bundle
using the disposable host documented for V01:

```sh
bash scripts/bench/scan-retry/run-tsan-host.sh \
  /private/tmp/sniffer-v02-tsan/arm64-apple-macosx/debug/MacSpaceSnifferPackageTests.xctest \
  'SpaceSnifferCoreTests.NativeDirectoryMetadataTests,SpaceSnifferCoreTests.ScanRetryTests,SpaceSnifferCoreTests.ScanAdmissionTests,SpaceSnifferCoreTests.ScanSchedulingTests'
```

Do not repeat a failed unchanged candidate until it passes. Preserve each
candidate's sources, binary hashes, full raw series and failed gates. V2 tiny
folder regressions caused a 16-entry admission minimum; V3 wide RSS failure
caused exact-count allocation and earlier name-list release in V4. Thresholds
were not relaxed. `build-manifest.json` records V4's plan before collection.
