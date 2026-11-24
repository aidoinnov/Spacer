# 추가 최적화 후보 조사

2026-11-08. MCP 기술문서 작성 후 현재 작업 트리를 다시 조사했다. 이번 변경은 **조사·합성 probe·문서·TODO**이며 `Sources/`와 배포 앱의 동작은 변경하지 않았다. 원본 필터·태그·집계·FIFO·SNS 계약을 바꾸지 않고 줄일 수 있는 중복 작업을 우선했다.

먼저 적용할 후보는 **탐색 시 membership/weights 재사용**, **대량 변경 큐의 경로 인덱스**, **트리맵 draw에서 툴팁·접근성 객체 수명 분리**다. 앞의 두 항목은 현재 비용을 합성 데이터로 측정했다. draw 항목은 코드상 반복 할당을 확인했으며 실제 UI frame time은 아직 측정하지 않았다.

후속으로 Windows 원본을 다시 대조한 결과는 [원본 최적화 20개와 근거](WINDOWS_OPTIMIZATIONS.md)에 있습니다. 탐색 트리 재사용·증분 정렬·순차 파일 출력은 원본에 직접 대응하는 경로가 확인됐습니다. **trie 큐·MCP cursor·Swift 배열 cache·AX 재사용 자체를 원본 기법으로 부르지 않습니다.** 원본 큐도 TList의 중첩 비교를 사용합니다.

## 조사 범위와 방법

- 기존 [리소스 최적화](RESOURCE_OPTIMIZATION.md), [메모리 검증](MEMORY_VALIDATION.md) 이후 남은 경로를 점검했다.
- scanner·공유 ScanService·projection·navigation·트리맵 geometry/paint·artifact·MCP 조회를 읽었다.
- 사용자 디스크를 스캔하거나 실행 중인 앱의 상태를 변경하지 않았다. 합성 metadata만 생성해 독립 release 프로세스에서 순차 실행했다.
- 각 시나리오는 3회, 시간은 monotonic wall clock 중앙값이다. RSS는 fixture 생성부터 종료까지의 프로세스 최대값이며 단계별 증가분이 아니다.
- [원시 결과](validation/optimization-audit.json)에 모든 표본·소스 SHA-256·Swift 버전을 기록했다. 전체 앱의 전후 벤치마크나 이미 적용된 최적화 성능표가 아니다.

## 우선순위

| 순서 | 후보 | 영향 조건 | 확인 수준 |
|---|---|---|---|
| 1 | 탐색만 바뀔 때 필터 membership/weights 재사용 | 큰 트리에서 폴더 진입·상위·뒤로/앞으로 반복 | 현재 경로와 재사용 실험 비교 |
| 2 | RefreshQueue의 선형 prefix 검색 교체 | 서로 다른 폴더의 변경 이벤트가 한꺼번에 많이 도착 | 1,000/2,000/4,000개 비용 측정 |
| 3 | paint와 툴팁/접근성 객체 갱신 분리 | 500ms 애니메이션·hover·진행 heartbeat 재그리기 | 소스 확인, 실제 frame profiling 필요 |
| 4 | 작은 scope의 MCP 검색을 subtree 단위로 제한 | 큰 snapshot에서 작은 폴더만 largest/query | 동일 10개 파일, 무관한 형제 수만 증가시켜 측정 |
| 5 | export의 중복 membership 제거와 streaming 출력 | 작은 focus export 또는 대량 SNS/TXT | 중복 pass 소스 확인 + 현재 scoped export 측정 |
| 6 | view_set 동일 값 스킵·변경 한 번에 projection 요청 | mode/hidden/filter를 묶어 호출 | 소스 확인, worker 시작/취소 계측 필요 |
| 7 | selection/resize의 geometry 재사용 | 자식이 매우 많은 폴더에서 반복 선택·resize | 소스 확인, 큰 단일 폴더 fixture 필요 |

순서는 일반 사용의 반복 빈도·메인 스레드/actor 지연·구현 위험을 함께 고려한 판단이다. 파일 수·폴더 분포·감시 이벤트 패턴에 따라 큐나 export가 더 우선일 수 있다.

## 1. 폴더 이동이 전체 필터를 다시 계산한다

