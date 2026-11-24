# Windows SpaceSniffer에서 확인한 최적화 기법

2026-11-08. 대상은 로컬에 보관한 **Windows SpaceSniffer 2.2.0.27 x64**다. 이 문서는 Mac 코드만 보고 만든 최적화 목록을 원본 기법으로 포장하지 않고, Windows 바이너리에서 확인한 동작을 따로 추출한 결과다.

- EXE: `References/Windows/2.2.0.27/SpaceSniffer.exe`
- SHA-256: `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`
- 분석기: Ghidra 12.1.4 / REA. 기존 107개 기록을 재검토하고 새 32개 기록을 추가해 총 139개를 보관했다. 새 기록에는 함수 디컴파일·어셈블리·심벌 검색이 포함된다.
- [전체 REA Evidence](windows-optimization-rea-evidence.json), [20개 항목의 근거 인덱스](windows-optimization-findings.json). 인덱스에는 함수별 전체 Evidence ID·본문 digest·원문 파일이 있다.
- 원문 링크의 첫 부분에 대상 hash·주소·Evidence ID를 적었고 decompiler 경고를 삭제하지 않았다. 가독성 파일은 총 53개 함수다.

**확인 수준은 정적 분석이다.** 코드가 가진 분기·자료구조·API 호출은 관찰했고, 그 구조가 줄이는 계산/할당은 해석으로 구분했다. Windows 실행 시간·CPU/RSS·실제 선택 옵션을 측정한 것은 아니다. 원본의 모든 최적화를 전부 발굴했다는 주장도 하지 않는다.

최초 20개에서 빠진 10개를 추가하고 Mac 코드를 대조한 **최신 [30개 통합 체크리스트](OPTIMIZATION_CHECKLIST.md)**를 작성했습니다. 이 문서는 최초 추출 기록으로 유지하며, 최신 적용 상태와 미해결 사항은 체크리스트를 기준으로 합니다.

## 주요 결론

원본은 기존 FS/TM 노드를 유지하면서 **focus 변경 재사용, delta 합산, 변경 항목의 정렬 복구, 작업 범위 축소, repaint 병합, 캐시와 재활용 풀**을 조합한다. Mac의 전체 snapshot/projection 재계산보다 변경 단위가 작은 경로가 여럿 있다. 반대로 원본도 TList 선형 검색·중첩 비교·명시적 WaitFor를 사용한다. 모든 원본 경로가 최신 인덱스나 비동기 모델보다 빠르다는 뜻은 아니다.

특히 앞선 조사에서 제안한 **trie 큐·MCP 전용 cursor·Swift packed 배열·AX 객체 재사용**은 원본 구현과 같다고 주장할 수 없다. 이 항목은 원본의 동작 계약을 유지하기 위한 Mac 플랫폼 구현 후보로 남긴다.

## 추출 목록

| ID | 원본에서 확인한 기법 | 핵심 함수 |
|---|---|---|
| W01 | 루트 데이터·리스너 공유 캐시 | `0x43ec60`, `0x43f230`, `0x4559f0` |
| W02 | 탐색 시 기존 필터 트리 재사용 | `0x428bb0`, `0x42a750`, `0x4295a0` |
| W03 | focus 우선 필터 후 중복 subtree 제외 | `0x4590a0`, `0x459170`, `0x46a490` |
| W04 | 조상 delta 누적 | `0x405a00`, `0x405260`, `0x4667a0` |
| W05 | 기존 형제 정렬의 변경 항목 재배치 | `0x4667a0` |
| W06 | 변경 의존성에 따른 재필터 제한 | `0x430400`, `0x42df10`, `0x444870` |
| W07 | 상속 태그 context의 재귀 전달 | `0x459170`, `0x46a490`, `0x406ad0` |
| W08 | 오래된 필터 작업 취소·교체 | `0x42cba0`, `0x429020`, `0x46a490` |
| W09 | 변경 요청 중복·조상 packing과 FIFO | `0x42e130`, `0x408260`, `0x42c9e0` |
| W10 | repaint 병합·간격 조절·가려진 창 생략 | `0x429140`, `0x42c760`, `0x42cd00` |
| W11 | layout/paint 분리와 표시 재귀 제한 | `0x4295a0`, `0x468db0`, `0x469770` |
| W12 | palette 포인터 캐시와 명시적 무효화 | `0x469770`, `0x46bb00`, `0x427ff0` |
| W13 | 문자열 치수 memoization | `0x4352c0`, `0x435340`, `0x468db0` |
| W14 | 지속 tooltip 객체와 dirty rebuild | `0x429aa0`, `0x450420`, `0x450590` |
| W15 | 노드 재활용 pool과 busy 참조 제외 | `0x404ee0`, `0x4658e0`, `0x448380` |
| W16 | 상한 있는 스캔 스레드 pool·event 대기 | `0x45a7c0`, `0x459e30`, `0x459a00` |
| W17 | OS 디렉터리 열거의 큰 버퍼 경로 | `0x455be0` |
| W18 | 경로 segment 저장·필요 시 full path 조합 | `0x405260`, `0x4061b0` |
| W19 | 파일 stream에 순차 export | `0x408a80`, `0x408a10`, `0x415eb0` |
| W20 | 확대 bitmap 재사용과 옵션별 재렌더 | `0x428bb0`, `0x42bb40` |

