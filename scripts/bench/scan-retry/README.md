# V01 retry regression and performance checks

Scope: permanent directory-open failures stop immediately; bounded transient
retries and cancellation wakeup. POSIX traversal, sorting, aggregation, scope,
and public scanner API remain the comparison constants.

Capture the **before** Core and `profile.swift` into an immutable directory
before making edits. Never build a baseline from files concurrently being edited.
The first 2026-11-19 baseline attempt violated this and was explicitly discarded;
its failed log and exclusion manifest are retained.

```sh
swiftc -O -whole-module-optimization \
  docs/validation/scan-retry-2026-11-19/before/core/*.swift \
  docs/validation/scan-retry-2026-11-19/before/profile.swift \
  -o /private/tmp/sniffer-retry-before-fixed
swiftc -O -whole-module-optimization \
  Sources/SpaceSnifferCore/*.swift scripts/bench/progressive-scan/profile.swift \
  -o /private/tmp/sniffer-retry-after
python3 scripts/bench/scan-retry/compare.py \
  --before /private/tmp/sniffer-retry-before-fixed \
  --after /private/tmp/sniffer-retry-after \
  --output /private/tmp/sniffer-v01-UNIQUE.json --pairs 20
```

Output must not already exist. The runner requires a non-root UID and 1 GiB
free on the fixture filesystem. It creates only its own temporary tree with
20 denied directories and one readable sibling, plus a separate 10,000-file
normal tree. Permission changes and cleanup affect only those owned fixtures.
Expected counts/issues/byte totals and normalized before/after field digest
must agree. All failed attempts are retained. Timings are release engine-only;
GUI draw or whole-volume speedups are not claimed. Baseline uses the original
POSIX backend and candidate uses POSIX plus V01, never a different traversal scope.

Tests:

```sh
swift test --scratch-path /private/tmp/sniffer-progressive-build --jobs 2
swift test --sanitize=thread --scratch-path /private/tmp/sniffer-v01-tsan \
  --jobs 2 --filter 'ScanRetryTests|ScanAdmissionTests|ScanSchedulingTests'
```

On the measured macOS/Xcode combination, SwiftPM's Apple-signed test discovery
helper rejected sanitizer library insertion before executing any tests. Use the
already instrumented test bundle with the isolated test host if this same error
occurs:

```sh
bash scripts/bench/scan-retry/run-tsan-host.sh \
  /private/tmp/sniffer-v01-tsan/arm64-apple-macosx/debug/MacSpaceSnifferPackageTests.xctest
```

This signs a disposable copy of xctest ad-hoc, specifies the existing Xcode
framework/runtime directories, runs the same TSAN-instrumented test bundle,
and removes the host. It does not modify Xcode, its sanitizer library, system
security settings or the normal app. Preserve both the loader failure and the
actual test logs. A filtered run must execute a non-zero expected test count;
a successful exit without tests does not count as a pass.

The initial isolated host needed the XCTest Swift support library directory in
addition to the TSAN runtime. The first fully loaded run had an 8-second timeout
in the existing 1,000-callback admission stress test under host load. A later
unchanged 20-test run passed, including that stress test, with no race report.
Do not erase the earlier failure when reporting the final result.

Final V2 collection used the fixed initial 20 pairs plus one predeclared 80-pair
expansion per scenario, pooled without changing binaries or dropping outliers.
`report.py` rejects incomplete series or different binary hashes, preserves
failed attempts in gate denominators, and reports the normal-input CI margin.
The final CI still crossed the -10% margin; the original app was not replaced.
The candidate Universal app was built, signed and checked separately, including
both architecture CLI runs and an actual completed-with-issues GUI state.

```sh
python3 scripts/bench/scan-retry/test_report.py
python3 scripts/bench/scan-retry/report.py \
  --reports docs/validation/scan-retry-2026-11-19/comparison-v2-20.json \
            docs/validation/scan-retry-2026-11-19/comparison-v2-supplement80.json \
  --output /private/tmp/sniffer-v01-scorecard.md
```

The generated scorecard omits the manual packaging appendix in the checked-in
Markdown; packaging evidence remains in `packaging.json` and UI state JSON.