경로: `ScanStore.navigate()` → `recalculate()` → `FilterProjection.init()` → `membership()` + `weights()` + navigation + children 정렬.

- [ScanStore](../Sources/MacSpaceSniffer/ScanStore.swift): navigate 179행, recalculate 135행.
- [FilterProjection](../Sources/SpaceSnifferCore/LatestWorker.swift): 61~75행.
- [Filter](../Sources/SpaceSnifferCore/Filter.swift): membership 214행, weights 257행.

focus/history만 바뀌어도 N개 파일의 filter 판정과 하위→상위 합산을 다시 수행한다. 뒤로 이동에는 `nodes.firstIndex(where: path)`도 별도로 있다. worker로 옮겨 놓았어도 계산량과 임시 배열이 사라지는 것은 아니다.

### 측정

합성 파일 250,000개, 폴더 101개, `*.bin` 필터. 첫 10개 폴더로 이동하는 동등한 계산 10회를 비교했다. 재사용 실험은 기존 `NavigationState`와 같은 children filter/sort를 쓰며 미리 계산한 membership/weights만 재사용했다.

| 계산 구간 | 10회 중앙값 | 회당 환산 |
|---|---:|---:|
| 현재 전체 FilterProjection | 320.733ms | 32.073ms |
| membership/weights 재사용 실험 | 12.707ms | 1.271ms |

이 metadata 구간에서 약 25.24배 차이다. 초기 membership/weights 계산은 실험 재사용 구간 밖에 있으며 현재 앱이 이를 재사용하는 구현은 아직 없다. geometry·paint·IPC·디스크 I/O는 포함하지 않았다. RSS 최대 82.53MiB는 두 경로와 미리 계산한 배열을 함께 가진 동일 프로세스 전체값이므로 전후 메모리 감소율로 계산하지 않는다.

### 구현 시 지킬 조건

- 엔진 snapshot/태그·필터·숨김·크기 모드가 같은 경우만 재사용한다. projection UUID는 탐색에도 바뀌므로 그것만 cache key로 쓰면 재사용할 수 없다. 엔진 입력 revision과 UI projection revision을 분리해 판단한다.
- 시간 조건은 현재 매 pass의 now를 사용한다. 단순 재사용은 경계 시간이 지난 파일을 놓칠 수 있으므로 시간 의존 필터는 우선 기존 경로로 fallback하거나 정확한 만료 기준을 별도로 설계한다.
- 파일 선택의 가시성은 weights>0만으로 대체하지 않는다. 필터에 맞는 0바이트 파일의 selection 계약 때문에 membership도 필요하다.
- 삭제/rename/필터 제외 시 가까운 생존 부모 이동과 이력 복구는 기존 NavigationState를 유지한다. 엔진이 바뀐 입력에는 기존 전체 경로를 사용한다.
- publish와 공개 revision·projection_pending 계약은 유지한다. 재사용했다고 조회 cursor의 focus 변경을 무시하면 안 된다.
- membership Bool 배열을 보유하는 비용이 추가된다. N개당 대략 N bytes의 원소 저장소 외 배열 overhead를 고려한다. 저장하지 않은 다른 full-tree 인덱스를 무작정 추가하지 않는다.

필요 검증: 재사용 경로가 독립 전체 projection과 weights/focus/selection/history/children까지 같아야 한다. 시간 필터 경계·숨김 조상·tag OR·0바이트 파일·삭제/rename·스캔 중 navigation·offline load를 포함한다.

## 2. 대량 변경 큐의 삽입 비용이 제곱으로 증가한다

경로: `ScanService.changed()`가 actor 안에서 changes를 순회하며 `RefreshQueue.insert()`를 호출한다.

- [RefreshQueue](../Sources/SpaceSnifferCore/RefreshQueue.swift): insert 10행, removeCovered 16행, popFirst 20행.
- [ScanService](../Sources/SpaceSnifferCore/ScanService.swift): changed 111~122행.

현재 insert는 기존 경로 전체에서 조상을 찾고, 다시 전체에서 후손을 지운다. 관련 없는 경로 B개가 누적되면 대략 O(B²) prefix 비교다. popFirst도 배열 앞 삭제지만 이번 표본에서는 삽입 비용이 훨씬 컸다.

