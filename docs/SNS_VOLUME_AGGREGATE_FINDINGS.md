# SNS drive wire fields와 폴더 합계의 정적 근거

production SNS 코드는 이번 조사에서 수정하지 않았다. 원본은 SpaceSniffer 2.2.0.27 x64, SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`다. [보존 dossier 19개와 bundle](validation/r-backlog-2026-11-09/r07-sns-aggregate/)은 Ghidra 12.1.4 정적 결과이며 Windows 실제 import/export 실행이 아니다.

## 확정한 좁은 계약

`exportHardCoded` [0x408a80](validation/r-backlog-2026-11-09/r07-sns-aggregate/functions/0x408a80.txt), Evidence `ev_4a67985a661fd873e79768bc504ad8243dbf9669847d1458638ba77c57b66a1e`:

- 일반 record는 FS node +0x30/+0x38의 두 값을 쓴다.
- drive 판정 vtable+0x60이 참이면 첫 값을 `getDriveSize()`로 바꾸고 두 번째 값에도 같은 값을 쓴다. 즉 live drive의 wire 두 byte 필드는 scanned logical/allocated 합계가 아니라 capacity다.
- free/unknown record는 별도 branch다. 이번 최소 수정안에 이 branch를 포함하지 않는다.
- writer에는 예외 cleanup 뒤 bad-instruction/type-propagation 경고가 있다. 정상 drive branch의 실제 assembly와 fwrite는 dossier에 함께 남겼다.

`getDriveSize` [0x404790](validation/r-backlog-2026-11-09/r07-sns-aggregate/functions/0x404790.txt), Evidence `ev_82262712fd3154e5ec9e5bb9848128da5ae6c3d467407f24a6147da0ed5a4450`: realtime이면 RootData의 drive size를 읽고, 그렇지 않으면 node의 virtual logical size를 읽는다. 따라서 offline/imported record에 호스트의 다른 live volume metadata를 추측해서 넣을 근거가 없다.

## 폴더 reset 추적 결과

[internal import 0x4093c0](validation/r-backlog-2026-11-09/r07-sns-aggregate/functions/0x4093c0.txt) (`ev_3358c9efa5bf394c106c05335bcc6796ece3be2a124f94c47475274ac370c58c`)는 이름 다음 두 값을 +0x30/+0x38에 직접 읽는다. v1~3의 두 번째 값은 첫 값+signed Int32 delta, v4는 Int64다. 폴더/drive 구분 없이 읽으며 여기에는 0 초기화가 없다.

[import 0x408ef0](validation/r-backlog-2026-11-09/r07-sns-aggregate/functions/0x408ef0.txt) (`ev_178b24de5f8ddf1b544e433f171c2d6e4c5eb5935ee2548d7df2b0661217dec1`)는 file(type2)와 missing(type6)에만 `bVar1=true`를 설정하고 import 뒤 부모와 모든 조상 +0x30/+0x38에 크기를 더한다. drive/folder/free/unknown에는 이 누적 branch가 없다. 새 노드 constructor/init의 zero는 **wire 필드를 읽기 전**이므로 이 덧셈을 상쇄하는 reset으로 볼 수 없다.

[SNS agent 0x4576f0](validation/r-backlog-2026-11-09/r07-sns-aggregate/functions/0x4576f0.txt) (`ev_80c109f2be41ce208fc6beebd5562470dd8bf425f50abcf360e9d0179a44d3ee`)는 node import 뒤 자기 vtable+0x20으로 재귀한다. ctor가 지정한 vtable 0x923890의 48 bytes를 REA로 읽었고 +0x20 값은 **0x4576f0 자체**였다 (`ev_aeb094a33f4cb98ce00d3e805a68cd30511c4655d7f02c8a5ffca329da0f5ef4`). inherited TBaseSnifAgent나 FS snifChildren wrapper가 중간에서 reset한다는 설명은 성립하지 않는다.

추가로 nodeAdded 0x458f90 → RootData.fireNodeAdded 0x43e730 → 알려진 view.nodeAdded 0x42dc90 → TM.nodeOperation 0x46af20 → folder.createTreeMapNode 0x40a510 → folder TM.newNode 0x465b30 → TM.init 0x4662d0를 추적했다. RootData는 observer virtual callback을 순회한다. 알려진 TM.init은 container의 **TM 합계**를 0으로 초기화하며 FS node의 wire 합계를 0으로 쓰는 동작은 보이지 않는다. TM의 0과 FS field의 0을 혼동하지 않는다.

이 범위에서는 **FS 폴더 합계를 자식 읽기 전에 reset하는 근거를 찾지 못했다**. 원문만 단순 모델링하면 recorded folder/drive 값에 file/missing descendant가 추가되는 양상이지만, 이를 올바른 최종 계약이나 Windows에서 실제로 중복 합계가 발생하는 확정 결함으로 일반화하지 않는다. RootData에 등록될 수 있는 모든 observer/runtime 흐름을 닫지 않았고 Windows 실행은 없다. Mac에서 이런 덧셈을 임의 재현하거나 모든 folder를 0부터 재집계하는 변경은 제안하지 않는다.

## 최소 수정안과 독립 테스트

root와 합의한 writer 조건은 `snapshot.isVolumeRoot && root == 0 && snapshot.volumeTotal > 0`인 **해당 root drive record만** 두 byte 필드를 `volumeTotal`로 쓰는 것이다. type3 folder, subtree, unknown-capacity, 원래 scope 밖 explicit offline type1은 기록된 필드를 유지한다. 이미 nativeType이 정해진 경우 type 판정을 유지하며 type3를 drive로 승격하지 않는다. decoder는 stored drive/folder raw fields와 volumeTotal metadata를 보존하고 node table을 재집계하지 않는다. 기존 Filter.weights의 leaf 집계가 물리적 관측량을 별도로 산출한다.

[새 테스트](../Tests/SpaceSnifferCoreTests/SNSVolumeWireContractTests.swift)는 encode의 oracle로 decode를 사용하지 않고 v4 header의 독립 little-endian offset을 읽는다. logical100/allocated4096, volumeTotal10000 fixture에서 drive wire가 10000/10000, readback raw도10000, allocated leaf weight는4096임을 구별한다. type3/unknown-capacity/offline/subtree 보존 조건과 독립 수작업 wire 입력의 decoder preservation을 검사한다.

부모의 release build와 측정이 진행 중이므로 요청에 따라 **Swift build/test는 실행하지 않았다**. writer 수정 전 첫 테스트는 현재 불일치를 드러내는 회귀 명세이며 PASS로 기록하지 않는다. root가 최소 writer 수정을 검토·반영한 뒤 `swift test --filter SNSVolumeWireContractTests`로 실행해야 한다. 이 테스트의 PASS도 Windows runtime roundtrip의 증거로 사용하지 않는다.