## 항목별 근거와 이식 경계

함수 주소는 이 EXE의 Ghidra 기본 주소 공간 기준이다. `node/view/thread+offset`은 디컴파일에서 관찰한 object offset이며 원본 C++ 헤더를 복구한 완전한 type layout은 아니다. 아래 링크는 해당 함수의 보관된 pseudocode이며 각 파일 상단의 전체 Evidence ID로 JSON bundle의 raw/normalized result와 연결된다.

### W01. 루트 데이터·리스너 공유 캐시

근거: [0x43ec60](validation/windows-optimization-functions/0x43ec60.txt), [0x43f230](validation/windows-optimization-functions/0x43f230.txt), [0x4559f0](validation/windows-optimization-functions/0x4559f0.txt), [0x4574e0](validation/windows-optimization-functions/0x4574e0.txt).

**관찰:** path segment와 agent GUID로 기존 root를 찾아 listener/refcount를 늘린다. 마지막 참조 해제 때 scan/watch를 정리한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 중복 스캔·중복 트리 메모리를 줄인다.

**Mac에 가져올 방향:** Mac 기존 공유 ScanService와 대응. 정규화 규칙·offline 분리를 유지한다.

**확인 한계:** 원본 비교 전에 항상 경로 정규화를 한다거나 자동 영구 캐시가 있다는 결론은 미확인.

### W02. 탐색 시 기존 필터 트리 재사용

근거: [0x428bb0](validation/windows-optimization-functions/0x428bb0.txt), [0x42a750](validation/windows-optimization-functions/0x42a750.txt), [0x4295a0](validation/windows-optimization-functions/0x4295a0.txt).

**관찰:** setNewFocus는 view+0x798을 바꾸고 DrawTreeMap/zoom을 호출한다. DrawTreeMap→refreshBitmap 경로는 기존 TM node를 배치·paint한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 탐색마다 filesystem scan이나 필터 트리 재구축을 반복하지 않는 해당 호출 경로다.

**Mac에 가져올 방향:** navigation-only membership/weights 재사용은 이 계약에 맞는 Swift 구현 후보.

**확인 한계:** 원본에 Swift Bool/Int64 배열 캐시가 있다는 의미가 아니며 모든 간접 경로 부재의 증명은 아니다.

### W03. focus 우선 필터 후 중복 subtree 제외

근거: [0x4590a0](validation/windows-optimization-functions/0x4590a0.txt), [0x459170](validation/windows-optimization-functions/0x459170.txt), [0x46a490](validation/windows-optimization-functions/0x46a490.txt), [0x42cba0](validation/windows-optimization-functions/0x42cba0.txt), [0x430400](validation/windows-optimization-functions/0x430400.txt).

**관찰:** ctor가 두 TM 인자를 +0x88/+0x90에 저장한다. Execute는 +0x90 먼저 처리하고 +0x88 처리 시 skip=+0x90을 넘긴다. updateFiltering은 this==skip이면 return한다. tag 재적용 호출은 root(+0x790),focus(+0x798)를 순서대로 전달한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 보이는 focus를 먼저 갱신하고 두 번째 traversal에서 이미 처리한 subtree를 제외한다.

**Mac에 가져올 방향:** 큰 projection의 focus 우선 단계 공개/부분 refilter 후보.

