2026-11-20 후속: [최종 검증·채택](SCAN_DELIVERY_RESULTS.md). 아래는 V03 초기 후보의 역사적 설계이며 현재는 기본2, demand-started max3 readers,64 sibling 진입·wave 방식이다.

# V03 bounded directory read-ahead candidate

2026-11-19. Experimental only: public scanner still defaults to1. Compare1/2/4
on the same scope and exact tree/export contract before selecting a default.

- One builder owns nodes, IDs, accounting and publications. It consumes directory
  listings in the existing DFS order; reader completion order cannot reorder IDs.
- OrderedDirectoryReader is the sole names-first/bulk/order/fallback policy for
  inline and read-ahead. Workers receive immutable path/control/native-reader
  plans and return immutable listings/statistics or explicit fallback/error.
- DirectoryReadPool has4 lazily started native threads and24 waiting jobs. No
  thread per directory. A per-scan dictionary holds at most concurrency−1 future
  listings. Look-ahead inspects at most concurrency stack entries; no full queue
  sort or scan. Stale count hints can only choose I/O, never skip files.
- Hints come from the same APFS bulk query. Only hinted64..1024-entry directories
  are prefetched. Tiny/huge/unhinted directories remain inline. A small initial
  root may request bulk counts to discover useful branches; deeper tiny folders
  retain the existing admission rule. Other filesystem backends stay inline.
- Each read-ahead collects at most2048 names and128KiB of estimated name storage,
  then at most512KiB of estimated metadata. Overflow closes its cursor, returns
  retryInline and counts the discarded prefix I/O. Actual allocator RSS must be
  measured; estimates do not prove a hard RSS limit.
- ScanAdmission still admits8 whole scan operations. DirectoryIOBudget is a
  separate8-permit unit for active directory sections, including inline work.
  Masters await a prefetch ticket before acquiring a directory permit. A master
  never holds that permit while waiting for child/ticket completion. Reader
  workers use the same budget and release it before signaling completion.
- Scan cancellation uses the same ScanControl. Terminal publication drains any
  accepted private readers before returning; no worker holds a tree reference.
  Existing ScanService generation guards continue to reject replaced root runs.
  Native OS calls remain cooperatively cancellable after they return, not
  forcibly interruptible. Blocked OS cases must be reported as such.
- Pool/ticket/budget mutable state is protected by their own NSCondition. The
  Sendable exceptions document that state; no unchecked wrapper is added to
  tree data. Workers never invoke UI/publication callbacks. While waiting, only
  the builder emits heartbeats with its already accepted counts.

Required checks: exact fields/IDs/children/TXT/SNS; names/metadata failure and
later-batch fallback; budget overflow; cancellation/quiescence/FDs; queue full;
multiple scans and permit maxima; TSAN; static/live convergence; flat/tiny/deep,
normal and branch-skew release performance with retained readers. Preserve all
failed prototypes and keep the Scope candidate package unchanged meanwhile.

Prototype V1 (utility QoS) passed exact fields but regressed wall latency sharply.
V2 uses userInitiated native readers because condition waits cannot identify a
producer for QoS donation; the shared-host exploratory comparison improved the
4-worker median but still failed CPU/tail gates. V3 batches only speculative
reader cancellation checks every64 records; before/after OS calls and the tree
builder retain immediate checks. Queued cancellation is removed by control
identity, without waiting for unrelated gated I/O. All prototypes/raw attempts
are retained; no default change from these5-pair explorations.