### 측정

중복·조상 관계가 없는 `/audit/branch-i/leaf` 경로를 추가했다. 같은 폴더에 파일이 많이 바뀌어 부모 하나로 합쳐지는 일반 사례와 다르며, **독립 폴더에 걸친 변경 폭주** 조건의 측정이다.

| 요청 수 | 삽입 중앙값 | 전체 drain 중앙값 |
|---|---:|---:|
| 1,000 | 126.105ms | 0.121ms |
| 2,000 | 505.890ms | 0.361ms |
| 4,000 | 1,941.877ms | 1.216ms |

요청을 2배로 늘릴 때 삽입 시간이 약 4배가 되는 패턴을 관측했다. 4,000개가 실제 한 actor 작업에 누적되면 그동안 다른 ScanService 요청도 기다릴 수 있다. UI 메인 스레드가 직접 1.94초 블로킹된다고 해석하지는 않는다. 실제 FSEvents 전달 패턴은 이번 실험에 포함하지 않았다.

### 구현 후보와 계약

경로 성분 trie/radix 또는 별도 ancestor index로 prefix 판정을 줄이고 FIFO에는 안정적인 순서 ID를 둔다. 정렬 Set만으로 바꾸면 원본 순서 계약을 잃을 수 있다.

유지할 예:

- 이미 `/a`가 있으면 `/a/x`는 무시한다.
- `/a/x`, `/b` 뒤에 `/a`가 오면 `/a/x`는 제거하고 결과는 `/b`, `/a`다. 새 조상을 기존 후손 자리에 앞당기지 않는다.
- `/a`와 `/ab`는 독립 경로다. prefix 문자열만 비교해 잘못 합치면 안 된다.
- root·중복·Windows 구분자·기존 SnapshotTree.contains 의미를 검토하고 종료/감시 세대 변경의 removeAll도 유지한다.

필요 검증: 기존 큐를 oracle로 한 무작위 삽입/제거/pop 시퀀스 동등성, FIFO, 조상 교체, 폭주·취소·monitor 해제 시 메모리 해제. 배치 처리를 worker로 옮긴다면 actor로 결과를 가져올 때 generation과 새로 추가된 이벤트를 잃지 않아야 한다.

## 3. 트리맵은 매 draw에서 툴팁과 접근성 객체를 다시 만든다

- [TreemapView](../Sources/MacSpaceSniffer/TreemapView.swift): draw 135~207행, updateNSView 25행.
- [MapTransition](../Sources/MacSpaceSniffer/MapTransition.swift): items(at:) 60행.

현재 draw마다 다음 작업이 있다.

1. removeAllToolTips, 표시 items 배열 계산.
2. 모든 visible 항목의 path→rect dictionary 생성.
3. 각 항목의 path/text/font attribute와 도형 구성, 툴팁 재등록.
4. `visible.filter(...).prefix(500)`와 새 NSAccessibilityElement 생성, children 전체 교체.

`filter`는 prefix 이전에 모든 일치 항목 배열을 먼저 만든다. 접근성 child는 최대 500개지만 filter 중간 배열은 그보다 클 수 있다. 애니메이션은 명목상 60Hz, 500ms이므로 draw가 30회 실행되면 최대 15,000개의 접근성 element를 새로 만들 수 있다. 이는 코드로 계산한 잠재 할당 수이며 실제 draw 수·프레임 지연·할당량을 계측한 수치가 아니다.

hover는 outline만 바뀌어도 전체 draw를 요청한다. progress heartbeat도 ObservableObject 갱신을 통해 `updateNSView`에서 needsDisplay를 세운다. geometryKey가 동일하면 기하 계산은 건너뛰지만 paint 관련 작업은 남는다.

### 개선 후보