**확인 한계:** 고정 크기 batch/페이지 알고리즘이나 임의 concurrency 수는 이 근거에 없다.

### W04. 조상 delta 누적

근거: [0x405a00](validation/windows-optimization-functions/0x405a00.txt), [0x405260](validation/windows-optimization-functions/0x405260.txt), [0x4667a0](validation/windows-optimization-functions/0x4667a0.txt).

**관찰:** 파일/트리맵 노드의 +0x30/+0x38에 변화량을 더하고 부모 포인터만 따라 올라간다.

**줄이는 작업 — 코드 구조에 따른 해석:** 파일 하나의 변화에 매번 전체 subtree 합산을 피한다.

**Mac에 가져올 방향:** 기존 scanner ancestor delta와 same-topology page 갱신에 일부 반영되어 있다.

**확인 한계:** hard-link inode dedup 또는 폴더 메타데이터 기여를 추가하는 근거가 아니다.

### W05. 기존 형제 정렬의 변경 항목 재배치

근거: [0x4667a0](validation/windows-optimization-functions/0x4667a0.txt).

**관찰:** 정렬 유지 옵션과 node+0x43 상태가 참이면 변경 자식 IndexOf 후 이웃 크기를 비교하여 TList.Exchange한다. 미정렬 분기는 전체 인접 비교 pass가 있다.

**줄이는 작업 — 코드 구조에 따른 해석:** 이미 정렬된 목록을 변경 자식 주변에서 복구한다.

**Mac에 가져올 방향:** projection/geometry에서 모든 형제를 매번 sorted하는 경로의 후속 최적화 근거.

**확인 한계:** IndexOf와 이동은 선형일 수 있다. O(logN) 업데이트라고 부르지 않는다.

### W06. 변경 의존성에 따른 재필터 제한

근거: [0x430400](validation/windows-optimization-functions/0x430400.txt), [0x42df10](validation/windows-optimization-functions/0x42df10.txt), [0x444870](validation/windows-optimization-functions/0x444870.txt).

**관찰:** 태그 재적용은 isTagInvolved일 때만 applyFilterTo한다. nodeModified는 포함 결과·재필터 필요 분기와 변경 범위를 사용한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 표시색 변경과 멤버십 변화가 필요한 변경을 구별한다.

**Mac에 가져올 방향:** tag를 안 쓰는 filter에서 무조건 전체 membership을 다시 계산하는 비용을 줄일 후보.

**확인 한계:** 모든 metadata 의존성을 완성한 DAG나 high-byte의 모든 의미를 규명한 것은 아니다.

### W07. 상속 태그 context의 재귀 전달

근거: [0x459170](validation/windows-optimization-functions/0x459170.txt), [0x46a490](validation/windows-optimization-functions/0x46a490.txt), [0x406ad0](validation/windows-optimization-functions/0x406ad0.txt), [0x408670](validation/windows-optimization-functions/0x408670.txt).

**관찰:** subtree 시작의 inherited tag를 구하고 updateFiltering 재귀에 ownTag|inheritedMask를 넘긴다.

**줄이는 작업 — 코드 구조에 따른 해석:** bulk filter 중 각 파일마다 같은 태그 조상을 다시 순회하는 일을 줄인다.

**Mac에 가져올 방향:** Mac packed context의 태그 OR 의미는 대응하며 MCP bulk query에도 적용 후보.

**확인 한계:** 원본의 folder matcher는 부모 재귀가 남는다. 모든 폴더 조건 사전 계산·1byte 배열 자체는 Mac 구현이다.

### W08. 오래된 필터 작업 취소·교체

근거: [0x42cba0](validation/windows-optimization-functions/0x42cba0.txt), [0x429020](validation/windows-optimization-functions/0x429020.txt), [0x46a490](validation/windows-optimization-functions/0x46a490.txt).

**관찰:** 새 필터 전에 Terminate→WaitFor→해제한다. 재귀/노드 갱신 사이에서 취소 flag와 detached 상태를 확인한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 버려질 필터가 끝까지 진행하지 않도록 한다.

**Mac에 가져올 방향:** 기존 LatestWorker의 취소 계약과 대응. 취소 검사 전 큰 sort 등은 별도 개선 후보.

**확인 한계:** 원본은 WaitFor를 사용한다. lock-free나 실행1/대기1 mailbox 자체가 원본 기법이라는 근거는 없다.

