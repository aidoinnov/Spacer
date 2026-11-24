# R11 — Windows configuration and text export reconstruction

Status: independent Core implementation and focused tests; application settings UI, file-class rendering integration and MCP/UI job wiring are owned by the parent task. Explicit CLI and asynchronous artifact integration were subsequently implemented below. No Windows runtime execution was performed. This report separates static binary facts from Mac execution boundaries.

## Target and reproducibility

Target: `References/Windows/2.2.0.27/SpaceSniffer.exe`, SHA256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`. Ghidra 12.1.4, ephemeral source-immutable analysis; the child-owned session was closed after exporting its evidence. Input identities and reused official distribution manual/getConfig evidence are in [reused-inputs.json](validation/r-backlog-2026-11-09/r11/reused-inputs.json). The official manual extraction is [manual-config-export.txt](validation/r-backlog-2026-11-09/r11/manual-config-export.txt).

Complete current session: [rea-evidence-final.json](validation/r-backlog-2026-11-09/r11/rea-evidence-final.json), 52 records. [evidence-index.json](validation/r-backlog-2026-11-09/r11/evidence-index.json) maps operation/parameters to evidence identity and limitations; [functions-final](validation/r-backlog-2026-11-09/r11/functions-final) contains readable pseudocode. Earlier exports and all previous validation raw/reference artifacts remain intact. Ghidra's bundle `unknowns: 0` means no transport-level unknown records; it does not establish complete behavioral coverage.

## Configuration facts and implementation

`getConfig` 0x40c420 reads XML; `getFileName` 0x40e7e0 places `SpaceSnifferConfig.xml` next to the executable. `saveConfig` 0x40f000 writes root `SpaceSnifferConfig` with a UTF-8 XML declaration. NativeConfiguration is a local Data codec, not a singleton or an automatic file writer. It implements recognized scalar keys, defaults, colors, file groups and export configurations. Its public `defaults` is the explicit key/value ledger; UI slider ranges are deliberately separate from parsed values.

Default integer keys: refreshDelayMs=50, zoomTimeMs=5, minElementSizePx=10, proportions=0, initialDetailLevel=3, fontSize=7. Boolean defaults: showFreeSpace=false, showUnknownSpace=false, showFileTooltipDateTime=false, showFileTooltipAge=true, useRealZoom=false, useDynaSmooth=true, useSorting=true, scanADS=false, watchDog=true, logPopup/logWarning/flashElement/flashWindow/keepTooltip=true. initialStyle is `flat`; all other native XML style values select fileClasses. Color integer defaults: drive=0x99ff, folder=0x99ccff, file=0xffcc99, free=0x8000, unknown=0x808080; halo levels=3; levelContrast=10, borderContrast=30; mouseHover/mouseTrail/hilightShadow=true. Colors are native integer values, not inferred web RGB strings.

Boolean parsing is exact lowercase `true`; numeric integer parsing follows signed32/native hex forms. Contrast values are explicitly cast through int before stored as double in getConfig. The native proportions position transform is `position/(position<0 ? 100 : 10)+1`; those constants are confirmed by the byte record at 0x73d368. No arbitrary clamp ranges were derived from these values.

File class constructor 0x40b6a0 reads name/extensions/color (missing defaults `???`, empty string, 0). Its init 0x40b5b0 creates TStringList with delimiter `;`. TStrings constructor 0x67c5d0 and SetDelimitedText 0x67ecb0 establish non-strict whitespace 1...32, quoted tokens, doubled quotes and trailing empty entries. Those parsing rules are implemented rather than using a simple split. Missing fileGroups generates the five native defaults; a present empty group list stays empty. Exact default labels, extension strings and integer colors are in `NativeConfiguration.defaultFileClasses` (including the original repeated m4a).

Export config XML ctor 0x412360 and exporter 0x413870 establish description, preferredFileName, preferredFileExtension, headerFormat/detailFormat/footerFormat, blockSorting, fineSorting, fineSortingDirection. Explicit versions 1...3 are accepted; missing version is legacy version0, whereas explicit version0 is rejected. Version3 scripts are Base64 UTF16LE. Versions0...2 use legacy ANSI bytes; version1 alone converts `<%size%>` and `<%sizebytes%>` to their disksize forms (converter 0x413390). The writer always emits version3. Native sortConfigs 0x40e8c0 sorts nonempty descriptions using exact Unicode ordering within runs; empty descriptions remain barriers, equal descriptions keep order. Custom configurations have no inferred builtin UI flags.

Text code pages are explicit: `WindowsLegacyText.decode` accepts ASCII without a code page and requires a nonzero caller-supplied original Windows code page for non-ASCII legacy bytes. XML text's UnicodeString(char*) → UnicodeFromPChar(false) path is a separate ambiguity from Base64 script ACP; `xmlTextCodePage` is separate from `legacyCodePage`, and neither silently assumes UTF8/1252/the Mac locale. The UTF8 XML serializer emits semantic configuration XML; it does not claim byte-for-byte TinyXML printer formatting or universal legacy-locale roundtrip.

## Export language: observed grammar

The implemented atom/parser/evaluator follows atomizeFormat 0x418fe0, recurse 0x419480, buildExportRow 0x416e60 and resolveTags 0x419aa0. There is no host-language execution. Braces construct nested atoms; empty inner atoms are omitted. A trailing suffix consisting only of whitespace after a closing group is dropped. `{script}` works only as the first non-whitespace marker and removes CRLF pairs and tabs from its remaining source, preserving lone LF. This is not a general whitespace normalizer.

Known commands: `&br`, `&tab`, `&curlyop`, `&curlycl`, `&angleop`, `&anglecl`; `nest{value}`; leftpad/rightpad with three child atoms; `if{lhs}operator{rhs}?{yes}` with optional `:{no}`. Command groups are eagerly evaluated in the native path, including condition branches. Padding length/truncation uses UTF16 code units and decimal prefix parsing; an evaluated empty pad yields the native BAD PAD marker. Generic atom concatenation is an observed fallback, not a guessed unknown language extension. Unrecognized tags yield `*BAD TAG*`, missing known values use the observed VOID/0/false defaults; tag expansion is a single pass.

Supported tags (case-sensitive): file, filename, fileext, path, pathfile; size/sizebytes/disksize/disksizebytes; filecreatedate/filecreatetime/filecreateage, filemodifydate/filemodifytime/filemodifyage, fileaccessdate/fileaccesstime/fileaccessage; isfile/isfolder/iscontainer, containsfiles/containsfolders/containscontainers, nestinglevel; count/localcount/filecount/localfilecount/foldercount/localfoldercount/containercount/localcontainercount.

Equality/inequality are exact UnicodeString/UTF16 equality: `01 == 1` is false and canonically equivalent Unicode sequences need not compare equal. Relational operators first try native ToDouble and then catch conversion errors to compare UnicodeString. Ghidra omitted the catch block from 0x41c0e0's function body and could not decode an isolated instruction there. Raw bytes 0x41c163 and independent [LLVM disassembly](validation/r-backlog-2026-11-09/r11/compare-catch-llvm-disassembly.txt) show begin_catch → UnicodeStringlt/gt → end_catch. [llvm-version.txt](validation/r-backlog-2026-11-09/r11/llvm-version.txt) identifies the local decoder. UnicodeString wrappers lead to `_UStrCmp` 0x5fd700's uint16 comparisons. This corroborates static control flow, not a Windows execution observation.

Native locale-sensitive floating conversion is not fully reproduced. The evaluator accepts an explicit decimal separator for finite numeric inputs; locale grouping, exotic numeric spellings and nonfinite native behavior are not claimed compatible. Nonfinite supported-parser inputs fail explicitly. Unclosed groups are rejected as a Mac safety boundary rather than emulating all native malformed-source fallbacks.

## Corrected report contracts

Two prior assumptions were disproved and current code/tests corrected without modifying the frozen historical LegacyArtifactReference writer:

1. **Native text file records are UTF8/LF.** Export action 0x41c270 opens mode at 0x73dfef as bytes `77 62 2b 00` (`wb+`). buildExportRow maps &br to LF for a file and CRLF for preview. Binary mode prevents CRT translation. The new independent hex goldens include Korean, emoji and actual CRLF inside a filename: filename CRLF stays data while only record separators are LF. No blanket CRLF replacement is used.
2. **Equal sorted children appear in reverse child-array position, not reverse node ID.** exportNode 0x416650 iterates the child array and inserts an incoming child before an existing element when compare<=0. A regression uses children `[2,1,3]` to distinguish these contracts. No sorting preserves the array order. Block sorting files/folders precedes fine size/name ordering; name comparison is exact UTF16.

Native compareTo 0x46b6b0 obtains physical bytes for size sorting. The existing Mac `Report` takes caller-provided view weights; logical-mode sorting remains a documented Mac extension. `ConfiguredReport` defaults to allocated and permits explicit logical mode. It uses native type1 drive,2 file,3 folder where supplied; Mac directory/file fallback applies otherwise.

The manual reverses file and filename descriptions relative to resolveTags: binary `<%file%>` includes the extension, `<%filename%>` removes the final dot suffix, `<%fileext%>` is that suffix. Binary wins. `<%path%>` is the parent node path without appending a separator; a snapshot root has no invented outside parent. Descriptive sizes follow 0x466b80: b/KB/MB/GB/TB, binary shifts, no spaces, one truncated fractional digit only if the *previous shifted integer's* remainder is nonzero. Thus 1025→1.0KB, 1536→1.5KB, 1048577→1MB. No general-purpose SI formatter was substituted.

`ConfiguredReport.write` implements header root-only traversal, resets counters before the detail traversal, then footer root-only traversal that increments the root once again. Consequently header count=1, detail root count=1, footer count=detailCount+1. Root local counts=0; selected child local counts begin1. Returned Statistics describe the detail pass and actual output UTF8 bytes. These quirks follow binary calls; they are not replaced with the manual's intuitive zero-based description.

## Mac ownership, budgets and integration contract

Files: NativeConfiguration.swift handles Data/XML/value models; NativeExportTemplate.swift handles immutable compiled atoms and row evaluation; ConfiguredReport.swift handles filtered traversal/row context/sink output and shares NativeReportOrdering with the fixed simple Report. UI, disk access and task lifecycle are outside these modules. No persistent cache, thread pool or global mutable formatter is introduced.

Configuration XML input is limited to 4MiB, 20,000 elements and depth256. DTD/entity declarations are rejected, XMLParser external resolution is disabled; supplied Data only, no filesystem/network fetching. Template hard ceilings: input1,048,576 UTF16, nesting128, atoms65,536, per-row output8,388,608 UTF16, work33,554,432. Cancellation checks cover parsing, evaluation, membership, traversal and output boundaries. Configured report output has a caller budget (default1GiB), checked before sink append; invalid negative budget fails. Sink writes can precede a later error: the caller must use its existing temporary-file/atomic-commit job adapter for all-or-nothing files.

Membership and requested weights are computed once per configured report, templates compiled once, rows streamed to the caller-owned ArtifactByteSink. Only referenced tag values are constructed; no complete rendered report array is retained. The frozen `now` value is reused across all rows. Immediate child position arrays are held by the iterative traversal stack; worst-case wide/deep trees still require structural working memory and no universal constant-memory claim is made.

Native date/time/age presentation is OS/locale-dependent. `ConfiguredReport.Formatting.time` requires an explicit caller formatter when a physical file date tag is referenced; absent formatter throws `missingFormatter`, nonfile dates yield VOID. This is deliberate unresolved presentation integration rather than invented native locale output. Decimal separator is likewise caller-owned. Parent integration must expose configured XML import/export, choose presentation formatting, map colors/classes into UI intentionally, and pass cancellation/output limits through existing artifact jobs. Core implementation alone does not mark those application flows complete.

Malformed mixed-content XML is not a complete TinyXML clone: XMLParser aggregates character/CDATA text whereas native TUtils first-child text behavior may differ. Valid native-generated scalar XML is the supported path; duplicate fields currently use the last value. Full Windows locale behavior, invalid UTF16 acceptance quirks, builtin export menu flags and dynamic Windows read/write roundtrip are unverified.

## Persistent cache boundary

Within the inspected getConfig recognized-key path there is no autosnapshot/recent-snapshot reload setting. Official CLI save/export/autoclose is explicit output, not proof of automatic persistent cache. This is a bounded negative observation only; DataCache RAM ownership and other entry points are covered by R04, not inferred from this absence.

## Verification

Focused test commands and source hashes are retained in the adjacent validation directory. Config tests cover defaults/missing-vs-empty groups, strict booleans, numeric handling, version migration/code pages, Unicode v3, XML limits/entities and cancellation. Template tests cover observed grammar, exact Unicode/numeric comparisons, padding, script cleanup, preview/file line breaks and bounded execution. Configured-report tests cover reordered-child ties, no-sort/name ordering, native counters/tag semantics/size formatting, caller-owned dates, invalid sorts, output budget and cancellation. Streaming/reference tests verify existing SNS behavior remains compatible with the frozen reference. Root owns final all-suite/package/application integration validation.

## App-facing integration follow-up (2026-11-09)

Implemented the explicit CLI flow and reusable asynchronous artifact APIs after the independent Core handoff. These additions do not apply settings to a running window, overwrite global defaults or alter the default Simple file list route. MCP/UI command wiring remains the parent task's scope.

Public reusable API:

```swift
let inspection = try await worker.inspectConfiguration(
    configurationURL,
    legacyCodePage: originalANSIPage,
    xmlTextCodePage: originalXMLRuntimePage,
    control: jobControl)