- 접근성 element는 path/ID에 따라 재사용하고 label·frame·enabled만 필요한 때 갱신한다. visibility/현재 snapshot 확인과 500개 제한을 유지한다.
- 툴팁 수명은 layout/presentation 변경과 연결하고 단순 hover redraw와 분리한다. 애니메이션 중 tooltip rect가 오래된 위치에 남지 않도록 frame 갱신 정책이 필요하다.
- accessibility 후보는 lazy sequence나 직접 순회로 최대 500개에서 중단한다.
- 정적인 text/font attributes와 부모 관계는 캐시하되 사각형이 움직이는 동안의 clip/hit 정확성을 유지한다.
- settled 상태의 부모 rect index와 transition 프레임의 index를 구별한다. animation을 제거하거나 원본 곡선/500ms를 줄이는 방식으로 해결하지 않는다.

필요 검증: 실제 draw의 p50/p95 시간·할당 프로파일, 60Hz 부하, hover·중단된 전환·Reduce Motion·VoiceOver·툴팁·새 snapshot ID 재배치. 현재 사용자가 만족한 UI 모양은 유지한다.

## 4. 작은 scope의 MCP largest도 전체 트리를 순회한다

- [Queries](../Sources/SpaceSnifferAutomation/Queries.swift): query_nodes 68~79행, largest_nodes 80~106행.

largest_nodes는 O(K) heap으로 전체 정렬을 피하지만, scope가 10개 파일이어도 N개 노드를 검사한다. query_nodes도 flat cursor에서 scope 밖 노드를 검사 예산에 포함한다. 작은 scope가 뒤쪽에 있으면 여러 빈 페이지를 받을 수 있다.

### 측정

같은 `/audit/target`의 파일 10개를 그대로 두고, 루트에 무관한 형제 파일만 더했다. largest_nodes의 scope와 limit=10, 반환 path/bytes의 조건은 같다.

| scope 밖 파일 수 | target 파일 수 | largest_nodes 중앙값 |
|---|---:|---:|
| 0 | 10 | 0.066ms |
| 100,000 | 10 | 13.695ms |
| 250,000 | 10 | 33.790ms |

이 표는 현재 알고리즘의 scale 측정이며 개선 구현과의 비교가 아니다. 마지막 행의 최대 RSS 88.17MiB는 25만 파일 fixture를 포함한 프로세스 전체값이지 10개 결과의 메모리 비용이 아니다.

### 개선 후보

- scope의 children을 stack으로 순회하는 subtree 경로와 top-K heap을 결합한다. subtree가 flat 배열의 연속 구간이라고 가정하지 않는다. live scanner의 디렉터리 발견/순회 순서에서는 다른 형제가 섞일 수 있다.
- query_nodes는 현재 cursor가 flat index이므로 subtree 순회로 바꾸면 기존 offset 계약이 달라진다. 새 cursor version 또는 별도 API를 설계하고 기존 호출 호환성을 검토한다.
- 작은 scope에서는 parent-chain tag/folder context를 먼저 계산해 각 파일에서 같은 조상 필터를 반복 평가하는 비용도 줄일 수 있다. 현재 query_nodes는 bulk membership의 packed context가 아니라 파일별 matches를 호출한다.
- full root largest는 여전히 전체 N을 봐야 정확하다. worker에 있다는 이유만으로 비용이 제한된다고 설명하지 않는다. 검사 budget/cancellation 연동도 별도 후보다.

필요 검증: 원래 전체 검사 결과와 동일 path/id/정렬/bytes, 동률 작은 id, scope 자신 제외, native_type 특수 레코드·0바이트·Windows path·tag 상속·revision 보호.

## 5. Export가 filter 판정을 두 번 하고 전체 결과를 메모리에 만든다

- [ArtifactWorker](../Sources/SpaceSnifferCore/ArtifactWorker.swift): export 22~27행.
- [Filter](../Sources/SpaceSnifferCore/Filter.swift): matchingIDs 244행과 weights 257행이 각각 membership 호출.
- [Report](../Sources/SpaceSnifferCore/Model.swift): simpleFileList 121~136행.
- [SNS](../Sources/SpaceSnifferCore/SNSSnapshot.swift): encode 33~61행.

TXT export는 membership을 두 번 구한다. scope가 작아도 두 pass는 전체 snapshot에 적용된다. 이후 IDs 배열→Set, weights, 경로 lines 배열, joined String, UTF-8 Data를 만든다. SNS도 전체 Data와 순회 stack을 만든다. 긴 파일 경로·대량 결과에서는 출력 크기에 비례하는 추가 메모리가 필요하다.