### W09. 변경 요청 중복·조상 packing과 FIFO

근거: [0x42e130](validation/windows-optimization-functions/0x42e130.txt), [0x408260](validation/windows-optimization-functions/0x408260.txt), [0x42c9e0](validation/windows-optimization-functions/0x42c9e0.txt).

**관찰:** TList 뒤에 요청을 추가하고 중첩 전체쌍 비교로 중복/덮이는 하위 요청을 제거한다. 조상 판정은 부모 포인터를 따른다. dequeue는 index0 Get/Delete다.

**줄이는 작업 — 코드 구조에 따른 해석:** 같은/포함된 범위의 중복 refilter를 줄이고 독립 분기를 남긴다.

**Mac에 가져올 방향:** Mac RefreshQueue의 의미 계약. trie/radix는 Mac 별도 구현 선택이다.

**확인 한계:** 이 본문은 고속 trie/hash가 아니다. 원본 큐의 점근적 우월성이나 실제 Windows 처리 시간을 주장하지 않는다.

### W10. repaint 병합·간격 조절·가려진 창 생략

근거: [0x429140](validation/windows-optimization-functions/0x429140.txt), [0x42c760](validation/windows-optimization-functions/0x42c760.txt), [0x42cd00](validation/windows-optimization-functions/0x42cd00.txt), [0x42c6a0](validation/windows-optimization-functions/0x42c6a0.txt).

**관찰:** requestRepaint는 요청 강도를 max로 병합하고 layout dirty를 유지한다. timer는 pending과 visible region 조건을 확인한다. DynaSmooth는 갱신 간격을 조절한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 동일 시점의 중복 paint와 보이지 않는 화면의 갱신을 줄일 수 있다.

**Mac에 가져올 방향:** AppKit occlusion/dirty state 기반 scheduler 후보.

**확인 한계:** DynaSmooth는 위치 보간 자체가 아니다. 실제 Windows 프레임율·모든 refresh interval은 미측정.

### W11. layout/paint 분리와 표시 재귀 제한

근거: [0x4295a0](validation/windows-optimization-functions/0x4295a0.txt), [0x468db0](validation/windows-optimization-functions/0x468db0.txt), [0x469770](validation/windows-optimization-functions/0x469770.txt).

**관찰:** force-layout flag일 때 setCoords/layout하고 그렇지 않으면 저장된 기하를 paint한다. depth·선택 경로·크기·visible/expanded 상태로 재귀를 제한한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 불필요한 전체 배치와 보이지 않는 하위 paint를 피한다.

**Mac에 가져올 방향:** 기존 geometryKey를 보강하고 unchanged branch geometry 재사용 후보.

**확인 한계:** 모든 작은 양수 항목을 배치 입력에서 버려도 된다는 근거가 아니다.

### W12. palette 포인터 캐시와 명시적 무효화

근거: [0x469770](validation/windows-optimization-functions/0x469770.txt), [0x46bb00](validation/windows-optimization-functions/0x46bb00.txt), [0x427ff0](validation/windows-optimization-functions/0x427ff0.txt).

**관찰:** paint는 node+0x50가 null일 때 palette를 얻어 보관한다. resetCache는 포인터를 비우고 자식 재귀, configChanged는 대응 virtual slot을 호출한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 반복 색상 테이블 취득을 줄이고 설정 변경 시 갱신한다.

**Mac에 가져올 방향:** 기존 Mac paletteCache와 대응. UI 표현별 key/invalidation을 유지한다.

**확인 한계:** cache pointer가 픽셀 전체 또는 node geometry cache라는 뜻은 아니다.

### W13. 문자열 치수 memoization

근거: [0x4352c0](validation/windows-optimization-functions/0x4352c0.txt), [0x435340](validation/windows-optimization-functions/0x435340.txt), [0x468db0](validation/windows-optimization-functions/0x468db0.txt), [0x469770](validation/windows-optimization-functions/0x469770.txt).

**관찰:** TTextBox.setText는 다른 문자열일 때만 dirty(+0x18)를 켠다. getSize는 dirty/font size/bold 변경 때만 TextExtent하고 저장된 size를 반환한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 같은 텍스트의 글자 폭/높이 측정 반복을 줄인다.

