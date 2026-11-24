# SpaceSnifferScanEngine

Independent Swift package for shared scan policies and concurrency. It has no
AppKit, Darwin, WinSDK or parent Core dependency and no macOS platform constraint.
The macOS app already uses this implementation; a Windows native reader is not
implemented or validated yet.

- `DirectoryBatchReader`: statically dispatched folder-level adapter contract.
- `DirectoryEntry<Metadata>` / `DirectoryListing<Metadata>`: immutable typed values;
  an adapter keeps its complete metadata/identity representation, including128-bit
  Windows file IDs. There is no imposed POSIX inode/device representation.
- `DirectoryWorkerPool` / read-only `DirectoryReadTicket`: bounded jobs, cancellation scoped
  to one control, ticket completion after operation and permit cleanup. Only the
  producer module creates/completes tickets. `requestShutdown` is nonblocking;
  coordinator `shutdown` waits for readers AND cancelled result delivery.
  `isTerminated` includes both obligations; native-work counters alone do not.
- `DirectoryReadWindow`: completed results keep a slot until consumed; shared
  refill/dedup loop. Both retained results and inspected plans have limits.
  `maximumPlans` defaults to the future capacity; explicitly budget additional
  duplicate/ineligible plans. Keys identify pending occurrences, not inode/name
  equivalence. The builder must consume, replenish, then wait in that order.
- `DirectoryIOBudget`: explicit adapter-supplied limits. `withPermit` releases on
  Swift errors without a heap token; raw acquire/release must still be paired.
- `DirectoryReadWindowPolicy`: thresholds and unknown-count admission are explicit
  inputs. Windows is not forced to provide macOS's cheap entry-count query.
- `ObservedByteBatch` / `ScanPublication`: shared batching and publication policies.
  Scalar hot paths and typed entries are inlinable across the module boundary.

The adapter owns native calls, names/ordering/namespace validation, error domains,
handle cleanup, filesystem capabilities and fallback. Return a batch only after
native resources settle. Do not run discovery or mutate a tree from worker code.
`configureWorker` configures the unstarted thread and must be nonblocking and must
not call back into the pool. OS QoS is supplied by the macOS composition layer.

Run the independent tests on a Swift host:

```sh
swift test --package-path Packages/SpaceSnifferScanEngine
```

They include opaque Windows-shaped metadata fixtures, not Win32 API integration.
Native Windows builds and NTFS/SMB/reparse/long-path tests remain required. Swift's
[official Windows setup](https://www.swift.org/install/windows/) documents the
Windows toolchain and SDK dependencies.

See [architecture and current limits](../../docs/SCAN_PLATFORM_ARCHITECTURE.md).

See the [red/green quality review](../../docs/SCAN_ENGINE_QUALITY.md).
