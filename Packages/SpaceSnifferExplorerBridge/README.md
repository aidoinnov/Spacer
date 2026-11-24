# Shared explorer semantics

GPUI delegates SNS, DU, filtering and simple reports to the original Swift implementations.
This package does not introduce another filesystem scanner or filter grammar.

- `ExplorerDomain` links canonical files in `Sources/SpaceSnifferCore`.
- `ExplorerBackend` composes the existing Windows scanner and the shared domain.
- `ExplorerService` owns source tokens and bounded JSONL artifact/weight transport.
  Its files are linked into the Mac bridge (which uses `SpaceSnifferCore`) and the
  Windows backend (which uses `ExplorerDomain`). A process never mixes the models.
- Code-page conversion lives behind `Platform/LegacyCodePageDecoder.swift`.
- Mac Quick Look is a separate native UI port using the original `QuickLook.swift`.

Symlinks are source ownership, not independent copies. Windows source archives
materialize these links. Run `scripts/gpui-app/check-shared-domain.py` to verify
canonical hashes; `--refresh` records intentional canonical changes.

Commands identify the immutable snapshot version returned by `complete`.
Weights are little-endian UInt64 values. Artifact streams are original SNS or
UTF-8/LF path reports. Data chunks are at most 65,536 decoded bytes; the Rust
client owns adjacent staging, stream length validation, synchronization and
atomic publication. Expired versions and invalid filters fail explicitly.

Windows focus refresh currently scans the whole root. Its hard-link accounting
uses a scan-wide identity set; subtree replacement without that set would risk
double-counting links in other branches. Mac uses the original focused rescan
service. Mac mounted-volume opt-in uses that original service policy. Windows
preview is implemented in the GPUI native companion, with Windows runtime
validation pending; mounted-volume opt-in remains unsupported on Windows.