**Mac에 가져올 방향:** MapItem sizeWidth 외 제목·글꼴별 측정 수명 분리 후보.

**확인 한계:** 검사 key는 관찰된 font size와 bold bit다. 모든 font 속성을 포함한 완전한 key라고 확대하지 않는다.

### W14. 지속 tooltip 객체와 dirty rebuild

근거: [0x429aa0](validation/windows-optimization-functions/0x429aa0.txt), [0x450420](validation/windows-optimization-functions/0x450420.txt), [0x450590](validation/windows-optimization-functions/0x450590.txt), [0x450b10](validation/windows-optimization-functions/0x450b10.txt), [0x4295a0](validation/windows-optimization-functions/0x4295a0.txt).

**관찰:** view+0x7f0의 tooltip 객체를 계속 사용한다. setRows는 rows를 저장하고 +0x40 dirty를 켠다. rebuild는 dirty가 아니면 return한다. Paint는 이 객체를 그린다.

**줄이는 작업 — 코드 구조에 따른 해석:** 매 paint마다 다수 tooltip 객체를 생성하는 구조를 피하고 layout 재계산을 분리한다.

**Mac에 가져올 방향:** Mac tooltip 수명 분리 방향의 근거. AX 객체 재사용은 Mac 플랫폼 대응이다.

**확인 한계:** setRows는 같은 rows인지 비교하지 않고 dirty를 켠다. Paint 일부 TextExtent도 남아 있어 모든 측정을 생략한다고 말하지 않는다.

### W15. 노드 재활용 pool과 busy 참조 제외

근거: [0x404ee0](validation/windows-optimization-functions/0x404ee0.txt), [0x4658e0](validation/windows-optimization-functions/0x4658e0.txt), [0x448380](validation/windows-optimization-functions/0x448380.txt), [0x448450](validation/windows-optimization-functions/0x448450.txt), [0x447fb0](validation/windows-optimization-functions/0x447fb0.txt), [0x448050](validation/windows-optimization-functions/0x448050.txt).

**관찰:** FS file node와 TM file node newNode는 recycle can을 먼저 확인한다. 없으면 각각 0x70/200 bytes 객체를 할당한다. pool은 연결 포인터로 보관하며 busy 목록의 객체를 건너뛴다.

**줄이는 작업 — 코드 구조에 따른 해석:** 반복 노드 생성/제거 시 allocation과 객체 초기화 비용을 줄일 수 있다.

**Mac에 가져올 방향:** Swift snapshot page·payload lifetime에 맞춘 재사용 설계 참고. raw pointer pool을 그대로 이식하지 않는다.

**확인 한계:** 전역 allocator 전체가 이 pool이라는 의미가 아니며 retained pool 크기/실측 절감량은 미측정.

### W16. 상한 있는 스캔 스레드 pool·event 대기

근거: [0x45a7c0](validation/windows-optimization-functions/0x45a7c0.txt), [0x459e30](validation/windows-optimization-functions/0x459e30.txt), [0x459a00](validation/windows-optimization-functions/0x459a00.txt).

**관찰:** working count를 maxConcurrency와 비교한다. pooled thread가 있으면 재설정하고 event로 깨운다. 완료 worker는 pooled list로 돌아가고 Execute는 event wait한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 스레드 생성 반복과 idle busy-loop를 줄이는 구조다.

**Mac에 가져올 방향:** bounded worker와 재사용을 참고하되 Mac syscall/I/O 특성을 측정해야 한다.

**확인 한계:** 고정 원본 data maxConcurrency의 4 bytes는 01 00 00 00이다. 기본부터 여러 스레드가 병렬 스캔한다고 주장하지 않는다.

### W17. OS 디렉터리 열거의 큰 버퍼 경로

근거: [0x455be0](validation/windows-optimization-functions/0x455be0.txt).

**관찰:** global branch에서 FindFirstFileExW(FindExInfoBasic,...,flags=2)를 호출하고 FindNextFileW로 이어간다. 다른 branch에는 FindFirstFileW가 있다.

**줄이는 작업 — 코드 구조에 따른 해석:** flag2는 Windows LARGE_FETCH로 큰 디렉터리 query buffer를 요청하는 경로다.

**Mac에 가져올 방향:** macOS bulk enumeration/stat 접근을 별도 측정할 후보.

**확인 한계:** 실행 중 어느 branch가 선택됐는지나 모든 파일시스템에서 더 빠른지는 미확인.

