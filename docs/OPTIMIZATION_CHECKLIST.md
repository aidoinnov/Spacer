# 원본 최적화 목록·Mac 적용 체크리스트·누락 감사

2026-11-09 현재 source 재검토. Windows SpaceSniffer 2.2.0.27 x64, EXE SHA256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`. 원본30개 목록은 bounded 조사 결과이며 binary-wide 누락0 증명은 아니다.

[구조화 checklist](optimization-checklist.json)가 현재 assessment/source anchor/remaining check의 기준이다. [독립 R 검토](R_BACKLOG_REVIEW_2026-11-09.md), [R 실행 기록](BACKLOG_EXECUTION_2026-11-09.md)과 연결했다. 이전116/116 최적화 완료 기록과 R01–R15 전체 완료는 별개다. Windows runtime_equivalence_verified는30개 모두 **false**다.

## 체크의 의미와 집계

`[x]`는 대응 코드 존재이며 Windows 동적 동일성·모든 하위 기능/성능 완료가 아니다. 부분 대응은 남은 기법을, 플랫폼 대체는 Mac 실행/값/OS 선택을 구분한다. 후보를 측정 후 미채택한 판단도 실제 구현과 구분한다.

| 분류 | 개수 |
|---|---:|
| 대응 구현 | 8 |
| 부분 대응 | 8 |
| 핵심 미적용 | 5 |
| 플랫폼 대체 | 8 |
| 적용 검토 | 1 |

기존84 source 중 hash 동일65는 기존 bounded 검토를 재사용했고 변경19 경로의 관련 계약을 다시 읽었다. 신규 production16/test24를 포함한 **124개 source hash**를 고정했다. [review metadata](optimization-checklist.json)의 source_review 범위가 기준이며 hash 갱신만으로 runtime 검증을 주장하지 않는다. [갱신 전 문서/JSON](validation/r-backlog-2026-11-09/checklist-review/)도 보존했다.

## 전체 목록

| 현재 대응 | ID | 원본 기법 | Mac 상태 | 현재 코드 근거 |
|---|---|---|---|---|
| [x] | W01 | 루트 데이터·리스너 공유 캐시 | 대응 구현 | [ScanService.swift:80](../Sources/SpaceSnifferCore/ScanService.swift#L80), [ScanService.swift:102](../Sources/SpaceSnifferCore/ScanService.swift#L102) |
| [x] | W02 | 탐색 시 기존 필터 트리 재사용 | 대응 구현 | [ProjectionSession.swift:89](../Sources/SpaceSnifferCore/ProjectionSession.swift#L89), [ScanStore.swift:181](../Sources/MacSpaceSniffer/ScanStore.swift#L181) |
| [ ] | W03 | focus 우선 필터 후 중복 subtree 제외 | 핵심 미적용 | [FilterProjection.swift:11](../Sources/SpaceSnifferCore/FilterProjection.swift#L11), [Filter.swift:275](../Sources/SpaceSnifferCore/Filter.swift#L275) |
| [ ] | W04 | 조상 delta 누적 | 부분 대응 | [Scanner.swift:103](../Sources/SpaceSnifferCore/Scanner.swift#L103), [SnapshotTree.swift:55](../Sources/SpaceSnifferCore/SnapshotTree.swift#L55), [Filter.swift:309](../Sources/SpaceSnifferCore/Filter.swift#L309), [ProjectionDelta.swift:5](../Sources/SpaceSnifferCore/ProjectionDelta.swift#L5) |
| [ ] | W05 | 기존 형제 정렬의 변경 항목 재배치 | 핵심 미적용 | [GeometrySession.swift:72](../Sources/SpaceSnifferCore/GeometrySession.swift#L72), [Treemap.swift:13](../Sources/SpaceSnifferCore/Treemap.swift#L13) |
| [ ] | W06 | 변경 의존성에 따른 재필터 제한 | 부분 대응 | [ScanService.swift:167](../Sources/SpaceSnifferCore/ScanService.swift#L167), [ScanStore.swift:141](../Sources/MacSpaceSniffer/ScanStore.swift#L141), [ScanStore.swift:173](../Sources/MacSpaceSniffer/ScanStore.swift#L173), [AutomationHub.swift:222](../Sources/MacSpaceSniffer/AutomationHub.swift#L222) |
| [x] | W07 | 상속 태그 context의 재귀 전달 | 대응 구현 | [Filter.swift:267](../Sources/SpaceSnifferCore/Filter.swift#L267), [Filter.swift:282](../Sources/SpaceSnifferCore/Filter.swift#L282), [SubtreeQuerySession.swift:136](../Sources/SpaceSnifferAutomation/SubtreeQuerySession.swift#L136) |
| [x] | W08 | 오래된 필터 작업 취소·교체 | 대응 구현 | [LatestWorker.swift:51](../Sources/SpaceSnifferCore/LatestWorker.swift#L51), [ScanStore.swift:192](../Sources/MacSpaceSniffer/ScanStore.swift#L192) |
| [x] | W09 | 변경 요청 중복·조상 packing과 FIFO | 대응 구현 | [RefreshQueue.swift:76](../Sources/SpaceSnifferCore/RefreshQueue.swift#L76), [RefreshQueue.swift:91](../Sources/SpaceSnifferCore/RefreshQueue.swift#L91) |
| [ ] | W10 | repaint 병합·간격 조절·가려진 창 생략 | 플랫폼 대체 | [TreemapView.swift:34](../Sources/MacSpaceSniffer/TreemapView.swift#L34), [TreemapView.swift:151](../Sources/MacSpaceSniffer/TreemapView.swift#L151), [MapWindowLifecycle.swift:12](../Sources/MacSpaceSniffer/MapWindowLifecycle.swift#L12), [TreemapView.swift:54](../Sources/MacSpaceSniffer/TreemapView.swift#L54) |
| [ ] | W11 | layout/paint 분리와 표시 재귀 제한 | 부분 대응 | [TreemapView.swift:186](../Sources/MacSpaceSniffer/TreemapView.swift#L186), [Treemap.swift:93](../Sources/SpaceSnifferCore/Treemap.swift#L93), [GeometrySession.swift:24](../Sources/SpaceSnifferCore/GeometrySession.swift#L24) |
| [x] | W12 | palette 포인터 캐시와 명시적 무효화 | 대응 구현 | [TreemapView.swift:118](../Sources/MacSpaceSniffer/TreemapView.swift#L118), [TreemapView.swift:127](../Sources/MacSpaceSniffer/TreemapView.swift#L127) |
| [ ] | W13 | 문자열 치수 memoization | 부분 대응 | [MapTransition.swift:11](../Sources/MacSpaceSniffer/MapTransition.swift#L11), [TreemapView.swift:139](../Sources/MacSpaceSniffer/TreemapView.swift#L139), [MapTextCache.swift:43](../Sources/MacSpaceSniffer/MapTextCache.swift#L43) |
| [ ] | W14 | 지속 tooltip 객체와 dirty rebuild | 플랫폼 대체 | [MapTooltipRegistry.swift:30](../Sources/MacSpaceSniffer/MapTooltipRegistry.swift#L30), [TreemapView.swift:315](../Sources/MacSpaceSniffer/TreemapView.swift#L315) |
| [ ] | W15 | 노드 재활용 pool과 busy 참조 제외 | 플랫폼 대체 | [NodeTable.swift:8](../Sources/SpaceSnifferCore/NodeTable.swift#L8), [LatestWorker.swift:24](../Sources/SpaceSnifferCore/LatestWorker.swift#L24), [FilterScratch.swift:6](../Sources/SpaceSnifferCore/FilterScratch.swift#L6), [ScratchBudget.swift:19](../Sources/SpaceSnifferCore/ScratchBudget.swift#L19) |
| [ ] | W16 | 상한 있는 스캔 스레드 pool·event 대기 | 플랫폼 대체 | [ScanService.swift:61](../Sources/SpaceSnifferCore/ScanService.swift#L61), [LatestWorker.swift:54](../Sources/SpaceSnifferCore/LatestWorker.swift#L54), [ScanAdmission.swift:23](../Sources/SpaceSnifferCore/ScanAdmission.swift#L23), [ScanService.swift:243](../Sources/SpaceSnifferCore/ScanService.swift#L243), [PathIO.swift:9](../Sources/SpaceSnifferCore/PathIO.swift#L9) |
| [ ] | W17 | OS 디렉터리 열거의 큰 버퍼 경로 | 플랫폼 대체 | [Scanner.swift:41](../Sources/SpaceSnifferCore/Scanner.swift#L41), [NativeDirectoryMetadata.swift:42](../Sources/SpaceSnifferCore/NativeDirectoryMetadata.swift#L42) |
| [ ] | W18 | 경로 segment 저장·필요 시 full path 조합 | 핵심 미적용 | [Model.swift:11](../Sources/SpaceSnifferCore/Model.swift#L11), [Model.swift:12](../Sources/SpaceSnifferCore/Model.swift#L12) |
| [x] | W19 | 파일 stream에 순차 export | 대응 구현 | [SNSSnapshot.swift:67](../Sources/SpaceSnifferCore/SNSSnapshot.swift#L67), [Report.swift:12](../Sources/SpaceSnifferCore/Report.swift#L12), [ArtifactFileTransaction.swift:88](../Sources/SpaceSnifferCore/ArtifactFileTransaction.swift#L88), [ArtifactSelection.swift:5](../Sources/SpaceSnifferCore/ArtifactSelection.swift#L5), [ConfiguredReport.swift:44](../Sources/SpaceSnifferCore/ConfiguredReport.swift#L44), [ConfiguredExportOptions.swift:49](../Sources/SpaceSnifferCore/ConfiguredExportOptions.swift#L49) |
| [ ] | W20 | 확대 bitmap 재사용과 옵션별 재렌더 | 부분 대응 | [TreemapMotion.swift:6](../Sources/SpaceSnifferCore/TreemapMotion.swift#L6), [MapTransition.swift:62](../Sources/MacSpaceSniffer/MapTransition.swift#L62) |
| [ ] | W21 | 기존 filtered TM 노드 보존·차이만 생성/제거 | 부분 대응 | [ProjectionDelta.swift:30](../Sources/SpaceSnifferCore/ProjectionDelta.swift#L30), [ProjectionSession.swift:95](../Sources/SpaceSnifferCore/ProjectionSession.swift#L95) |
| [ ] | W22 | 감시 buffer/event 재사용·batch 직접 변경 | 부분 대응 | [DirectoryMonitor.swift:27](../Sources/SpaceSnifferCore/DirectoryMonitor.swift#L27), [ScanService.swift:195](../Sources/SpaceSnifferCore/ScanService.swift#L195) |
| [ ] | W23 | 열거 metadata 재사용·조건부 추가 size query | 플랫폼 대체 | [NativeDirectoryMetadata.swift:5](../Sources/SpaceSnifferCore/NativeDirectoryMetadata.swift#L5), [Scanner.swift:177](../Sources/SpaceSnifferCore/Scanner.swift#L177) |
| [x] | W24 | 필터 조건 사전 분류·숫자 변환·빠른 조건 판정 | 대응 구현 | [Filter.swift:56](../Sources/SpaceSnifferCore/Filter.swift#L56), [Filter.swift:191](../Sources/SpaceSnifferCore/Filter.swift#L191) |
| [ ] | W25 | 사각형·가시성으로 계층형 hit-test 가지치기 | 핵심 미적용 | [TreemapView.swift:293](../Sources/MacSpaceSniffer/TreemapView.swift#L293), [TreemapView.swift:296](../Sources/MacSpaceSniffer/TreemapView.swift#L296) |
| [ ] | W26 | 동일 FS 노드의 중복 스캔 진입 방지 | 플랫폼 대체 | [ScanService.swift:132](../Sources/SpaceSnifferCore/ScanService.swift#L132), [FocusScanRequests.swift:55](../Sources/SpaceSnifferCore/FocusScanRequests.swift#L55), [FocusScanTarget.swift:8](../Sources/SpaceSnifferCore/FocusScanTarget.swift#L8) |
| [ ] | W27 | 설정 객체 lazy 생성·메모리 재사용 | 적용 검토 | [NativeConfiguration.swift:8](../Sources/SpaceSnifferCore/NativeConfiguration.swift#L8), [NativeExportTemplate.swift:5](../Sources/SpaceSnifferCore/NativeExportTemplate.swift#L5), [ConfigurationFile.swift:8](../Sources/SpaceSnifferCore/ConfigurationFile.swift#L8), [ConfiguredReport.swift:5](../Sources/SpaceSnifferCore/ConfiguredReport.swift#L5) |
| [ ] | W28 | SNS 입력의 record 단위 stream 읽기 | 플랫폼 대체 | [ArtifactTransfer.swift:25](../Sources/SpaceSnifferCore/ArtifactTransfer.swift#L25), [SNSSnapshot.swift:123](../Sources/SpaceSnifferCore/SNSSnapshot.swift#L123), [DUSnapshot.swift:6](../Sources/SpaceSnifferCore/DUSnapshot.swift#L6) |
| [ ] | W29 | 자식 이름 조회의 hint 주변 양방향 검색 | 핵심 미적용 | [SnapshotTree.swift:11](../Sources/SpaceSnifferCore/SnapshotTree.swift#L11), [Queries.swift:27](../Sources/SpaceSnifferAutomation/Queries.swift#L27) |
| [ ] | W30 | 전체 스캔과 별도 focus 재스캔 worker 경로 | 부분 대응 | [FocusScanRequests.swift:17](../Sources/SpaceSnifferCore/FocusScanRequests.swift#L17), [ScanService.swift:132](../Sources/SpaceSnifferCore/ScanService.swift#L132), [ScanStore.swift:219](../Sources/MacSpaceSniffer/ScanStore.swift#L219) |

## 이번에 추가한 누락 10개

W21–W30은 최초20개에서 분리·보강한10개다. 새 번호가 원본의 새 기능10개나 새 구현10개를 뜻하지 않는다. original_evidence의 주소/ID/payload/hash와 최초139+6 records는 그대로 보존했다. R13/R11/DU 보충 bundle은 별도 supplemental_review_evidence로 기록했고 기존145개를 바꾸지 않았다.

## 30개 현재 assessment와 남은 확인

### W01 — 대응 구현: 루트 데이터·리스너 공유 캐시

원본 관측: path segment와 agent GUID로 기존 root를 찾아 listener/refcount를 늘린다. 마지막 참조 해제 때 scan/watch를 정리한다.

근거: [0x43ec60](validation/windows-optimization-functions/0x43ec60.txt), [0x43f230](validation/windows-optimization-functions/0x43f230.txt), [0x4559f0](validation/windows-optimization-functions/0x4559f0.txt), [0x4574e0](validation/windows-optimization-functions/0x4574e0.txt).

현재 Mac: live root Entry와 listener를 공유하고 마지막 unsubscribe에 scan/watch/focus intent를 정리한다. offline SNS/DU는 창별 snapshot이다. 원본 raw path+agent GUID cache와 Mac standardized path 정책은 다르다.

관측 한계: 원본 비교 전에 항상 경로 정규화를 한다거나 자동 영구 캐시가 있다는 결론은 미확인.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] R04의 case/trailing-separator/cache hit·재시작 동작은 실제 Windows 관찰이 필요하다.

관련 회귀 source: [EngineTests.swift:27](../Tests/SpaceSnifferCoreTests/EngineTests.swift#L27). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W02 — 대응 구현: 탐색 시 기존 필터 트리 재사용

원본 관측: setNewFocus는 view+0x798을 바꾸고 DrawTreeMap/zoom을 호출한다. DrawTreeMap→refreshBitmap 경로는 기존 TM node를 배치·paint한다.

근거: [0x428bb0](validation/windows-optimization-functions/0x428bb0.txt), [0x42a750](validation/windows-optimization-functions/0x42a750.txt), [0x4295a0](validation/windows-optimization-functions/0x4295a0.txt).

현재 Mac: ProjectionSession의 같은 판정 재사용과 작은 추적 경로/계층 lookup, ScanStore history lookup, bounded child order cache를 구현. 전체 path dictionary 없이 navigation oracle와 25만 파일 5쌍 측정. 실제 GUI 반복은 별도 acceptance에서 확인한다. R09 identity guard로 같은 path의 교체 노드에 selection/tag를 잘못 승계하지 않게 보강했다.

관측 한계: 원본에 Swift Bool/Int64 배열 캐시가 있다는 의미가 아니며 모든 간접 경로 부재의 증명은 아니다.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.
- [ ] 실제 foreground/Space/창 수명 acceptance 완료 여부는 TODO의 해당 step과 최종 검증 기록을 따름.

관련 회귀 source: [ProjectionSessionTests.swift:40](../Tests/SpaceSnifferCoreTests/ProjectionSessionTests.swift#L40), [ProjectionSessionTests.swift:57](../Tests/SpaceSnifferCoreTests/ProjectionSessionTests.swift#L57). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W03 — 핵심 미적용: focus 우선 필터 후 중복 subtree 제외

원본 관측: ctor가 두 TM 인자를 +0x88/+0x90에 저장한다. Execute는 +0x90 먼저 처리하고 +0x88 처리 시 skip=+0x90을 넘긴다. updateFiltering은 this==skip이면 return한다. tag 재적용 호출은 root(+0x790),focus(+0x798)를 순서대로 전달한다.

근거: [0x4590a0](validation/windows-optimization-functions/0x4590a0.txt), [0x459170](validation/windows-optimization-functions/0x459170.txt), [0x46a490](validation/windows-optimization-functions/0x46a490.txt), [0x42cba0](validation/windows-optimization-functions/0x42cba0.txt), [0x430400](validation/windows-optimization-functions/0x430400.txt).

현재 Mac: production은 full 또는 검증된 sparse delta/reuse 후 navigation을 계산하며 focus-first+skip 중간 publish는 없다. R05에서 270 samples/18cases/5pairs와 COW/frozen/cancel oracle를 평가했으나 large/root/empty 회귀 때문에 후보만 보존하고 미채택했다.

관측 한계: 고정 크기 batch/페이지 알고리즘이나 임의 concurrency 수는 이 근거에 없다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] focus-first UI 부분 publish·전역/지역 합계 표시와 immutable COW 비용을 대표 입력에서 검증한 뒤 재선정한다.

### W04 — 부분 대응: 조상 delta 누적

원본 관측: 파일/트리맵 노드의 +0x30/+0x38에 변화량을 더하고 부모 포인터만 따라 올라간다.

근거: [0x405a00](validation/windows-optimization-functions/0x405a00.txt), [0x405260](validation/windows-optimization-functions/0x405260.txt), [0x4667a0](validation/windows-optimization-functions/0x4667a0.txt).

현재 Mac: COW page proof + opaque baseline/result로 검증한 sparse size/mtime/atime 변경에 leaf 기여 제거/추가와 조상 delta를 적용. flat 배열 COW는 남고 dense/시간/unknown metadata/topology는 full fallback. 원본 모든 mutation handler의 증분 동작 전체 이식은 아니다.

관측 한계: hard-link inode dedup 또는 폴더 메타데이터 기여를 추가하는 근거가 아니다.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.

관련 회귀 source: [ScanProgressTests.swift:16](../Tests/SpaceSnifferCoreTests/ScanProgressTests.swift#L16). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W05 — 핵심 미적용: 기존 형제 정렬의 변경 항목 재배치

원본 관측: 정렬 유지 옵션과 node+0x43 상태가 참이면 변경 자식 IndexOf 후 이웃 크기를 비교하여 TList.Exchange한다. 미정렬 분기는 전체 인접 비교 pass가 있다.

근거: [0x4667a0](validation/windows-optimization-functions/0x4667a0.txt).

현재 Mac: GeometrySession은 같은 source/parent의 sibling order를 bounded cache로 재사용한다. 입력 weights/source가 바뀌면 해당 형제 정렬을 다시 수행하며 변경 child 주변 insertion/reposition은 없다. 모든 호출에서 항상 정렬한다고 표현하지 않는다.

관측 한계: IndexOf와 이동은 선형일 수 있다. O(logN) 업데이트라고 부르지 않는다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] 변경 child 주변 정렬 복구는 별도 미구현. R14 hint/lookup 결과와 report의 reverse child-position 동률을 geometry comparator와 혼동하지 않는다.

### W06 — 부분 대응: 변경 의존성에 따른 재필터 제한

원본 관측: 태그 재적용은 isTagInvolved일 때만 applyFilterTo한다. nodeModified는 포함 결과·재필터 필요 분기와 변경 범위를 사용한다.

근거: [0x430400](validation/windows-optimization-functions/0x430400.txt), [0x42df10](validation/windows-optimization-functions/0x42df10.txt), [0x444870](validation/windows-optimization-functions/0x444870.txt), [0x408300](validation/windows-optimization-functions/0x408300.txt), [0x445400](validation/windows-optimization-functions/0x445400.txt).

현재 Mac: 입력 의존 matrix를 적용: 같은 문자열 parse, tag 비의존 동일 COW nodes의 membership/weights 재사용, metadata/공개 revision 갱신. 시간 조건·filter/mode/hidden/unknown 변경은 full. 원본 모든 dirty/bitmap option bit 동일 이식 주장은 아니다.

관측 한계: R13에서 modifiedAttributes는 tag byte+old/new 문자열 payload이며 high byte는 isIncluded 반환값의 subtree 요청임을 구분했다. filterID는 generation/paint marker이고 skip proof가 아니다. 모든 간접 alias/event/runtime 경로 완전성은 미확인.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.

관련 회귀 source: [EngineTests.swift:44](../Tests/SpaceSnifferCoreTests/EngineTests.swift#L44), [integration_smoke.py:67](../scripts/mcp/integration_smoke.py#L67). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W07 — 대응 구현: 상속 태그 context의 재귀 전달

원본 관측: subtree 시작의 inherited tag를 구하고 updateFiltering 재귀에 ownTag|inheritedMask를 넘긴다.

근거: [0x459170](validation/windows-optimization-functions/0x459170.txt), [0x46a490](validation/windows-optimization-functions/0x46a490.txt), [0x406ad0](validation/windows-optimization-functions/0x406ad0.txt), [0x408670](validation/windows-optimization-functions/0x408670.txt).

현재 Mac: bulk filter의 packed inherited-tag OR context와 R15 subtree cursor frame의 같은 tag mask 전달을 구현했다. offset query의 파일별 ancestor walk는 유지한다. Mac cursor/token/budget은 원본에 없던 플랫폼 확장이다.

관측 한계: 원본의 folder matcher는 부모 재귀가 남는다. 모든 폴더 조건 사전 계산·1byte 배열 자체는 Mac 구현이다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] STDIO notification 선점/disconnect cancellation과 hard deadline은 미지원. subtree frame/step 상한을 전체 query wall-time/RSS 상한으로 확대하지 않는다.

관련 회귀 source: [ResourceOptimizationTests.swift:43](../Tests/SpaceSnifferCoreTests/ResourceOptimizationTests.swift#L43), [SubtreeQueryTests.swift:5](../Tests/SpaceSnifferAutomationTests/SubtreeQueryTests.swift#L5). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W08 — 대응 구현: 오래된 필터 작업 취소·교체

원본 관측: 새 필터 전에 Terminate→WaitFor→해제한다. 재귀/노드 갱신 사이에서 취소 flag와 detached 상태를 확인한다.

근거: [0x42cba0](validation/windows-optimization-functions/0x42cba0.txt), [0x429020](validation/windows-optimization-functions/0x429020.txt), [0x46a490](validation/windows-optimization-functions/0x46a490.txt).

현재 Mac: 오래된 control 취소·최신 대기 작업 교체·오래된 publish 차단 대응.

관측 한계: 원본은 WaitFor를 사용한다. lock-free나 실행1/대기1 mailbox 자체가 원본 기법이라는 근거는 없다.

남은 확인:

- [ ] 큰 sorted 작업 도중 취소 지연을 별도 계측한다. 원본 WaitFor 구현 복제는 아님.

관련 회귀 source: [EngineTests.swift:172](../Tests/SpaceSnifferCoreTests/EngineTests.swift#L172). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W09 — 대응 구현: 변경 요청 중복·조상 packing과 FIFO

원본 관측: TList 뒤에 요청을 추가하고 중첩 전체쌍 비교로 중복/덮이는 하위 요청을 제거한다. 조상 판정은 부모 포인터를 따른다. dequeue는 index0 Get/Delete다.

근거: [0x42e130](validation/windows-optimization-functions/0x42e130.txt), [0x408260](validation/windows-optimization-functions/0x408260.txt), [0x42c9e0](validation/windows-optimization-functions/0x42c9e0.txt).

현재 Mac: packing/FIFO는 기존 배열 oracle과 연산별 대조. B08은 작은 큐 배열/큰 큐 Character radix index와 FIFO 저장소 분리로 비용을 낮춘 Mac 선택. 원본 TList가 trie라는 근거로 보지 않음. 2026-11-09 queue metadata 전후 측정과 실제 FSEvents burst는 REFRESH_QUEUE_VALIDATION.md 참조.

관측 한계: 이 본문은 고속 trie/hash가 아니다. 원본 큐의 점근적 우월성이나 실제 Windows 처리 시간을 주장하지 않는다.

남은 확인:

- [ ] trie/radix는 플랫폼 추가 P01. 원본 큐가 trie라서 가져오는 것으로 표시하지 않는다.

### W10 — 플랫폼 대체: repaint 병합·간격 조절·가려진 창 생략

원본 관측: requestRepaint는 요청 강도를 max로 병합하고 layout dirty를 유지한다. timer는 pending과 visible region 조건을 확인한다. DynaSmooth는 갱신 간격을 조절한다.

근거: [0x429140](validation/windows-optimization-functions/0x429140.txt), [0x42c760](validation/windows-optimization-functions/0x42c760.txt), [0x42cd00](validation/windows-optimization-functions/0x42cd00.txt), [0x42c6a0](validation/windows-optimization-functions/0x42c6a0.txt).

현재 Mac: AppKit visibility/occlusion/miniaturize/window close 경계에서 geometry·timer·중간 presentation을 정리하고 복귀 최신 상태/명시적 capture를 준비한다. 원본 repaint interval/paint scheduler를 그대로 옮긴 것이 아니며 과거 native Space/가림 측정은 FINAL_OPTIMIZATION_VALIDATION.md에 보존했다. 이번 R 실행의 최신 package/native QA와 Windows 비교는 별도다.

관측 한계: DynaSmooth는 위치 보간 자체가 아니다. 실제 Windows 프레임율·모든 refresh interval은 미측정.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.
- [ ] 실제 foreground/Space/창 수명 acceptance 완료 여부는 TODO의 해당 step과 최종 검증 기록을 따름.

### W11 — 부분 대응: layout/paint 분리와 표시 재귀 제한

원본 관측: force-layout flag일 때 setCoords/layout하고 그렇지 않으면 저장된 기하를 paint한다. depth·선택 경로·크기·visible/expanded 상태로 재귀를 제한한다.

근거: [0x4295a0](validation/windows-optimization-functions/0x4295a0.txt), [0x468db0](validation/windows-optimization-functions/0x468db0.txt), [0x469770](validation/windows-optimization-functions/0x469770.txt), [0x468360](validation/windows-optimization-functions/0x468360.txt).

현재 Mac: 원래 Double comparator/rect/selection-path 상세화/양수 면적 참여를 보존한 GeometrySession 정렬·rect 재사용. scope/weights/bounds/depth/selection key 분리, 65536 sort 슬롯/50000 rect tile 예산. 원본 filtered TM 객체·branch 변경 재배치 전체 이식은 아니다.

관측 한계: 모든 작은 양수 항목을 배치 입력에서 버려도 된다는 근거가 아니다.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.
- [ ] 실제 foreground/Space/창 수명 acceptance 완료 여부는 TODO의 해당 step과 최종 검증 기록을 따름.

관련 회귀 source: [ReferenceContractTests.swift:57](../Tests/SpaceSnifferCoreTests/ReferenceContractTests.swift#L57). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W12 — 대응 구현: palette 포인터 캐시와 명시적 무효화

원본 관측: paint는 node+0x50가 null일 때 palette를 얻어 보관한다. resetCache는 포인터를 비우고 자식 재귀, configChanged는 대응 virtual slot을 호출한다.

근거: [0x469770](validation/windows-optimization-functions/0x469770.txt), [0x46bb00](validation/windows-optimization-functions/0x46bb00.txt), [0x427ff0](validation/windows-optimization-functions/0x427ff0.txt).

현재 Mac: 현재 UI 옵션의 key 기반 palette 캐시 대응. 원본 pointer reset 모델과 동일 구조는 아님.

관측 한계: cache pointer가 픽셀 전체 또는 node geometry cache라는 뜻은 아니다.

남은 확인:

- [ ] Windows 전체 theme/config를 화면에 적용하는 flow는 아직 미연결이며 도입 시 palette invalidation key를 확장해야 한다.
- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.

### W13 — 부분 대응: 문자열 치수 memoization

원본 관측: TTextBox.setText는 다른 문자열일 때만 dirty(+0x18)를 켠다. getSize는 dirty/font size/bold 변경 때만 TextExtent하고 저장된 size를 반환한다.

근거: [0x4352c0](validation/windows-optimization-functions/0x4352c0.txt), [0x435340](validation/windows-optimization-functions/0x435340.txt), [0x468db0](validation/windows-optimization-functions/0x468db0.txt), [0x469770](validation/windows-optimization-functions/0x469770.txt).

현재 Mac: 현재 presentation의 title/size/NSString width와 font/style 조합을 MapTextCache에서 재사용. path·정확 UTF8 name·dir/link·bytes·point size에 따라 갱신하며 4096 entry/추정 UTF8 1MiB 제한. 원본 node 문자열 치수 저장 구조 전체를 복제한 것은 아니다.

관측 한계: 검사 key는 관찰된 font size와 bold bit다. 모든 font 속성을 포함한 완전한 key라고 확대하지 않는다.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.
- [ ] 실제 foreground/Space/창 수명 acceptance 완료 여부는 TODO의 해당 step과 최종 검증 기록을 따름.

### W14 — 플랫폼 대체: 지속 tooltip 객체와 dirty rebuild

원본 관측: view+0x7f0의 tooltip 객체를 계속 사용한다. setRows는 rows를 저장하고 +0x40 dirty를 켠다. rebuild는 dirty가 아니면 return한다. Paint는 이 객체를 그린다.

근거: [0x429aa0](validation/windows-optimization-functions/0x429aa0.txt), [0x450420](validation/windows-optimization-functions/0x450420.txt), [0x450590](validation/windows-optimization-functions/0x450590.txt), [0x450b10](validation/windows-optimization-functions/0x450b10.txt), [0x4295a0](validation/windows-optimization-functions/0x4295a0.txt), [0x4274b0](validation/windows-optimization-functions/0x4274b0.txt).

현재 Mac: MapTooltipRegistry로 native 등록 영역 수명을 분리. 같은 presentation은 유지, 움직이는 rect는 재등록하며 live content/current path를 검증한다. AppKit 대체로 원본 TTooltip bitmap/치수 cache 동일 구현이 아니다.

관측 한계: setRows는 같은 rows인지 비교하지 않고 dirty를 켠다. Paint 일부 TextExtent도 남아 있어 모든 측정을 생략한다고 말하지 않는다.

남은 확인:

- [ ] AppKit registry/AX 수명은 기존 native 회귀에서 확인했으나 원본 bitmap/TextExtent cache와 Windows runtime 동등성은 미검증.

관련 회귀 source: [MapTooltipTests.swift:53](../Tests/MacSpaceSnifferTests/MapTooltipTests.swift#L53). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W15 — 플랫폼 대체: 노드 재활용 pool과 busy 참조 제외

원본 관측: FS file node와 TM file node newNode는 recycle can을 먼저 확인한다. 없으면 각각 0x70/200 bytes 객체를 할당한다. pool은 연결 포인터로 보관하며 busy 목록의 객체를 건너뛴다.

근거: [0x404ee0](validation/windows-optimization-functions/0x404ee0.txt), [0x4658e0](validation/windows-optimization-functions/0x4658e0.txt), [0x448380](validation/windows-optimization-functions/0x448380.txt), [0x448450](validation/windows-optimization-functions/0x448450.txt), [0x447fb0](validation/windows-optimization-functions/0x447fb0.txt), [0x448050](validation/windows-optimization-functions/0x448050.txt).

현재 Mac: 값 타입 NodeTable COW를 유지하고 private ancestor context만 owner1MiB/global idle charge4MiB/pressure epoch로 재사용. reader-free page 및 실제 node object pool을 prototype·frozen reader·reset·adapter·RSS/CPU로 비교하고 미채택. 원본 busy-ref node pool 동일 구현이 아니다.

관측 한계: 전역 allocator 전체가 이 pool이라는 의미가 아니며 retained pool 크기/실측 절감량은 미측정.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.

관련 회귀 source: [MemoryLifetimeTests.swift:24](../Tests/SpaceSnifferCoreTests/MemoryLifetimeTests.swift#L24), [FilterScratchTests.swift:30](../Tests/SpaceSnifferCoreTests/FilterScratchTests.swift#L30). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W16 — 플랫폼 대체: 상한 있는 스캔 스레드 pool·event 대기

원본 관측: working count를 maxConcurrency와 비교한다. pooled thread가 있으면 재설정하고 event로 깨운다. 완료 worker는 pooled list로 돌아가고 Execute는 event wait한다.

근거: [0x45a7c0](validation/windows-optimization-functions/0x45a7c0.txt), [0x459e30](validation/windows-optimization-functions/0x459e30.txt), [0x459a00](validation/windows-optimization-functions/0x459a00.txt).

현재 Mac: native ScanAdmission running8/pending64와 별도 metadata/artifact/metrics serial lane. actual waiting thread8개·1000submit·queued capture 해제·stale generation·CPU/query 응답을 확인. Dispatch thread 재사용이며 고정 전용 OS thread8개/모든 volume 처리시간/전체 thread ceiling이 아니다.

관측 한계: 고정 원본 data maxConcurrency의 4 bytes는 01 00 00 00이다. 기본부터 여러 스레드가 병렬 스캔한다고 주장하지 않는다.

남은 확인:

- [ ] Windows 실제 동적 결과/타이밍 및 원본 내부 전체 상태 전이는 별도 R backlog와 coverage boundary에 남음.

관련 회귀 source: [ScanAdmissionTests.swift:40](../Tests/SpaceSnifferCoreTests/ScanAdmissionTests.swift#L40), [ScanSchedulingTests.swift:51](../Tests/SpaceSnifferCoreTests/ScanSchedulingTests.swift#L51). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W17 — 플랫폼 대체: OS 디렉터리 열거의 큰 버퍼 경로

원본 관측: global branch에서 FindFirstFileExW(FindExInfoBasic,...,flags=2)를 호출하고 FindNextFileW로 이어간다. 다른 branch에는 FindFirstFileW가 있다.

근거: [0x455be0](validation/windows-optimization-functions/0x455be0.txt).

현재 Mac: default Scanner는 POSIX opendir/readdir 경로다. R14에서 private fd/64KiB/4096entries·추정4MiB의 all-or-nothing bulk metadata 및 count-hint adaptive 후보를 구현·필드 oracle/오류/취소/5pairs로 평가했다. wide에서 회귀하여 opt-in만 유지하고 기본 활성화하지 않았다.

관측 한계: 실행 중 어느 branch가 선택됐는지나 모든 파일시스템에서 더 빠른지는 미확인.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] APFS 외 동작·root count 비용·실제 분포 end-to-end를 재측정해야 한다. adaptive v2 wide median 약19% 회귀를 해결됐다고 보고하지 않는다.

관련 회귀 source: [NativeDirectoryMetadataTests.swift:5](../Tests/SpaceSnifferCoreTests/NativeDirectoryMetadataTests.swift#L5). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W18 — 핵심 미적용: 경로 segment 저장·필요 시 full path 조합

원본 관측: init은 부모(+0x10)와 segment(+0x20)를 저장한다. getFullPath는 부모를 재귀 호출하고 separator와 현재 segment를 합친다.

근거: [0x405260](validation/windows-optimization-functions/0x405260.txt), [0x4061b0](validation/windows-optimization-functions/0x4061b0.txt).

현재 Mac: parent/name과 함께 전체 path 문자열을 각 node에 저장. R14 actual 709만-node 경로/stride attribution과 lazy/segment 후보 비용을 별도 조사했으나 production path compression은 미도입.

관측 한계: full path 조합 CPU·깊은 경로 비용도 있다. 프로그램 전체에 full path cache가 전혀 없다는 증명은 아니다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] identity/tag/query/SNS/rename/frozen reader 경계와 materialization 비용을 검증해야 한다. 문자열 모델 추정치를 실제 heap attribution으로 주장하지 않는다.

### W19 — 대응 구현: 파일 stream에 순차 export

원본 관측: SNS writer는 FILE*에 필드별 fwrite, 종료 writer는 end bytes를 쓴다. TXT exportNode는 FILE*가 있으면 행을 UTF8로 fprintf하고 별도 string destination이 있으면 거기에 append한다.

근거: [0x408a80](validation/windows-optimization-functions/0x408a80.txt), [0x408a10](validation/windows-optimization-functions/0x408a10.txt), [0x415eb0](validation/windows-optimization-functions/0x415eb0.txt), [0x416650](validation/windows-optimization-functions/0x416650.txt).

현재 Mac: SNS/TXT를 bounded sink와 atomic transaction으로 순차 출력한다. R11 원본 wb+·&br 근거로 TXT UTF8/LF와 reverse child-array-position 동률을 정정했고 CRLF filename data는 보존한다. historical LegacyArtifactReference/40표본 hash는 그 당시 writer 증거이며 원본 newline 증명이 아니다. SNS 및 decode batch autoreleasepool과 bitset validation은 Mac 메모리 최적화이며 전체 tree/정렬/selection은 남는다. configured export는 template·weights를 재사용하고 행별 streaming/cancel/output cap을 적용한다.

관측 한계: 원본에도 행 buffer/정렬 TList/재귀와 string destination 경로가 있다. 전체 O(1) 메모리라고 주장하지 않는다. SNS decompiler warning도 보존한다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] 실제 큰 최종 버전 scan/export의 장시간 peak/reader lifetime 관찰과 Windows locale/파일 왕복이 필요하다.
- [ ] namespace atomicity는 fsync/crash durability 보장이 아니다.

관련 회귀 source: [ArtifactStreamingTests.swift:37](../Tests/SpaceSnifferCoreTests/ArtifactStreamingTests.swift#L37), [ArtifactStreamingTests.swift:109](../Tests/SpaceSnifferCoreTests/ArtifactStreamingTests.swift#L109), [NativeReportLineEndingTests.swift:16](../Tests/SpaceSnifferCoreTests/NativeReportLineEndingTests.swift#L16), [ConfiguredExportIntegrationTests.swift:63](../Tests/SpaceSnifferCoreTests/ConfiguredExportIntegrationTests.swift#L63). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W20 — 부분 대응: 확대 bitmap 재사용과 옵션별 재렌더

원본 관측: zoom은 시작/목표 bitmap을 준비해 변환해서 그리는 경로가 있고 real-zoom flag일 때는 loop에서 refreshBitmap을 한다. 같은 depth focus 변경은 zoom을 생략하는 분기가 있다.

근거: [0x428bb0](validation/windows-optimization-functions/0x428bb0.txt), [0x42bb40](validation/windows-optimization-functions/0x42bb40.txt).

현재 Mac: 원본 곡선/500ms 적용. Mac은 rect 보간으로 매 draw paint하며 bitmap 재사용은 없음.

관측 한계: 일반 재배치의 모든 rect 위치 보간은 아직 입증하지 못했다. Mac 일반 애니메이션은 사용자 요청 UI 구현이다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] R03의 일반 재배치 시간/옵션과 zoom·강조를 구분해야 한다. bitmap reuse 및 realZoom 동일-depth 동작은 미이식.

관련 회귀 source: [ReferenceContractTests.swift:83](../Tests/SpaceSnifferCoreTests/ReferenceContractTests.swift#L83). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W21 — 부분 대응: 기존 filtered TM 노드 보존·차이만 생성/제거

원본 관측: 기존 children의 FS pointer를 새 포함 목록과 대조한다. 계속 포함되는 TM node는 유지하고 빠진 노드만 제거, 새 항목만 생성한다.

근거: [0x46a490](validation/windows-optimization-functions/0x46a490.txt).

현재 Mac: ProjectionDelta가 opaque baseline/result와 same-topology proof에 한해 기존 included/weights를 COW 공유하고 바뀐 leaf와 조상 delta만 갱신한다. dense/시간/unknown metadata/topology는 full fallback이다. 기존 filtered TM 객체를 FS pointer별 유지/생성/삭제하는 원본 reconciliation 전체는 아니므로 부분 대응이다.

관측 한계: focus-first 순서와 독립적인 filtered-tree reconciliation. page COW만으로 동일 기법 적용이라고 보지 않는다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] topology add/remove/rename의 filtered-object reconciliation은 미구현이며 flat included/weights COW 비용이 남는다.

관련 회귀 source: [OptimizationMatrixTests.swift:51](../Tests/SpaceSnifferCoreTests/OptimizationMatrixTests.swift#L51). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W22 — 부분 대응: 감시 buffer/event 재사용·batch 직접 변경

원본 관측: watch buffer를 없을 때 malloc(0x7fff)하고 overlapped ReadDirectoryChangesW/event wait를 사용한다. 완료 batch를 root write lock 안에서 순회해 elementChange에 전달하고 rename record를 연결한다.

근거: [0x45bc60](validation/windows-optimization-functions/0x45bc60.txt), [0x406d30](validation/windows-optimization-functions/0x406d30.txt).

현재 Mac: FSEvents batch를 RefreshQueue에서 scope packing하고 immutable 부모/whole-root 재스캔으로 수렴시킨다. R07/R08의 취소 baseline·부분 탐색 보존·issue truncation root 승격과 watch overflow/focus 순서 회귀를 추가했다. Windows 직접 mutable elementChange·rename-pair/buffer/event-thread를 그대로 복제하지 않았다.

관측 한계: Mac의 FSEvents 부모 재검사와 같은 직접 mutation 구현은 아니다. syscall callback와 해당 batch의 동작을 관찰한 것이며 Windows 변경 폭주 성능 실측은 아니다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] Windows producer action/order/overflow와 동일 fixture 동적 비교가 필요하다.

관련 회귀 source: [ScanRecoveryTests.swift:5](../Tests/SpaceSnifferCoreTests/ScanRecoveryTests.swift#L5), [FocusScanLifecycleTests.swift:196](../Tests/SpaceSnifferCoreTests/FocusScanLifecycleTests.swift#L196). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W23 — 플랫폼 대체: 열거 metadata 재사용·조건부 추가 size query

원본 관측: 일반 속성·invalid file handle 분기에서는 전달된 high/low size를 그대로 사용한다. handle이 있으면 GetFileSizeEx, compressed/sparse 분기에서는 GetCompressedFileSizeW를 사용한다.

근거: [0x405d30](validation/windows-optimization-functions/0x405d30.txt), [0x455be0](validation/windows-optimization-functions/0x455be0.txt).

현재 Mac: 기본 POSIX는 한 lstat 결과를 size/identity/times/attributes에 재사용한다. opt-in NativeDirectoryMetadata는 getAttrListBulk 결과의 실제 필수 metadata를 쓰고 누락·mount/firmlink/unknown에 lstat fallback한다. all-or-nothing directory 수집과 oracle는 있으나 wide 회귀 때문에 기본 POSIX다.

관측 한계: 모든 파일에서 size 조회 syscall을 추가한다는 구조가 아니다. 모든 metadata가 추가 I/O 없이 수집된다는 주장도 아니다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] 현재 opt-in의 field 동등성/오류 회귀를 유지하며 대표 filesystem/분포에서 syscall·시간·peak를 비교한 뒤 활성화 여부를 판단한다.

관련 회귀 source: [NativeDirectoryMetadataTests.swift:5](../Tests/SpaceSnifferCoreTests/NativeDirectoryMetadataTests.swift#L5). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W24 — 대응 구현: 필터 조건 사전 분류·숫자 변환·빠른 조건 판정

원본 관측: 생성자/토큰 파서에서 mask·태그·속성·크기/기간을 분류하고 숫자 경계를 저장한다. 개별 노드 판정은 파싱된 필드를 사용하며 조건별 조기 실패/성공 분기가 있다.

근거: [0x43f450](validation/windows-optimization-functions/0x43f450.txt), [0x43fd20](validation/windows-optimization-functions/0x43fd20.txt), [0x440810](validation/windows-optimization-functions/0x440810.txt), [0x441b00](validation/windows-optimization-functions/0x441b00.txt), [0x4455b0](validation/windows-optimization-functions/0x4455b0.txt), [0x4422a0](validation/windows-optimization-functions/0x4422a0.txt), [0x445bd0](validation/windows-optimization-functions/0x445bd0.txt), [0x445050](validation/windows-optimization-functions/0x445050.txt), [0x444870](validation/windows-optimization-functions/0x444870.txt), [0x4447b0](validation/windows-optimization-functions/0x4447b0.txt).

현재 Mac: filter 생성 시 mask/수치 경계/태그/속성 분류. 노드마다 문자열 조건을 다시 파싱하지 않는다. R09에서 native glob LF/CRLF 끝·빈 조건·age 소수초/zero 경계를 보강했다. Mac Unicode/ACP equivalence 전체는 남는다.

관측 한계: 원본의 regex precompile이나 Mac ASCII 단축 경로 자체를 확인한 것으로 확대하지 않는다. isVoidFilter의 세 list 검사만으로 모든 scalar 조건 부재까지 증명하지 않는다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] R13 filterID와 isIncluded 반환 high byte를 조건 파싱 최적화/skip 증명으로 혼동하지 않는다.

관련 회귀 source: [ReferenceContractTests.swift:29](../Tests/SpaceSnifferCoreTests/ReferenceContractTests.swift#L29), [FilterBoundaryFollowupTests.swift:6](../Tests/SpaceSnifferCoreTests/FilterBoundaryFollowupTests.swift#L6). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W25 — 핵심 미적용: 사각형·가시성으로 계층형 hit-test 가지치기

원본 관측: 보이지 않거나 좌표가 node rect 밖이면 null을 반환한다. 포함된 노드에서만 자식에 재귀하고 첫 일치 하위 노드를 반환한다.

근거: [0x4680b0](validation/windows-optimization-functions/0x4680b0.txt).

현재 Mac: 현재 presentation flat 목록을 뒤에서 검사. 계층형 hit-test 아님. R14에서 작은22rect overhead/큰 synthetic 이득과 parent 밖 child 반례를 비교해 후보만 보존했다.

관측 한계: quadtree/이진 탐색 또는 O(logN) 보장은 아니다. 렌더 재귀 제한과 별도의 포인터 입력 처리 기법이다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] transition/reparent containment 또는 flat fallback을 증명하고 실제 presentation 분포·index build/retained bytes까지 평가해야 한다.

### W26 — 플랫폼 대체: 동일 FS 노드의 중복 스캔 진입 방지

원본 관측: node+0x6a bit2가 설정되어 있으면 root read lock을 놓고 Sleep(10) 후 재획득/취소 검사한다. 진입 시 bit2와 조상 bit1을 설정하고 완료 후 지운다.

근거: [0x406b10](validation/windows-optimization-functions/0x406b10.txt).

현재 Mac: root별 직렬 worker/admission/generation에 더해 R06 owner별 latest focus intent/FIFO/정확 ticket·root incarnation·pre/post lstat identity/realpath guard를 연결했다. 동일 owner만 교체 취소하고 master/다른 owner는 취소하지 않으며 terminal까지 slot을 drain한다. 원본 node bit busy guard나 별도 병렬 worker 동일 구현은 아니다.

관측 한계: 중복 작업 억제와 동시성 정확성 guard다. busy wait 자체를 이상적인 새 최적화로 권장하지 않는다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] disjoint parallel focus worker는 미구현이며 동시 merge·공정성 이득 없이 단순 thread 추가하지 않는다.

관련 회귀 source: [FocusScanLifecycleTests.swift:23](../Tests/SpaceSnifferCoreTests/FocusScanLifecycleTests.swift#L23). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W27 — 적용 검토: 설정 객체 lazy 생성·메모리 재사용

원본 관측: 저장된 config pointer가 null일 때만 TConfig를 만들고 XML/default 설정을 읽는다. pointer가 있으면 그 객체를 반환한다.

근거: [0x40c420](validation/windows-optimization-functions/0x40c420.txt).

현재 Mac: NativeConfiguration/NativeExportTemplate/ConfiguredReport와 bounded ConfigurationFile, CLI/MCP inspection·명시 index 선택·atomic configured export를 구현했다. 설정은 explicit immutable job 값이며 UI 기본값을 자동 적용하거나 config singleton/lazy cache를 추가하지 않았다. 전역 UI 설정/file-class palette 편집·적용은 미연결이므로 lazy cache 필요성은 계속 검토 대상이다.

관측 한계: 설정 dirty flag만으로 모든 변경을 자동 rebuild한다는 근거는 아니다. XML codec 기능 구현과 singleton/lazy cache 정책 도입은 다른 작업이다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] Mac locale formatter/strict malformed boundaries를 Windows와 동일하다고 하지 않는다. 실제 XML read/write·template 왕복과 UI settings/class integration은 별도다.
- [ ] lazy config cache는 반복 사용 profile과 소유/무효화 경계가 필요할 때 평가하며 codec 존재로 도입 완료 처리하지 않는다.

관련 회귀 source: [NativeConfigurationTests.swift:4](../Tests/SpaceSnifferCoreTests/NativeConfigurationTests.swift#L4), [ConfiguredExportIntegrationTests.swift:5](../Tests/SpaceSnifferCoreTests/ConfiguredExportIntegrationTests.swift#L5). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W28 — 플랫폼 대체: SNS 입력의 record 단위 stream 읽기

원본 관측: FILE*에서 fread로 record와 필드를 읽고 고정 길이 제한의 이름 buffer를 사용해 노드를 만든다.

근거: [0x408ef0](validation/windows-optimization-functions/0x408ef0.txt), [0x4093c0](validation/windows-optimization-functions/0x4093c0.txt), [0x4576f0](validation/windows-optimization-functions/0x4576f0.txt).

현재 Mac: SNS는 mapped-if-safe Data를 record 단위로 decode하고 1024-record autoreleasepool·cancellation/validation bitset을 사용하나 모든 tree를 만든다. inspectRoots도 decodeAll이므로 metadata-only constant memory가 아니다. DU는 canonical0x4547f0 근거의 bounded strict text adapter로 파일 전체 text/line views를 만들며 native FILE*/fgetws와 동일 streaming 구조가 아니다.

관측 한계: 입력 전부를 먼저 JSON/String으로 만들지는 않지만 최종 전체 tree는 생성한다. O(1) 전체 메모리나 mapped Data보다 항상 유리함은 미확인.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] 대형 multi-root의 metadata inspection/선택 root decode peak를 순수 stream reader와 비교해야 한다. DU unsupported escaping/UNC/모호 residual을 임의 성공 처리하지 않는다.

관련 회귀 source: [DUSnapshotTests.swift:4](../Tests/SpaceSnifferCoreTests/DUSnapshotTests.swift#L4), [LegacySNSCodePageTests.swift:4](../Tests/SpaceSnifferCoreTests/LegacySNSCodePageTests.swift#L4). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

### W29 — 핵심 미적용: 자식 이름 조회의 hint 주변 양방향 검색

원본 관측: 주어진 hint가 유효하면 그 근처에서 앞/뒤로 검색한다. 범위 밖 hint는 자식 수/2로 대체한다. 이름 일치와 유효 노드 조건을 확인한다.

근거: [0x4068a0](validation/windows-optimization-functions/0x4068a0.txt), [0x455be0](validation/windows-optimization-functions/0x455be0.txt), [0x406d30](validation/windows-optimization-functions/0x406d30.txt).

현재 Mac: SnapshotTree/QueryContext는 각 level children을 앞에서 찾고 hint 주변 양방향 탐색은 없다. R15 subtree continuation은 path 재탐색을 피하지만 이름 lookup hint 알고리즘과는 다르다. R14 localized hint는 이득, random lookup은 회귀·duplicate name first-match 반례가 있어 미채택했다.

관측 한계: 이번 추가 decompile로 확인했다. 사전 순서의 대소 비교가 없으므로 이진 탐색/해시 lookup이라 부르면 안 된다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] hint locality·duplicate-name 첫 결과·정확 UTF16/path 계약과 index build/retained bytes를 실제 호출에서 검증해야 한다.

### W30 — 부분 대응: 전체 스캔과 별도 focus 재스캔 worker 경로

원본 관측: rescanCurrentFocus는 view의 별도 thread slot을 정리하고 focus FS node 대상으로 pool 인자 0인 TSnifThread를 만들어 Start한다. master root 재스캔 경로와 분리되어 있다.

근거: [0x430270](validation/windows-optimization-functions/0x430270.txt), [0x459a00](validation/windows-optimization-functions/0x459a00.txt), [0x43e4c0](validation/windows-optimization-functions/0x43e4c0.txt).

현재 Mac: R06 owner-scoped focus intent/ticket/incarnation/target guard를 existing serialized root admission에 연결했고 Store.rescanFocus/nonroot automationRescan이 이를 사용한다. master와 다른 owner를 취소하지 않고 obsolete partial/terminal을 버리며 watcher overflow를 보존한다. 원본 pool=0 별도 focus thread와 병렬 master/focus worker는 미구현이다.

관측 한계: 별도 worker 구조를 확인했으며 실제 동시 실행/우선순위/성능은 미측정이다. pool static cap=1을 전체 프로세스의 스레드 상한으로 오해하면 안 된다.

남은 확인:

- [ ] Windows 실제 옵션/동시성/타이밍 및 SNS 왕복은 미실행이며 runtime 동등성으로 체크하지 않는다.
- [ ] parallel job/merge·공정성·대표 focus latency 측정은 별도다. source/cancel lifetime 개선만으로 병렬 기법 전체 완료라고 하지 않는다.

관련 회귀 source: [FocusScanLifecycleTests.swift:4](../Tests/SpaceSnifferCoreTests/FocusScanLifecycleTests.swift#L4). 코드 anchor의 존재는 테스트 실행 결과를 뜻하지 않는다.

## 복합 항목에서 놓치기 쉬운 하위 기법

| 상위 ID | 하위 점검 | 현재 상태 |
|---|---|---|
| W04/W21 | filtered membership/weight delta | sparse same-topology만 incremental; full fallback과 flat COW 비용 유지 |
| W05/W11 | sibling/geometry reuse | 같은 source/branch sort·rect cache; changed child local reposition 미구현 |
| W06 | tag 비의존·동일값·복합 변경 | dependency reuse/updateView batching; 모든 native dirty bit와 동일하지 않음 |
| W07/P03 | ancestor context·MCP cursor | bulk 및 explicit subtree는 mask 전달; old offset은 ancestor walk |
| W10 | fully occluded/minimized/Space lifecycle | Mac gating/return/capture 구현; native DynaSmooth scheduler 미이식 |
| W12/W27 | palette와 XML settings | 현재 palette key 캐시; explicit XML codec/export 있음, 전역 settings/class UI 미연결 |
| W13 | publication 간 text/font/width reuse | bounded MapTextCache 있음; native node-owned text object 전체와 다름 |
| W15 | node/page pool | 평가 후 미채택; worker scratch만 bounded 재사용 |
| W16/W26/W30 | worker/owner 수명 | bounded admission + owner focus intents; 별도 parallel focus worker 아님 |
| W17/W23 | bulk metadata | opt-in 후보 구현/평가, wide 회귀로 default POSIX 유지 |
| W19 | TXT newline/tie | file UTF8/LF·reverse child-position, preview CRLF; historical writer는 frozen reference |
| W20 | zoom/일반 재배치 | 500ms rect motion 구현; 원본 일반 재배치 runtime 미확인 |
| W28 | SNS/DU reader | mapped SNS + strict bounded DU; metadata inspection도 tree materialize |

## 최초 미참조 pseudocode55개 처리 상태

원본 evidence와 pseudocode/hash는 보존한다. 아래는 역할·관계의 bounded review이지 모든 instruction/alias/runtime 검증이 아니다. 과거0x455440 selector는 canonical DU0x4547f0 body 내부였으며 SNF와 혼용하지 않는다.

| 주소 | 분류 | 현재 처리 이유 |
|---|---|---|
| [0x406d30](validation/windows-optimization-functions/0x406d30.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x42da80](validation/windows-optimization-functions/0x42da80.txt) | mechanism_support | 기존 상세 깊이 감소 handler와 다시 그리기 호출 |
| [0x43fd20](validation/windows-optimization-functions/0x43fd20.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x40c2b0](validation/windows-optimization-functions/0x40c2b0.txt) | mechanism_support | 설정 form 생성과 메모리 config 수명 보강 |
| [0x405d30](validation/windows-optimization-functions/0x405d30.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x441b00](validation/windows-optimization-functions/0x441b00.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x436390](validation/windows-optimization-functions/0x436390.txt) | behavior_or_format | legacy Base64 decode 의미/실패 처리. 독립 최적화 확정 근거 아님 |
| [0x4680b0](validation/windows-optimization-functions/0x4680b0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x468360](validation/windows-optimization-functions/0x468360.txt) | mechanism_support | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x4455b0](validation/windows-optimization-functions/0x4455b0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x40a220](validation/windows-optimization-functions/0x40a220.txt) | mechanism_support | folder init의 부모/segment 연결 wrapper |
| [0x430270](validation/windows-optimization-functions/0x430270.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x43ea50](validation/windows-optimization-functions/0x43ea50.txt) | mechanism_support | cache 소멸 시 scan/watch/루트 해제 |
| [0x4051a0](validation/windows-optimization-functions/0x4051a0.txt) | mechanism_support | FS init overload의 크기 초기화 경로 |
| [0x42ee60](validation/windows-optimization-functions/0x42ee60.txt) | behavior_or_format | 제거된 focus/selection/history의 정확성 복구. 별도 성능 기법으로 세지 않음 |
| [0x4093c0](validation/windows-optimization-functions/0x4093c0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x408770](validation/windows-optimization-functions/0x408770.txt) | behavior_or_format | ADS flag getter. 저장 형식/필터 의미를 보강 |
| [0x445050](validation/windows-optimization-functions/0x445050.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x42c590](validation/windows-optimization-functions/0x42c590.txt) | mechanism_support | double click focus/zoom 호출과 선택 보호 |
| [0x4353e0](validation/windows-optimization-functions/0x4353e0.txt) | mechanism_support | SNS Base64 writer helper wrapper |
| [0x42d7a0](validation/windows-optimization-functions/0x42d7a0.txt) | mechanism_support | 기존 cache 연결·초기 scanner 시작 호출 |
| [0x445bd0](validation/windows-optimization-functions/0x445bd0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x457220](validation/windows-optimization-functions/0x457220.txt) | behavior_or_format | SNS agent의 파일/경로/식별 설정. 별도 cache 최적화로 세지 않음 |
| [0x406380](validation/windows-optimization-functions/0x406380.txt) | behavior_or_format | 할당량 cluster 반올림 계산. OS 의미 계약이며 독립 재사용 최적화로 세지 않음 |
| [0x42f0a0](validation/windows-optimization-functions/0x42f0a0.txt) | mechanism_support | 키보드 tag toggle/필터 재적용 호출 |
| [0x40c420](validation/windows-optimization-functions/0x40c420.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x43e4c0](validation/windows-optimization-functions/0x43e4c0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x42b5c0](validation/windows-optimization-functions/0x42b5c0.txt) | mechanism_support | 선택 경로 상세화와 paint 호출 |
| [0x45bc60](validation/windows-optimization-functions/0x45bc60.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x440810](validation/windows-optimization-functions/0x440810.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x43d9d0](validation/windows-optimization-functions/0x43d9d0.txt) | mechanism_support | root scanner pool과 watch worker 시작 호출 |
| [0x4576f0](validation/windows-optimization-functions/0x4576f0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x46b290](validation/windows-optimization-functions/0x46b290.txt) | mechanism_support | TM 수정 operation→부분 변경 호출 |
| [0x413b30](validation/windows-optimization-functions/0x413b30.txt) | behavior_or_format | export UI/default preset 초기화와 형식 설정 |
| [0x43f450](validation/windows-optimization-functions/0x43f450.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x4460a0](validation/windows-optimization-functions/0x4460a0.txt) | behavior_or_format | fuzzy wildcard 재귀 의미. 새로운 효율 기법/성능 우월성은 미확인 |
| [0x468320](validation/windows-optimization-functions/0x468320.txt) | mechanism_support | node rect 직접 기록/기하 수명 보강 |
| [0x445420](validation/windows-optimization-functions/0x445420.txt) | behavior_or_format | fuzzy entry의 변환·재귀 호출. 의미 보강과 비용 후보 |
| [0x43e940](validation/windows-optimization-functions/0x43e940.txt) | mechanism_support | cache lock·root 목록 생성 |
| [0x42db80](validation/windows-optimization-functions/0x42db80.txt) | mechanism_support | 기존 tooltip 포인터의 flag/표시 초기화 |
| [0x46b640](validation/windows-optimization-functions/0x46b640.txt) | mechanism_support | TM tag 전달 wrapper |
| [0x42dad0](validation/windows-optimization-functions/0x42dad0.txt) | mechanism_support | 상세 깊이 증가 handler |
| [0x408300](validation/windows-optimization-functions/0x408300.txt) | mechanism_support | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x45a470](validation/windows-optimization-functions/0x45a470.txt) | mechanism_support | working/pooled 목록 생성·최초 thread 접수 |
| [0x40bc20](validation/windows-optimization-functions/0x40bc20.txt) | behavior_or_format | TConfig 기본 객체·클래스 목록 생성. lazy cache의 직접 증거는 getConfig에 분리 |
| [0x45b650](validation/windows-optimization-functions/0x45b650.txt) | mechanism_support | 대기 working thread 시작 루프 |
| [0x435410](validation/windows-optimization-functions/0x435410.txt) | behavior_or_format | Base64 인코딩 byte 형식·이름 길이 처리 |
| [0x43d7e0](validation/windows-optimization-functions/0x43d7e0.txt) | mechanism_support | root/cache/scan pool/watch worker 소유 관계 |
| [0x455440](validation/windows-optimization-functions/0x455440.txt) | unresolved | 과거 selector0x455440은 canonical DU parser0x4547f0의 non-contiguous body 내부 주소다. DU/SNF 혼용을 정정했고 R07/R10/R13에서 문법·missing 회계와 strict adapter를 분석했다. native streaming/Windows runtime 전체 동등성은 미확인. |
| [0x415590](validation/windows-optimization-functions/0x415590.txt) | behavior_or_format | export 설정 선택 반영. XML config 전체 기능과 별개 최적화로 세지 않음 |
| [0x4422a0](validation/windows-optimization-functions/0x4422a0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x46b6b0](validation/windows-optimization-functions/0x46b6b0.txt) | mechanism_support | 형제 정렬의 비교 규칙. 별도 고속 정렬 알고리즘은 아님 |
| [0x408ef0](validation/windows-optimization-functions/0x408ef0.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x4274b0](validation/windows-optimization-functions/0x4274b0.txt) | mechanism_support | 상세 원문을 해당 체크리스트 항목에 연결 |
| [0x406b10](validation/windows-optimization-functions/0x406b10.txt) | new_mechanism_source | 상세 원문을 해당 체크리스트 항목에 연결 |

## 미해결 질문과 조사 경계

- [ ] Q01: 미분석 native procedure와 간접/vtable 경로에 추가 기법이 있는가? (open)
- [ ] Q02: Windows 실행 옵션·concurrency·CPU/RSS·cache hit와 전후 성능은? (open)
- [ ] Q03: 일반 재배치 rectangle 시간 보간·자동 영구 disk cache가 존재하는가? (open)
- [ ] Q04: filterID·modifiedAttributes(tag byte+old/new strings)·isIncluded 반환 high byte의 정적 invalidation 경계 이후, 간접 alias/event/runtime 전체 동작은? (partial)
  - 정적 확인: high byte는 payload가 아니라 isIncluded 반환의 subtree 요청이며 filterID는 generation/paint marker다. skip proof로 사용하지 않는다. [보충 근거](R13_INVALIDATION_FINDINGS.md).
- [ ] Q05: canonical DU parser0x4547f0(body 내부 과거 selector0x455440)의 지원 밖 경로/escaping·실제 fixture/CRT locale·Windows runtime 의미는? (partial)
  - 정적 확인: .DU 수용/space delimiter/dot grouping/KiB/backslash/missing 회계와 bounded strict adapter 확보. SNF 또는 모든 원본 grammar 지원으로 확대하지 않는다. [보충 근거](DU_SNAPSHOT_READER_FINDINGS.md).

Q04의 high byte는 modifiedAttributes payload가 아니라 isIncluded 반환의 subtree 요청이다. filterID는 generation/paint marker이며 subtree skip 증거가 아니다. Q05의 .DU 문법/strict adapter를 확인했지만 producer 전체·escaping/UNC/CRT locale·Windows runtime은 남는다.

## Mac 전용 추가 후보의 현재 범위

- P01 trie/radix/별도 index로 이벤트 큐 구현: RefreshPathIndex small-array/radix/FIFO platform policy; source W09.
- P02 접근성 element 재사용/lazy 500개 제한: MapAccessibilityCache target invalidation + bounded lazy accessibility elements; W14 platform extension.
- P03 MCP subtree cursor·budget·취소 연동 및 context 재사용: SubtreeQuerySession bounded DFS/context lease/one-use cursor/explicit cancel/epoch+terminal shutdown; STDIO notification 선점 미지원.
- P04 view_set 동일 값·복합 변경 batching: ScanStore.updateView + Hub view_set batching/same-value gates; native source mechanism과 구분.

이 네 항목은 Mac 플랫폼 구현이다. 원본에 MCP/radix/AX lazy 정책이 있었다고 주장하지 않는다. 최신 실행/검증은 각 R 문서와 root 통합 QA를 따르며 이 문서 source hash 갱신만으로 완료 판정을 올리지 않는다.

## 근거 보관

- [최초139 records](windows-optimization-rea-evidence.json), [추가6 records](windows-optimization-coverage-rea-evidence.json), [기존20개 원문 조사](WINDOWS_OPTIMIZATIONS.md)는 변경하지 않았다.
- [현재 R 검토](R_BACKLOG_REVIEW_2026-11-09.md), [DU reader](DU_SNAPSHOT_READER_FINDINGS.md), [R13 invalidation](R13_INVALIDATION_FINDINGS.md), [R11 config/export](R11_CONFIG_EXPORT_FINDINGS.md), [R06 owner lifecycle](R06_FOCUS_LIFECYCLE_IMPLEMENTATION.md), [R14 후보](R14_ADAPTIVE_V2.md), [R15 query](R15_QUERY_FOLLOWUP.md)를 보충 근거로 사용했다.
- [실익 후보 선택](BENEFICIAL_OPTIMIZATIONS.md)의 기존116 completion 기록을 수정하지 않았다. source_checklist_sha256만 이 재검토 결과에 맞춰 갱신한다.