### 현재 비용 표본

전체 250,000개 파일 중 첫 폴더의 2,500개 파일을 scope로 하고 `*.bin` 1,250개 경로를 출력하는 현재 계산 구간은 중앙값 54.161ms였다. 같은 필터의 membership 한 번과 결과 checksum reduce는 20.926ms였다. 후자는 reduce가 포함된 별도 계측이므로 20.926ms 전체를 제거 가능한 순수 중복 비용 또는 export 개선율로 단정하지 않는다. 실제 디스크 쓰기는 포함하지 않았다.

### 개선 후보

- leaf membership을 한 번 만들고 weights를 계산한 뒤, 별도 COW 부모 포함 처리로 export IDs를 얻는다. 부모 포함으로 변경한 membership을 leaf weights 입력으로 잘못 재사용하지 않는다.
- TXT는 기존 순회·files-first·크기 정렬·동률·UTF8/CRLF 바이트를 유지하는 sink writer를 추가한다. 순회 stack과 형제 정렬 메모리까지 O(1)이 되는 것은 아니다.
- SNS도 같은 record writer를 Data sink/file sink로 나눌 수 있지만 name 인코딩·종료 bytes·exclusive/atomic 쓰기·부분 실패 정리 정책을 먼저 명시한다.
- 동시 artifact 2개 제한이 있어도 각 job이 snapshot과 큰 buffer를 잡을 수 있다. 이력 32개 제한과 실행 중 입력 메모리 제한은 다르다.

필요 검증: 독립 golden bytes, 기존 Report/SNS 결과 바이트 완전 일치, 동일 timestamp 기준, focus/filter/hidden/mode, 0바이트·특수 type, 실패·동일 output 경합·덮어쓰기 거부·취소/부분 파일 정책.

## 6. MCP view_set이 같은 값도 projection을 다시 요청할 수 있다

- [ScanStore](../Sources/MacSpaceSniffer/ScanStore.swift): sizeMode/showHidden didSet, recalculate.
- [AutomationHub](../Sources/MacSpaceSniffer/AutomationHub.swift): view_set에서 mode·hidden·filter 순차 대입.

현재 size_mode와 show_hidden은 기존 값과 같아도 didSet에서 recalculate를 호출한다. navigation+mode+hidden+expression을 한 호출에 넣으면 여러 submit과 취소가 생길 수 있다. LatestWorker는 대기 하나로 합치지만 이미 시작된 pass의 초기 할당과 취소 검사 전 계산은 남는다. 반대로 depth/list만으로 전체 membership을 다시 계산하지 않는 기존 경로는 유지해야 한다.

개선 후보: oldValue 비교와 batch update의 단일 projection 요청. 동일 filter 재적용은 상대 시간 조건을 다시 평가하려는 의미일 수 있으므로 문자열이 같다는 이유만으로 항상 생략하지 않는다. pending input/fallback filter/오류 표시·MCP accepted와 projection_pending 계약을 함께 검토한다.

현재 효과 크기는 미측정이다. worker 시작/완료/취소를 구분해 실제 연속 호출에서 버려진 일을 계측한 후 적용한다. 현재 WorkerTelemetry.runs만으로 성공 완료 수를 판정하지 않는다.

## 7. Selection·resize 때 큰 형제 목록의 geometry를 다시 정렬한다

- [TreemapView](../Sources/MacSpaceSniffer/TreemapView.swift): geometryKey에 selected/bounds 포함.
- [Treemap](../Sources/SpaceSnifferCore/Treemap.swift): layout의 filter/sorted와 tiles의 재귀 layout.

geometryKey는 selection이 바뀌어도 달라진다. 원본 계약상 선택 경로의 내부를 더 보여줘야 하므로 selection을 key에서 제거하면 안 된다. 다만 같은 snapshot/weights/bounds에서 변하지 않은 형제 rect/정렬을 재사용하는 방안을 검토할 수 있다. resize 시도 정렬 순서가 같다면 sorted children의 재사용 후보가 된다.