### W18. 경로 segment 저장·필요 시 full path 조합

근거: [0x405260](validation/windows-optimization-functions/0x405260.txt), [0x4061b0](validation/windows-optimization-functions/0x4061b0.txt).

**관찰:** init은 부모(+0x10)와 segment(+0x20)를 저장한다. getFullPath는 부모를 재귀 호출하고 separator와 현재 segment를 합친다.

**줄이는 작업 — 코드 구조에 따른 해석:** 모든 노드에 전체 조상 경로를 상주시키는 저장과 다른 구조다.

**Mac에 가져올 방향:** 현재 Swift path/name 전체 문자열 저장 비용을 줄일 장기 후보.

**확인 한계:** full path 조합 CPU·깊은 경로 비용도 있다. 프로그램 전체에 full path cache가 전혀 없다는 증명은 아니다.

### W19. 파일 stream에 순차 export

근거: [0x408a80](validation/windows-optimization-functions/0x408a80.txt), [0x408a10](validation/windows-optimization-functions/0x408a10.txt), [0x415eb0](validation/windows-optimization-functions/0x415eb0.txt), [0x416650](validation/windows-optimization-functions/0x416650.txt).

**관찰:** SNS writer는 FILE*에 필드별 fwrite, 종료 writer는 end bytes를 쓴다. TXT exportNode는 FILE*가 있으면 행을 UTF8로 fprintf하고 별도 string destination이 있으면 거기에 append한다.

**줄이는 작업 — 코드 구조에 따른 해석:** 파일 저장 경로에서 전체 최종 출력 문자열/Data를 요구하지 않는 구조다.

**Mac에 가져올 방향:** ArtifactWorker/Report/SNS에 sink 기반 writer를 추가할 원본 근거.

**확인 한계:** 원본에도 행 buffer/정렬 TList/재귀와 string destination 경로가 있다. 전체 O(1) 메모리라고 주장하지 않는다. SNS decompiler warning도 보존한다.

### W20. 확대 bitmap 재사용과 옵션별 재렌더

근거: [0x428bb0](validation/windows-optimization-functions/0x428bb0.txt), [0x42bb40](validation/windows-optimization-functions/0x42bb40.txt).

**관찰:** zoom은 시작/목표 bitmap을 준비해 변환해서 그리는 경로가 있고 real-zoom flag일 때는 loop에서 refreshBitmap을 한다. 같은 depth focus 변경은 zoom을 생략하는 분기가 있다.

**줄이는 작업 — 코드 구조에 따른 해석:** 기본 확대 과정의 반복 트리 rendering을 줄일 수 있다.

**Mac에 가져올 방향:** 원본 곡선/500ms를 유지하며 bitmap/presentation 캐시 정책을 참고한다.

**확인 한계:** 일반 재배치의 모든 rect 위치 보간은 아직 입증하지 못했다. Mac 일반 애니메이션은 사용자 요청 UI 구현이다.

## 분기를 보강한 세부 근거

### focus-first 인수 매핑

`reapplyFilterIfTagInvolved(0x430400)`는 `view+0x790`과 `view+0x798`을 `applyFilterTo`에 넘긴다. `setNewFocus`가 갱신하는 focus는 `+0x798`이다. `applyFilterTo` → `TFilterThread` ctor에서 이 두 인자는 각각 thread+0x88/+0x90에 저장된다. Execute가 +0x90을 먼저 처리하고 나머지 +0x88에서 skip하는 코드와 이어진다. 이 호출 경로의 **focus 우선 + 중복 subtree 제외**는 이름만 보고 추정한 결론이 아니다.

### 정렬 상태와 실제 교환

`deltaSize(0x4667a0)`의 pseudocode뿐 아니라 어셈블리에도 `0x466849: CMP byte ptr [RBX + 0x43], 0x0` 분기와 이웃 교환 호출들이 있다. 보강 Evidence는 `ev_778131abab47eebc5038d4fb1f6359bae4635bcd6ee17f82870387a3bb1a8e2d`다. 이것은 이미 정렬된 경우의 국소 복구 분기이며 초기 미정렬 full pass까지 없다는 뜻은 아니다.

### 스레드 pool의 상한: 기본 data는 1

