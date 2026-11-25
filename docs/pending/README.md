# Deferred node storage candidate

`node-storage-168.patch` preserves the unadopted node layout work. Normal source
builds now use the retained 184-byte layout. The patch includes its candidate
layout assertion and applies to the canonical sources; ExplorerDomain uses the
same sources through links/materialized release copies.

To revisit it in an isolated checkout, run `git apply --check` first, then apply
the patch and refresh `scripts/gpui-app/check-shared-domain.py --refresh`.
The previously deferred correctness/performance admission still applies.
Preserve the historical November 24–25 evidence; do not relabel those runs.