양수 항목은 sub-pixel이어도 면적 배치에 참여한다. 작은 항목을 layout 입력에서 먼저 버려 화면을 가볍게 만들면 기존 면적·선택 계약을 바꿀 수 있다. 실제 그리기 item culling과 배치 입력 제거를 구별한다. 취소 검사 전에 실행하는 큰 sorted 구간도 빠른 재요청에서 지연 요인 후보지만, 현재 worker latest 계약을 유지하며 별도 측정해야 한다.

## 보류할 변경

- scanner 디렉터리 이름의 전체 수집·sorted는 큰 단일 폴더의 비용 후보다. 이번에는 디스크 열거를 측정하지 않았고, 순서 변경이 node ID·동률·SNS/report에 주는 영향을 확인하지 않았다. 단순 제거 대상으로 확정하지 않는다.
- 파일 path/name/identity 문자열 압축과 전역 인덱스는 N에 비례하는 저장 비용을 줄이거나 늘린다. deep/Unicode/Windows snapshot/rename·공유 page에서의 비용을 별도 측정한 뒤 판단한다.
- MCP text JSON과 structuredContent의 중복은 전송 메모리 비용이지만 클라이언트 호환성을 확인하지 않고 제거하지 않는다.
- 전체 볼륨 scan의 syscall/I/O 병목은 metadata probe로 검증하지 않았다. scanner 스레드를 늘리면 더 빨라진다고 추정해 변경하지 않는다.

## 다음 구현 순서와 완료 기준

1. **탐색 projection 분리:** 고정 필터의 same-input 재사용부터 적용. 전체 projection oracle과 결과 비교 후 실제 앱 폴더 이동의 p50/p95와 RSS 확인.
2. **이벤트 큐 인덱스:** 기존 큐 oracle로 FIFO/조상 결과를 대조하고 폭주 측정. actor가 장시간 점유되지 않는지 관찰.
3. **paint 객체 수명 분리:** 프레임/할당부터 계측하고 tooltip/AX/hit·중단 전환을 실제 앱에서 검증.
4. MCP subtree·export·batch/geometry는 위 범위와 독립적으로 후속 적용한다.

이 목록은 구현 계획이지 완료 체크가 아니다. 엔진 의미가 변하는 최적화는 원본 근거·기존 계약 검토 없이 넣지 않는다. 구현 시 단위/회귀 검사 후 변경된 경로에 맞는 실제 QA를 수행하며, 이번 조사만으로 기존 Swift 51개 테스트를 새로 실행했다고 보고하지 않는다.

## 재현

```sh
swiftc -O -whole-module-optimization Sources/SpaceSnifferCore/*.swift scripts/bench/optimization-audit.swift -o /tmp/macsniffer-optimization-audit
# SwiftPM release module/object를 현재 소스에 맞게 준비
swift build -c release --arch arm64
swiftc -O -parse-as-library -I .build/arm64-apple-macosx/release/Modules .build/arm64-apple-macosx/release/SpaceSnifferCore.build/*.o .build/arm64-apple-macosx/release/SpaceSnifferAutomation.build/*.o scripts/bench/mcp-query-audit.swift -o /tmp/macsniffer-mcp-query-audit
python3 scripts/bench/audit-optimizations.py --core-probe /tmp/macsniffer-optimization-audit --mcp-probe /tmp/macsniffer-mcp-query-audit --output /tmp/macsniffer-optimization-audit.json
```

위 module 경로는 이 Apple Silicon 측정 환경 기준이다. 다른 아키텍처에서는 해당 SwiftPM 경로를 사용한다. 최초 측정은 직전 Universal 빌드의 release objects를 사용했다. 재사용 membership/weights는 미리 준비된 같은 snapshot의 배열이며 초기 계산 시간을 포함하지 않는다. 시나리오 실행 순서·warm cache·백그라운드 부하를 통제하지 않았으므로 절대 시간과 비율은 환경에 따라 달라질 수 있다.


누락 재점검 후 원본 목록은 [30개 통합 체크리스트](OPTIMIZATION_CHECKLIST.md)로 보강했습니다. 원본 기법과 Mac 구현 상태를 분리해 기록하고, 최초 미참조 pseudocode 55개를 차집합 기준으로 추적했습니다.