`newThreadOn(0x45a7c0)`의 어셈블리는 working count를 `0x924580`의 32bit 값과 비교한다. `0x45a7f0: CMP EAX, dword ptr [0x00924580]`가 보강 근거다(`ev_c8d0c3ea2a24d1d9d5396148f9cd314dc3605f8509ee255f75b070fb3b3b4d1b`). 해당 data의 보관된 4 bytes는 `01 00 00 00`이다(`ev_018f329a697c13dfa22bd6f3878f8e81d28500d1fcb2937a01b198c2e4674dc1`).

따라서 **상한 검사·스레드 재사용 구조는 확인했지만 기본부터 많은 스레드로 병렬 스캔한다고 결론 내리면 안 된다.** 이 data의 실행 중 변경 가능성과 실제 동시 실행 수는 이번 정적 조사로 확정하지 않았다. Mac에서 무조건 concurrency를 늘릴 근거로 사용하지 않는다.

### Windows API 의미와 바이너리 관찰의 구별

원본의 `FindFirstFileExW(..., FindExInfoBasic, ..., flags=2)` 호출은 W17 원문에 있다. Microsoft 문서상 2는 `FIND_FIRST_EX_LARGE_FETCH`로 더 큰 디렉터리 query buffer를 요청하는 옵션이며 성능을 높일 수 있다. **호출 존재의 근거는 바이너리**, 플래그 의미의 근거는 [공식 API 문서](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-findfirstfileexw)다. 다른 branch에서는 FindFirstFileW도 사용하므로 실행 시 항상 LARGE_FETCH가 선택된다고 주장하지 않는다.

`isWindowCompletelyCovered`는 GetDC → GetClipBox → 반환값 1 검사 → ReleaseDC 구조다. [GetClipBox 공식 문서](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-getclipbox)는 clip region의 의미를 설명한다. 원본의 해당 조건을 발견한 것과 최신 Windows compositor에서 모든 occlusion 상태를 정확히 거르는 것을 실행 검증한 사실은 구별한다.

### Tooltip의 캐시 범위

`setRows`는 호출될 때마다 dirty를 켠다. `rebuild`는 dirty를 검사하고 끝에 이를 내리는 경로가 있다. 반면 Paint의 일부 보조 행은 TextExtent를 호출한다. 따라서 원본이 persistent tooltip과 dirty layout을 사용한다는 것은 맞지만, 같은 hover 내용에 대한 모든 문자열 처리·치수 측정이 항상 생략된다고 설명하면 과장이다. Mac 접근성 객체 재사용의 직접 원본 근거는 별도로 확인하지 않았다.

### 파일 출력과 전체 메모리 상한

SNS는 필드별 fwrite, TXT는 행 단위 fprintf가 명확하다. 그러나 원본 exportNode에는 형제 정렬용 TList와 재귀, Unicode/UTF8 행 buffer, 선택적 문자열 목적지도 있다. 가져올 수 있는 것은 **file sink로 순차 기록하는 구조**이지 전체 작업이 고정 메모리/O(1)이라는 주장이 아니다. SNS writer의 decompiler에는 bad instruction/type propagation 경고가 남아 있어 전체 제어흐름의 동등성은 기존 golden bytes·추가 assembly·원본 실행으로 보강해야 한다.

## 앞서 제안한 7개 후보를 다시 분류

| Mac 후보 | 원본 근거 | 재분류 |
|---|---|---|
| 탐색 membership/weights 재사용 | W02, W03: 기존 필터 트리 탐색·focus-first | 원본 동작에 맞는 재사용 방향. Swift 배열 캐시는 플랫폼 구현 |
| 이벤트 큐 trie/radix | W09: pointer 기반 TList packing/FIFO | **trie는 원본에서 확인되지 않음.** 원본도 중첩 목록 비교. 기존 의미를 유지하는 Mac 최적화 제안 |
| paint tooltip/AX 객체 재사용 | W10~W14: 요청 병합·layout 분리·palette/text/tooltip 캐시 | tooltip/paint 수명 분리는 직접 대응. AX 재사용은 Mac UI 구현 |
| MCP subtree 조회 | W03/W07: subtree 필터·context 전달 | subtree 범위 처리 참고. **원본 MCP/index/cursor 최적화라는 근거는 없음** |
| export 단일 pass·streaming | W19: file sink 순차 쓰기 | streaming은 직접 대응. 단일 Swift membership 공유 설계는 Mac 구현 |
| view_set batch·동일 값 스킵 | W06/W10/W13: 필요한 변경만 재필터·repaint 병합·문자열 동일값 확인 | 변경 의존성/dirty state 원칙은 대응. MCP transaction batching 자체는 원본 근거 없음 |
| selection/resize geometry 재사용 | W05/W11: 정렬 복구·layout과 paint 분리 | 배치/정렬 재사용 방향은 대응. Swift rectangle cache 설계는 별도 검증 필요 |

