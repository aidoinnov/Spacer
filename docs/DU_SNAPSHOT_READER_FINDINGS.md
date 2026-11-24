# .DU 텍스트 snapshot reader의 근거와 구현 범위

원본은 SpaceSniffer 2.2.0.27 x64, SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`다. [REA 원문과 bundle](validation/r-backlog-2026-11-09/r10-du/)은 Ghidra 12.1.4 정적 분석이며 Windows runtime 결과가 아니다. 새 모듈은 [DUSnapshot.swift](../Sources/SpaceSnifferCore/DUSnapshot.swift), 전용 테스트는 [DUSnapshotTests.swift](../Tests/SpaceSnifferCoreTests/DUSnapshotTests.swift)다. parent의 source-ready 허가 뒤 정식 경로에 복사했다. scratch 사본도 dist/r-backlog-du-prototype에 남겼다.

## 확인한 문법

| 위치 | 관측 | Evidence |
|---|---|---|
| ctor0x454320 | `_wfopen` mode의 narrow literal `r`, 이어 `fgetws` | `ev_e4d2715affaf313bd26695d1c391c931eb62ea988357fdcd16634b65350cb98f` |
| accepts0x4546a0 | 이름 길이>3, 마지막3글자를 UpperCase해 `.DU`와 비교 | `ev_33d5648a3d4480fa519b1896325c224c5c4379c3b000cc2c877b05ca300469d9` |
| parser canonical0x4547f0 | Trim한 줄의 첫 delimiter로 크기/경로 분리, dot 제거→atoi64→`<<10` | `ev_5e5050fe671bef819825466a308e010e94978ee427a5dd32b8d53de262db56f3` |
| raw0x741849 | `20 00 2e 00 00 00 00`: separator는 space, 숫자에서 제거하는 문자는 dot | bundle의 read_bytes |
| raw0x7417bb | `5c 00`: 경로 component는 backslash로 나눔 | bundle의 read_bytes |
| raw0x74178d/0x741761 | `.DU\0` / `r\0` | bundle의 read_bytes |

8192 wchar buffer와 fgetws count0x2000이 보인다. parser는 디스크에서 경로를 다시 stat하지 않고 folder node를 생성한다. 파일별 type2 레코드를 읽는 SNS 문법이 아니다. shipped References/Windows에는 du.exe 또는 별도 DU output spec이 없었고, 보존 manual.txt에서도 이 문법의 생산 도구를 확정하지 못했다. 따라서 Sysinternals DU의 CSV/byte columns, Unix du의 tab/escaping, SNF 구조를 이 reader와 동일하다고 가정하지 않았다.

원본 CRT의 텍스트 변환은 생성 Windows의 ACP/locale 영향을 받을 수 있다. prototype은 ASCII bytes를 그대로 읽고 high bytes에는 기존 `WindowsLegacyText.decode`와 명시적 `legacyCodePage`를 요구한다. 파일명으로 ACP/UTF8을 추측하지 않는다. BOM/UTF16 파일 autodetection은 구현하지 않았다.

## missing(type6) 동작

새 최종 folder에는 기록 KiB×1024 크기의 `Files` missing child를 만든다. 부모 folder에 기존 missing child가 있으면 그 기여에서 새 최종 folder의 전체 기록 크기를 차감하고 0 이하는 제거한다. 기존 folder를 다시 기록할 때 현재 aggregate보다 크면 차이만 missing child로 추가한다. 현재 aggregate 이상이 아닌 반복 기록은 합계를 낮추지 않는다. 새 중간 component에는 무조건 기록 크기를 넣지 않는다.

parser dossier assembly에서 0x455363→0x455370은 같은 bytes를 RDX/R8에 넣어 deltaSize0x405a00으로 전달한다. 0x45540c→0x455421은 같은 음수 bytes를 RDX/R8에 넣어 상위 missing에서 차감한다. 즉 이 분기의 logical/physical 크기는 모두 같은 KiB 기반 값이다. 0x455220→0x45522f의 기존 folder 부족분 branch도 두 차이를 전달한다. pseudocode에서 세 번째 인자가 누락된 곳을 단일 크기 필드라고 오해하지 않았다.

## Mac adapter의 명시적 제한

- 원본 synthetic `[SNAPSHOT: file]` host container 대신 drive별 `C:\` root의 `[ScanSnapshot]`을 반환한다. root는 nativeType3 folder이며 volume capacity/isVolumeRoot/fileCount를 추측하지 않는다. drive letter의 case를 보존하며 `c:`와 `C:`도 자동으로 합치지 않는다. multi-drive 입력은 decodeAll 또는 명시적 rootIndex를 요구한다.
- 지원 범위는 Windows drive absolute 경로다. POSIX/drive-relative/UNC, 빈 component, `.`/`..`, `/`, quote escaping은 지원하지 않고 실패한다. UNC/기타 native 빈-component 의미를 임의 구현하지 않았다. folder lookup key는 `[UInt16]`다. Swift `String`의 canonical-equivalence equality로 NFC/NFD 이름이 합쳐지지 않는다. native getChildByName0x4068a0은 UnicodeString::operator== → UnicodeEqual0x6d59a0 → _UStrEqual0x5fd7a0 → _UStrCmp0x5fd700의 unsigned UTF16 비교를 사용한다. parent의 warm REA 결과 `ev_92c22d965689259ba98bd238571eca9edc9c4d715b227436a542ec38ee40fdf2`, `ev_fc22cd6dfbb9762d229b6d6576c2b48b4a5685afcdb4be3926cee2ffe3d87d18`, `ev_3552de2bfd34d3b35ecf806f04110ffd6b3e8c511516488ccf47fd3f3f562f12`와 기존 R11 raw가 근거이며 parent가 별도 bundle로 보존한다.
- 숫자는 unsigned decimal과 비어 있지 않은 dot groups만 허용한다. native atoi64가 허용할 수 있는 부호·junk suffix·빈 그룹을 import 성공으로 바꾸지 않는다. KiB multiplication과 조상 합계 모두 Int64 overflow를 검사한다.
- 빈 중간 줄/잘린 줄/긴 줄/범위 초과는 부분 성공으로 반환하지 않는다. 기본 한도는 input64MiB, records1M, nodes2M, depth256이며 caller가 더 작은 한도를 줄 수 있다.
- 상위 missing보다 새 child 기록이 커져 음수가 되는 모순 입력은 실패한다. native 0이하 제거 경로가 있다고 해서 음수 raw fields·destructor 보정을 추측하지 않았다.
- 같은 folder에 residual이 이미 있는데 다시 부족분을 요구하면 ambiguousResidual로 실패한다. native는 이름이 같은 missing child를 추가할 수 있지만 이를 하나로 합치면 이후 getChildByFlag의 차감 의미를 바꾼다. `Files`라는 실제 하위 folder와 missing 이름이 충돌하는 경우도 실패한다.

이 제한은 안전한 partial reader 계약이다. 임의 텍스트를 추정해 열거나 원본이 읽을 수 있는 모든 DU 파일을 지원한다고 주장하지 않는다. byte grammar와 missing 기여 관계가 확인된 입력에서만 snapshot을 반환한다.

## 독립 fixture와 테스트

[synthetic-parent-first.du](validation/r-backlog-2026-11-09/r10-du/synthetic-parent-first.du)는 literal ASCII bytes `10 C:\parent`, `4 C:\parent\a`, `6 C:\parent\b`와 CRLF로 직접 만든 합성 fixture다. captured Windows 또는 du.exe 생성 파일이 아니다. parent10KiB의 missing이 두 child4/6KiB에 의해 차감·제거되고, 최종 leaf weights10KiB와 folder aggregate가 일치해야 한다.

전용 테스트9개는 parent-first removal, child-first 부족분+낮은 반복, dot grouping/KiB/spaces/root line, multi-drive selection/accepts, CP1252 high bytes, malformed/overflow/unsupported 입력, 명시적 resource limits, exact UTF16 NFC/NFD·A/a·drive-case 분리, pre-cancelled control/task를 다룬다. 숫자 expected값은 고정 상수이며 encoder roundtrip으로 oracle을 만들지 않는다. sibling a/b의 missing 크기는4096/6144, child-first parent12KiB의 추가 missing은2048이다.

현재 상태는 **정식 경로에 source-ready, build/test 미실행**이다. parent의 `.build` 작업과 겹치지 않도록 요청에 따라 Swift 명령을 실행하지 않았다. root가 `swift test --filter DUSnapshotTests`를 실행해야 한다. ArtifactTransfer/Hub/UI dispatch는 이번 소유 범위 밖이며 수정하지 않았다. Windows runtime, 실제 생산 DU fixture, ACP/locale 조합, SNF는 별도 미확인이다.

## 취소와 데이터 구조

optional `ScanControl` 및 `Task.isCancelled`를 decoding 전후, record별, component별, 모든 ancestor delta loop 및 최종 DFS remap에서 확인하고 CancellationError를 던진다. 최종 snapshot은 builder가 parent-before-child IDs, 비음수 합계, 균형 잡힌 child 합계를 구성하며, 별도 uncancellable whole-table Model.validated pass를 reader 안에서 반복하지 않는다. 테스트에서는 독립적으로 Model.validated를 호출한다. Foundation/CF의 단일 text decoding과 줄 split 자체는 중간에 끊지 못하므로 input64MiB 상한이 그 작업의 범위다. pre-cancel 테스트가 임의 시점의 GUI cancellation latency 측정인 것은 아니다. ArtifactTransfer가 이 control을 전달하는 통합은 parent의 별도 작업이다.