let template = try inspection.selectingExport(explicitIndex)
let options = ConfiguredExportOptions(
    configuration: template, filter: filter, mode: .allocated,
    showHidden: true, root: root,
    formatting: MacExportFormatting.localized(), now: frozenNow,
    maximumOutputBytes: 1_073_741_824, control: jobControl)
let statistics = try await worker.exportConfigured(
    frozenSnapshot, options: options, to: destination,
    replaceExisting: false)
```

`ConfigurationFile.inspect(URL|Data, legacyCodePage:xmlTextCodePage:control:)` is the synchronous equivalent. An inspection returns `configuration: NativeConfiguration?` and `exports: [ExportConfiguration]`. Full `SpaceSnifferConfig` XML always requires explicit selection, including when it contains only one export; indexes correspond to the normalized inspected list, including native description sorting. Standalone `exportConfig` defaults to index0. Missing/out-of-range indexes fail before export. Template source remains data and is exposed to callers without executing host code. The file reader uses O_NONBLOCK/O_CLOEXEC, verifies the opened descriptor is a regular file, and reads in bounded chunks with a hard 4MiB+1 detection boundary. FIFO/device/directory inputs are rejected without waiting for a FIFO writer. Explicit file URL paths containing NUL and non-file URLs are rejected. Symlinks to regular files are allowed; no automatic path search or preference loading occurs.

`ArtifactTransfer.exportConfigured` creates an adjacent `ArtifactFileTransaction`, streams through `ArtifactFileSink`, and commits only after rendering succeeds. A specialized I/O wrapper checks cancellation before writes and immediately before atomic publication, including cancellation that arrives during the final buffered flush. Errors, unsupported formatting, limits or cancellation leave an existing destination unchanged and remove owned staging storage. Namespace atomicity does not imply fsync durability. The successful rename is the commit point; a later cancellation cannot undo a committed result. `replaceExisting: false` uses the existing exclusive publication contract. Both async configuration inspection and export run on ArtifactWorker's existing bounded serial I/O executor. A task cancellation handler forwards cancellation into the same ScanControl used by synchronous work; supplying a ScanControl means its lifetime belongs to this job.

`WindowsLegacyText` was extracted into its own Core file for shared SNS/XML decoding ownership. `MacExportFormatting.localized(locale:timeZone:)` captures explicit Foundation locale/time-zone formatters once, protects their shared mutable internals with a lock, and supplies short dates, medium times and numeric relative ages. Its formatters never consult changing defaults per row. Missing timestamps yield VOID. These are intentional Mac presentation choices; they are not asserted byte-compatible with Windows date/age formatting. The configured traversal uses one supplied `now` across all rows. The CLI reuses the same clock for report and summary selection and delays summary-only projection until configured output is finished, avoiding concurrent duplicate selection/weight storage; the later summary pass still costs another filter evaluation.

CLI examples (run the executable built from this source, not an older installed package):

```sh
.build/debug/MacSpaceSniffer --cli --inspect-config /path/SpaceSnifferConfig.xml
.build/debug/MacSpaceSniffer --cli --inspect-config /path/legacy-export.xml --config-legacy-code-page 949 --config-xml-code-page 65001
.build/debug/MacSpaceSniffer --cli --scan /path/folder --export-config /path/export.xml --output /path/report.txt
.build/debug/MacSpaceSniffer --cli --load /path/input.sns --export-config /path/SpaceSnifferConfig.xml --export-config-index 0 --output /path/report.txt --max-output-bytes 10485760
```

The SNS `--legacy-code-page` and configuration `--config-legacy-code-page` are separate inputs. Modern v3 scripts already carry UTF16; non-ASCII ordinary XML text still needs its explicit runtime page. Inspection emits JSON with document kind, index requirement, scripts, sort settings, preferred names/extensions, settings and file classes. `--export-config` requires a TXT output and cannot silently produce SNS or select the first full-config template. Omitted `--export-config` keeps the existing default report path. These new flags are validated before scan/load, including duplicate/missing values, invalid page/index/budget and incompatible inspection/export combinations.

Validation artifacts: [integration](validation/r-backlog-2026-11-09/r11/integration). The real headless smoke script starts the executable only with `--cli`, uses temporary fixtures, never starts an AppKit window and never controls the user's running app. It checks inspection, standalone/full indexed exports, missing-index rejection, output-budget atomic preservation, default-report compatibility, explicit non-ASCII XML code page and invalid SNS destination. Focused native Swift tests additionally exercise streaming atomic failure, cancellation during final flush and queued async export cancellation, regular-file/FIFO boundaries, async worker inspection, frozen Mac formatting, CLI option validation and inspection JSON. Full-suite and packaged-app verification remain root-owned.