이 분류는 Mac 후보를 모두 폐기하거나 그대로 복제하자는 뜻이 아니다. **원본에서 가져온 동작과 플랫폼 자료구조를 분리하고, 포팅 시 기존 결과를 보존한다는 검증 조건을 붙인다.**

## 현재 Mac과의 차이 및 다음 순서

1. 탐색 전용 갱신을 전체 filter pass와 분리한다. W02를 기준으로 같은 입력의 결과를 유지하되 시간 필터·0바이트 가시성·삭제/rename fallback을 지킨다.
2. size/tag/표현 변경의 dirty 범위를 분리한다. W04/W06/W10/W11처럼 필요한 membership·합산·sort·paint만 갱신하도록 나눈다.
3. 형제 목록을 정렬된 상태로 유지하고 바뀐 자식만 재배치하는 경로를 검토한다. W05의 IndexOf/이웃 교환을 그대로 복사하기보다 Swift IDs·동률 계약·snapshot 격리에서 같은 결과가 나는지 검증한다.
4. text/tooltip/AX 수명과 paint를 나눈다. W13/W14는 제목 폭·크기 측정의 재사용 근거가 된다. 현재 사용자 UI의 외형과 애니메이션 곡선은 유지한다.
5. SNS/TXT는 원본 sink 방식을 참고하되 바이트 동등성·독점 생성·부분 실패·취소 정책을 먼저 검증한다.
6. node pool·segment path 저장은 장기 메모리 후보다. 원본의 수동 포인터 수명과 Swift COW snapshot의 안전 모델이 달라 원문 pool을 곧바로 이식하지 않는다.
7. 큐 인덱스와 MCP budget/cursor 개선은 Mac 자체 구현으로 표시하고 원본 packing·scope·정렬 결과를 보존한다.

[이전 합성 최적화 조사](OPTIMIZATION_AUDIT.md)의 25.24배 실험 차이·1.94초 큐 비용은 **Mac metadata probe 수치**다. Windows 원본이 그 비율만큼 빠르다는 근거로 사용하지 않는다.

## 남은 질문과 검증 경계

- 실제 Windows에서 어떤 enumeration branch·concurrency·zoom/refresh 설정을 쓰는가.
- 전체 디스크 scan·변경 폭주·큰 export에서 원본의 CPU/RSS/실행 시간은 어느 정도인가.
- 자동 영구 디스크 캐시가 있는가. 확인한 root cache 생성/조회/해제 경로의 파일 저장 부재는 프로그램 전체의 부재 증명이 아니다.
- 일반 재배치에서도 모든 rectangle이 시간 보간되는가. 현재 확인한 것은 zoom bitmap 경로·노드 강조·refresh cadence다.
- node filter ID(+0x58)의 모든 비교/skip 경로와 metadata 변경 dependency bit의 정확한 전체 의미.
- 모든 간접 호출·예외 경로가 복구되었는가. 직접 caller가 없다고 미사용 함수로 단정하지 않는다.

이번에는 Windows 실행·새 VM 설치·사용자 파일 변경·Mac 엔진 기능 변경을 하지 않았다. 정적 기록 139개와 여기 선택한 20개 기법이 조사 범위다. 본문의 코드상 재사용/skip 조건은 관찰이며 예상 효율은 추론이다.

## 재검증

```sh
python3 scripts/check-windows-optimization-evidence.py
python3 scripts/check-engine-evidence.py
```

첫 검사는 선택한 EXE hash, bundle digest, 각 Evidence의 authority/target/operation/address, 읽기 쉬운 원문 파일과 payload hash를 대조한다. 두 번째 검사는 기존 Mac core 계약의 추적성을 유지하는 검사다. 어느 검사도 Windows runtime 성능이나 Mac 포팅 동등성 자체를 증명하지 않는다.
