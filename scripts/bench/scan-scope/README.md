# V00 scope validation

Create only owned sparse HFS+ images and mount them inside a unique private
fixture, never under user data. At least2 GiB free backing space is required.
The initial input has100 local files and6000 files on two nested image volumes.
Use a new manifest/output path. Keep images mounted until all tests, measurement
and app validation finish, then clean up in reverse order.

```sh
python3 scripts/bench/scan-scope/fixture.py create --manifest /private/tmp/scope-fixture.json
SNIFFER_SCOPE_MANIFEST=/private/tmp/scope-fixture.json \
  swift test --scratch-path /private/tmp/sniffer-progressive-build --jobs 2
```

Ordinary unit runs skip the three explicit native image tests rather than
creating mounts. The supplied environment runs them against the owned fixture.
Other unit tests check System/Data policy against the actual host mount table,
mode/cache lifetime, scope merge, bounded provenance and old JSON/SNS handling.

Freeze Core sources/profile before release compilation; never build a baseline
from files being edited. V3 benchmark:

```sh
swiftc -O -whole-module-optimization \
  docs/validation/scan-scope-2026-11-19/candidate-v3/core/*.swift \
  docs/validation/scan-scope-2026-11-19/candidate-v3/profile.swift \
  -o /private/tmp/sniffer-scope-v3-profile
python3 scripts/bench/scan-scope/compare.py \
  --fixture /private/tmp/scope-fixture.json \
  --before /private/tmp/sniffer-automatic-v4 \
  --after /private/tmp/sniffer-scope-v3-profile \
  --output /private/tmp/scope-UNIQUE.json --pairs 100
python3 scripts/bench/scan-scope/report.py \
  --raw /private/tmp/scope-UNIQUE.json --output /private/tmp/scope-scorecard.md
python3 scripts/bench/scan-scope/test_report.py
```

Baseline is V02 V4's immutable release profile, whose automatic backend scans
across mounts. New `all` scans the same input; new `automatic` selects one volume.
The separate control10000 fixture contains no nested mount. Cyclically rotate
three variants for every pair, retain all attempts and compare exact counts,
logical sizes and same-scope field digests. Process starts do not imply cold
filesystem cache. Run final timings after controlled compilation/TSAN jobs end.
The user can still be active on this shared host; do not stop unrelated jobs.
Stat/bulk API counts exclude other setup metadata calls and are not literal
kernel syscall counts. No OS cache purge or user Spotlight reindex is needed.

Reporter recomputes gates from rows, rejecting failed/missing/duplicate pairs,
wrong counts/mode/provenance and non-finite samples. Selected-vs-all reduction
is explicitly different scope, not a same-scope engine speedup. V2 raw failures
are retained. V3's100-pair plan was fixed before collection; do not repeat an
unchanged candidate until it passes. Its optional all-volume control p95 remains
HOLD. The default selected-volume control and same-scope mounted-input all mode
passed. This does not supersede V02's earlier standalone/composed decisions.

V4 only tightens count/fill inventory saturation handling: a completely
full getfsstat buffer is conservatively incomplete. This follows the SDK man
page's filled-record count. Measured V3 fixtures did not saturate buffers; timing
artifacts remain labelled V3. V5 suppresses SpaceAccounting for allVolumes,
which is outside the standalone scanner timing path. Final native/full tests and actual app checks are
separate evidence, not a claim that their binary hash equals V3's.

TSAN uses the same disposable xctest host documented for scan-retry when macOS
rejects sanitizer injection into SwiftPM's platform-signed discovery helper.
Retain both the pre-test loader failure and the actual17-test TSAN log. This
changes no Xcode/system security settings.

`verify_app.py --proof PROOF_DIR` tests the explicitly packaged PID from its
packaging manifest using the app-bundled public MCP bridge. It checks default,
opt-in all volumes, real cross-volume watch, return to selected mode, local
watch, capacity preservation and cache counts, and saves bounded forced window
captures. It creates two7-byte files in the owned fixture; run this **after**
measurement. Disable Python bytecode writes so the signed bundle is unchanged.

```sh
python3 scripts/bench/scan-scope/fixture.py cleanup --manifest /private/tmp/scope-fixture.json
```

Before deleting fixture files, cleanup resolves the currently attached owned
image through `hdiutil info`; it does not blindly detach a possibly reused disk
number. A detach failure preserves the fixture for recovery. On setup failure,
attachments are recorded before the attach operation so rollback can find an
image even if mount parsing failed. The candidate test process must be stopped
before unmounting its fixture. Leave the user's existing process untouched.
