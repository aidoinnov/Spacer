# Mac에서 실익을 기대할 수 있는 최적화 추림

2026-11-08. [원본 30개 체크리스트](OPTIMIZATION_CHECKLIST.md)에서 현재 Mac 구현에 남은 비용을 줄일 후보를 **8개 작업 단위**로 추렸다. 노드 풀·스레드 풀은 별도의 **선행 평가 2개(E01/E02)**로 추적한다. 구체적인 의존성·수명 계약·측정·완료 기준은 [실행 TODO](../TODO.md)에 있다. 함수별 원본 근거/Evidence ID는 해당 체크리스트와 [구조화 선택 목록](beneficial-optimizations.json)에 연결된다.

Windows 원본과 시스템이 다르므로 가져올 것은 중복 계산·할당·재탐색을 줄이는 원리다. 구현은 Swift COW snapshot·actor·FSEvents·AppKit의 수명과 데이터에 맞춘다. 원본 pointer pool·Win32 buffer·Sleep/WaitFor·동시성 수치를 그대로 이식해 이득이 난다고 가정하지 않는다.

**최신 적용:** 2026-11-09 B01 핵심 재사용 및 B02 동일 값/복합 요청 일부를 구현했다. [검증 기록](PROJECTION_SESSION_VALIDATION.md)을 참조한다. 아래 추림과 최초 probe 수치는 선정 당시 근거이며, 나머지 후보가 적용 완료됐다는 뜻은 아니다. B01은 재사용 probe 비교가 있고 B08은 후속 index 전후 측정을 완료했다([검증](REFRESH_QUEUE_VALIDATION.md)). 나머지는 코드상 낭비/구조 근거와 이득이 생길 조건을 확인한 후보이며, 실제 반영 전후의 시간·메모리·결과 동등성을 통과해야 채택한다. 조건부 항목의 이득을 보장하지 않는다.

## 추린 목록

| ID | 작업 | 기대 이득·조건 | 순서 | 원본 연결 |
|---|---|---|---|---|
| B01 | 탐색 전용 projection에서 기존 판정·합계 재사용 | 전체 membership/weights 재계산과 임시 배열 할당 감소. | 우선 적용 | W02 |
| B02 | 변경 종류별로 필요한 계산만 다시 실행 | 불필요한 전체 filter pass·중복 submit·취소되는 초기 작업 감소. | 우선 적용 | W06 |
| B03 | 작은 파일 변경의 filtered 합계·포함 상태 증분 갱신 | 매 변경마다 전체 N의 membership·filtered weights를 만드는 비용 감소. | 후속 적용 | W04, W21 |
| B04 | 기존 형제 순서·변하지 않은 배치 재사용 | 전체 형제 정렬과 동일 branch geometry 계산 반복 감소. | 후속 적용 | W05, W11 |
| B05 | 문자열·툴팁의 수명을 paint와 분리 | 글자 치수/문자열/tooltip 등록의 반복 처리·할당 감소. | 우선 적용 | W13, W14 |
| B06 | 필요한 paint만 요청하고 가려진 창의 시각 작업 유예 | 실제로 보이지 않는 geometry/paint와 불필요한 redraw 감소. | 조건부 적용 | W10 |
| B07 | 한 번 판정하고 SNS/TXT를 순차 기록 | 중복 membership 계산과 전체 lines/String/Data 동시 보유 감소. | 우선 적용 | W19 |
| B08 | 중복·조상 packing 계약을 유지하는 이벤트 큐 index | 반복 prefix 검색과 actor 점유 시간 감소. | 우선 적용 | W09 |

B08은 **원본 packing/FIFO 계약을 지키는 Mac 자료구조 개선**이다. 원본에 trie/hash가 있다는 근거는 없다. B05의 AX element 재사용과 B02의 MCP batching 역시 Mac 플랫폼 구현 선택으로 구분한다.

## 풀 최적화 선행 평가

| ID | 근거 | 평가·채택 조건 |
|---|---|---|
| E01 | W15: FS/TM recycle can, busy 노드 제외 | 노드·page·worker scratch 후보를 비교한다. reader가 잡은 snapshot 저장소는 재사용하지 않고, pool 보유 메모리 상한과 해제 정책을 검증한다. |
| E02 | W16: worker 재사용·상한, W30: 별도 focus worker | blocking I/O 실행 경로와 프로세스 전체 scan 상한을 비교한다. 기존 task 재사용을 thread pool 부재로 오인하지 않고, 취소·종료·대기열·완료 전달을 검증한다. |

두 항목은 불필요하다고 제외한 것이 아니다. G00 기준 측정 뒤 우선 평가하고 실제 이득을 보이는 구현을 채택한다. 평가 완료와 풀 도입 완료는 구분한다. W30 전체 기능의 채택 여부는 별도 판단한다.

## 적용 조건과 보존할 동작

### B01. 탐색 전용 projection에서 기존 판정·합계 재사용

**언제 이득인가:** 폴더 진입·상위·뒤로/앞으로 이동. 같은 snapshot/filter/hidden/mode인 경우.

**Mac 구현 방향:** Mac의 snapshot 입력 identity와 filter/mode/hidden/tag revision으로 무효화 키를 만든다. navigation/history 복구는 기존 경로를 사용한다.

**현재 근거:** 25만 파일에서 이동 10회: 전체 projection 320.733ms, 재사용 probe 12.707ms. 초기 계산·geometry/paint는 제외한 실험이다.

- 시간 의존 필터는 우선 기존 경로로 fallback하거나 정확한 만료 기준을 설계한다.
- weights>0로 membership을 대체하지 않는다. 0바이트 selection을 보존한다.
- 공개 snapshot_revision/projection_pending·삭제/rename·scope 변경의 일관성을 유지한다.

**채택 기준:** 전체 projection oracle과 결과가 같고 실제 navigation p50/p95·할당·RSS를 전후 비교한다.

### B02. 변경 종류별로 필요한 계산만 다시 실행

**언제 이득인가:** 태그를 표시만 바꾸거나 동일 값/설정 조합을 반복 적용할 때.

**Mac 구현 방향:** membership 의존 변경, 합계 의존 변경, paint-only 변경을 분리한다. tag 비의존 filter는 색 갱신만 요청하는 경로를 둔다.

**현재 근거:** 현재 tag 변경은 revision/broadcast→전체 projection 경로다. 제거 가능한 호출은 확인했지만 전체 앱 개선율은 미측정이다.

- 태그가 filter에 쓰이면 inherited membership까지 갱신한다.
- 동일 filter 문자열 재적용이 시간 조건 재평가를 의도할 수 있어 무조건 생략하지 않는다.
- 색상·notice·MCP 상태가 갱신되지 않는 일이 없어야 한다.

**채택 기준:** 같은 입력의 최종 결과를 기존 경로와 비교하고 projection 시작/취소/완료 수·응답 지연을 측정한다.

### B03. 작은 파일 변경의 filtered 합계·포함 상태 증분 갱신

**언제 이득인가:** 같은 topology에서 일부 파일 크기/속성이 바뀌는 반복 변경.

**Mac 구현 방향:** 안정적인 node ID와 dirty 범위를 이용해 변한 leaf·영향받는 ancestors만 갱신한다. 입력 변화가 불명확하면 전체 projection으로 fallback한다.

**현재 근거:** FS same-topology delta는 이미 있고 filtered weights는 여전히 전체 계산한다. 새 증분 projection 구현의 개선율은 미측정이다.

- 변경 ID/속성·새 snapshot의 연결 계약을 먼저 정의한다.
- 필터 경계 통과, 부모 tag/숨김, 0바이트, 삭제·추가·rename은 보수적으로 처리한다.
- 단순 size-only delta로 모든 조건을 갱신한 것으로 처리하지 않는다.

**채택 기준:** 전체 membership/weights oracle과 파일별·조상별 결과를 비교하고 작은 변경당 시간·RSS·변경 폭주 수렴을 측정한다.

### B04. 기존 형제 순서·변하지 않은 배치 재사용

**언제 이득인가:** selection·resize와 소수 파일 변경에서 같은 형제 집합을 반복 배치할 때.

**Mac 구현 방향:** weights/revision/scope/bounds/depth/selection에 따라 정렬 순서와 배치 결과를 구분해 재사용한다. cache 수명은 현재/직전 입력 정도로 제한한다.

**현재 근거:** projection과 Treemap.layout의 전체 sorted 경로를 확인했다. 해당 cache의 실제 CPU/RSS 이득은 미측정이다.

- Int64/Double 변환·동률·양수 면적 참여 규칙을 보존한다.
- 선택 경로 상세화 때문에 selection을 무시한 geometry key를 만들지 않는다.
- 원본 tiny chunk 표시 정책을 UI에 무조건 복제하지 않는다.

**채택 기준:** 동일 입력의 rect/순서·선택 경로 결과를 비교하고 selection/resize p95와 cache 보유 메모리를 측정한다.

### B05. 문자열·툴팁의 수명을 paint와 분리

**언제 이득인가:** 애니메이션·hover·같은 geometry의 반복 draw.

**Mac 구현 방향:** text/font/값이 바뀔 때 측정하고 같은 항목의 tooltip 정보를 재사용한다. AX element 재사용은 별도의 AppKit 플랫폼 확장으로 표시한다.

**현재 근거:** draw마다 tooltip 제거/재등록, 최대 500개 AX 객체 재생성을 확인했다. 실제 frame/할당 개선율은 아직 측정하지 않았다.

- 전환 중 tooltip/hit/clip rect가 현재 화면 위치와 같아야 한다.
- VoiceOver frame·활성 상태·이름과 snapshot ID 재배치를 검증한다.
- 표시 외형·500ms 곡선·Reduce Motion을 유지한다.

**채택 기준:** 실제 draw p50/p95·allocation을 전후 비교하고 tooltip/VoiceOver/중단 전환을 QA한다.

### B06. 필요한 paint만 요청하고 가려진 창의 시각 작업 유예

**언제 이득인가:** 창이 최소화·완전히 가려져 있거나 표시 내용 변화가 없는 update가 반복될 때.

**Mac 구현 방향:** AppKit needsDisplay의 기본 병합을 활용한다. visibility/dirty 상태를 구분하고 다시 보일 때 최신 표시 작업을 반영한다.

**현재 근거:** 모든 representable update가 needsDisplay를 세우는 코드는 확인했다. 실제 visibility별 CPU 차이는 미측정이다.

- 원본 DynaSmooth 타이머를 문자 그대로 복제하지 않는다.
- 스캔·데이터 projection·MCP 조회 상태는 표시 visibility와 분리한다.
- view_capture 요청과 복귀 시 최신 화면을 보장하고 animation timer 수명을 정리한다.

**채택 기준:** 보이는/가려진/최소화 상태의 draw/geometry 실행 수와 CPU를 비교한다. 이득이 없는 상태에는 추가 scheduler를 강제하지 않는다.

### B07. 한 번 판정하고 SNS/TXT를 순차 기록

**언제 이득인가:** 큰 SNS 저장·TXT export, 또는 큰 트리의 작은 focus export.

**Mac 구현 방향:** 같은 판정 시각의 membership을 공유하고 기존 순회/인코더에 Data sink와 file sink를 나눈다. Actor I/O와 exclusive/atomic 정책을 보존한다.

**현재 근거:** 25만 파일 중 한 폴더의 현재 export 계산 구간은 54.161ms였다. membership 중복과 전체 출력 buffer는 확인했지만 streaming 구현의 개선량은 미측정이다.

- 파일 우선·크기/동률 정렬·UTF8/CRLF·SNS golden bytes를 보존한다.
- 파일 오류·동일 output 경합·부분 파일·취소 정리 정책을 정의한다.
- 부모 포함 처리한 membership을 leaf weights에 잘못 재사용하지 않는다.

**채택 기준:** 기존 writer와 바이트가 같고 큰 export peak RSS/시간이 줄어드는지 측정한다. 기존 파일 덮어쓰기 거부도 검사한다.

### B08. 중복·조상 packing 계약을 유지하는 이벤트 큐 index

**언제 이득인가:** 서로 독립된 폴더의 이벤트가 한꺼번에 누적될 때.

**Mac 구현 방향:** 원본의 중복/조상 병합·독립 FIFO 의미는 유지하면서 Mac 경로 component index나 동등한 구조를 선택한다.

**현재 근거:** 현재 큐 독립 1천/2천/4천 경로 삽입 중앙값: 126.105/505.890/1941.877ms. 새 index의 전후 성능은 아직 측정하지 않았다.

- trie/hash가 원본에 있다는 근거로 표시하지 않는다.
- 새 ancestor는 기존 descendant 위치로 당기지 않고 원래 append 순서를 지킨다.
- /a와 /ab 경계·감시 세대·취소·removeCovered를 유지한다.

**채택 기준:** 기존 큐를 oracle로 임의 시퀀스 결과를 대조하고 같은 폭주 입력에서 시간·메모리를 비교한다.

## 선택 순서

1. **B01 탐색 재사용**으로 반복되는 전체 pass부터 줄인다.
2. **B02 변경 의존성 분리**로 불필요한 pass/submit을 줄인다.
3. **B05 text/tooltip 수명 분리**와 **B08 큐 index**를 각각 UI 반복 할당·이벤트 폭주 조건에서 적용한다.
4. **B07 출력 경로**는 큰 저장/내보내기의 메모리/중복 계산을 줄인다. 두 작업을 한 거대 변경으로 묶지 않는다.
5. **B04 정렬/배치 재사용**, **B03 증분 projection**은 invalidation/dirty 계약을 준비한 뒤 적용한다.
6. **B06 가려진 창 처리**는 visibility별 실제 작업량을 확인한 범위에서 적용한다. AppKit의 기존 병합을 중복 구현하지 않는다.

수치 해석: B01의 약 25배는 특정 metadata probe 구간 차이이며 전체 앱 속도 배율이 아니다. B08의 1.94초는 현재 4,000개 독립 경로 삽입 표본이며 새 index가 얼마나 빨라졌다는 결과가 아니다. B07 수치는 실제 디스크 쓰기를 제외한다. [측정 원문](validation/optimization-audit.json)과 [측정 조건](OPTIMIZATION_AUDIT.md)을 따른다.

## 30개 전부의 선택/보류 확인

이 표로 원본 목록 중 판단하지 않은 항목이 없도록 한다. 보류는 영구 배제가 아니라 **현재 적용 이득의 근거가 부족하거나 플랫폼 위험이 더 큰 항목**이라는 의미다.

| 원본 ID | 기법 | 판단 | 이유 |
|---|---|---|---|
| W01 | 루트 데이터·리스너 공유 캐시 | 기존 유지 | 공유 root/cache 수명 대응이 이미 있음. 다시 구현할 항목 아님. |
| W02 | 탐색 시 기존 필터 트리 재사용 | 선택 | 선택 작업 B01의 원본 근거 |
| W03 | focus 우선 필터 후 중복 subtree 제외 | 이번 적용에서 보류 | focus-first는 첫 결과를 앞당길 수 있지만 전체 CPU 감소 보장이 없고 중간 publish·추가 snapshot 비용이 든다. 우선 실제 지연을 측정한다. |
| W04 | 조상 delta 누적 | 선택 | 선택 작업 B03의 원본 근거 |
| W05 | 기존 형제 정렬의 변경 항목 재배치 | 선택 | 선택 작업 B04의 원본 근거 |
| W06 | 변경 의존성에 따른 재필터 제한 | 선택 | 선택 작업 B02의 원본 근거 |
| W07 | 상속 태그 context의 재귀 전달 | 기존 유지 | bulk inherited tag context가 이미 있음. MCP의 추가 비용은 별도 후보. |
| W08 | 오래된 필터 작업 취소·교체 | 기존 유지 | 최신 작업 교체/취소가 이미 있음. 취소 지연만 해당 경로에서 계측. |
| W09 | 변경 요청 중복·조상 packing과 FIFO | 계약 유지 + Mac 개선 | packing/FIFO는 유지. 추가 이득 후보 B08은 Mac index 선택이며 원본 trie 복제가 아니다. |
| W10 | repaint 병합·간격 조절·가려진 창 생략 | 선택 | 선택 작업 B06의 원본 근거 |
| W11 | layout/paint 분리와 표시 재귀 제한 | 선택 | 선택 작업 B04의 원본 근거 |
| W12 | palette 포인터 캐시와 명시적 무효화 | 기존 유지 | 현재 UI palette key 캐시가 이미 있음. |
| W13 | 문자열 치수 memoization | 선택 | 선택 작업 B05의 원본 근거 |
| W14 | 지속 tooltip 객체와 dirty rebuild | 선택 | 선택 작업 B05의 원본 근거 |
| W15 | 노드 재활용 pool과 busy 참조 제외 | E01 선행 평가 | node/page/scratch 후보별 allocation 이득·reader 격리·보유 메모리를 비교해 채택한다. |
| W16 | 상한 있는 스캔 스레드 pool·event 대기 | E02 선행 평가 | blocking I/O 실행·worker 재사용·프로세스 전체 admission을 따로 측정한다. 원본 cap은 Mac 기본값으로 복사하지 않는다. |
| W17 | OS 디렉터리 열거의 큰 버퍼 경로 | 이번 적용에서 보류 | Windows LARGE_FETCH를 macOS에 직접 적용할 수 없다. bulk metadata의 실제 I/O 실험이 먼저다. |
| W18 | 경로 segment 저장·필요 시 full path 조합 | 이번 적용에서 보류 | path 저장 메모리는 줄 수 있지만 full path 조합·tag lookup·rename 비용이 증가할 수 있는 큰 구조 변경이다. |
| W19 | 파일 stream에 순차 export | 선택 | 선택 작업 B07의 원본 근거 |
| W20 | 확대 bitmap 재사용과 옵션별 재렌더 | 이번 적용에서 보류 | bitmap을 보유하면 메모리/품질/전환 의미가 달라질 수 있다. 현재 사용자 요청 rect animation을 유지한다. |
| W21 | 기존 filtered TM 노드 보존·차이만 생성/제거 | 선택 | 선택 작업 B03의 원본 근거 |
| W22 | 감시 buffer/event 재사용·batch 직접 변경 | 이번 적용에서 보류 | FSEvents는 Windows notify record의 old/new 쌍·metadata를 동일하게 주지 않는다. 직접 mutation 복제는 누락 위험이 있다. |
| W23 | 열거 metadata 재사용·조건부 추가 size query | 이번 적용에서 보류 | 현재 lstat 결과는 여러 필드에 재사용한다. 열거 metadata로 치환하려면 할당량·identity·시각/속성 보존과 I/O 측정이 필요하다. |
| W24 | 필터 조건 사전 분류·숫자 변환·빠른 조건 판정 | 기존 유지 | 조건 사전 파싱/분류는 이미 있음. |
| W25 | 사각형·가시성으로 계층형 hit-test 가지치기 | 이번 적용에서 보류 | hit-test hotspot과 visible item 수가 아직 계측되지 않았다. 현재 flat hit보다 이득이 확인되면 다시 선택한다. |
| W26 | 동일 FS 노드의 중복 스캔 진입 방지 | 이번 적용에서 보류 | root actor/task/generation으로 이미 수명을 관리한다. bit guard/Sleep loop 복제의 추가 이득이 확인되지 않았다. |
| W27 | 설정 객체 lazy 생성·메모리 재사용 | 이번 적용에서 보류 | 현재 없는 Windows XML load 경로를 위한 cache는 제거할 비용이 없다. 설정 기능 도입 시 검토한다. |
| W28 | SNS 입력의 record 단위 stream 읽기 | 이번 적용에서 보류 | mapped-if-safe 입력과 stream reader의 실측 우열이 없다. 전체 tree 저장 비용도 남는다. |
| W29 | 자식 이름 조회의 hint 주변 양방향 검색 | 이번 적용에서 보류 | hint의 locality가 Mac의 경로/순회 패턴에서도 성립하는지 미측정. binary search로 오인하지 않는다. |
| W30 | 전체 스캔과 별도 focus 재스캔 worker 경로 | 이번 적용에서 보류 | 별도 focus worker는 I/O·이전 snapshot 보유·중복 작업을 늘릴 수 있다. 반응성 이득과 자원 비용부터 측정한다. |

선택의 기반은 원본의 작업 축소 계약이며 성능·메모리 개선은 Mac에서 별도로 확인한다. API/구조 차이 때문에 원본과 자료구조가 다르다는 이유만으로 미구현 항목 전부를 복제하지 않는다. 이번 작업은 실익 후보 추출과 우선순위 정리이며 배포 앱 변경은 포함하지 않았다.

2026-11-09 후속 적용: E01의 private context 재사용과 E02의 ScanAdmission/ScanWork를 구현했다. [실제 할당·상한 비교·회귀](SCAN_RESOURCE_VALIDATION.md)를 참조한다. 두 평가 전체와 node/page pool·ArtifactWorker 격리가 완료된 것은 아니다.

2026-11-09 artifact 후속: B07 순차 SNS/TXT 출력·한 번의 판정·transaction과 ArtifactWorker I/O 이관을 구현했다. [바이트/메모리/오류 검증](ARTIFACT_STREAMING_VALIDATION.md)을 참조한다. 나머지 B03~B06/B08 및 node/page pool 전체는 별개다.


2026-11-09 B08 후속: 작은 큐 배열과 큰 큐 압축 경로 인덱스/FIFO를 구현했다. 기존 배열 oracle과 연산별 대조, idle arena 해제, 순차 5쌍 성능 측정을 완료했다. [실측과 메모리 교환관계](REFRESH_QUEUE_VALIDATION.md). 후속 [수명·취소 검증](REFRESH_LIFECYCLE_VALIDATION.md)까지 통과해 B08은 검증 범위 완료로 체크했다. deep byte/RSS 반환량·장시간 부하는 별도다.


2026-11-09 B05 후속: AX element 재사용·ID 재검증·500개 후보 조기 중단만 채택했다. [구성 요소 실측](ACCESSIBILITY_CACHE_VALIDATION.md). text/font/tooltip/전체 frame 및 VoiceOver 종합 검증은 남아 B05 전체는 부분 진행이다.


B05.04 후속: native tooltip 등록 영역 수명과 content 조회를 분리했다. [정지/이동 구성 요소 비교](TOOLTIP_REGISTRY_VALIDATION.md). W14는 원본 bitmap cache 동일 구현이 아닌 플랫폼 대체로 분류한다.

2026-11-09 최종 평가 후속: 위 문단들은 단계별 중간 기록이다. 현재 B01~B08 및 E01/E02는 각 검증 범위에서 완료했고, native Space/부분·완전 가림 matrix까지 포함해 실행 체크는 116/116이다. [150 kernel 표본·실제 창 각 200회·2500 render frames·allocation·수명·126 TSAN](FINAL_OPTIMIZATION_VALIDATION.md), [SRP 실제 소유자](OPTIMIZATION_MODULE_DESIGN.md)를 따른다. page/node pool은 측정에서 비용이 증가해 미채택했으며 private scratch와 bounded native admission만 채택했다. 이 결정은 원본 30개 기법 전체 구현이나 Windows 실제 동등성 완료를 의미하지 않는다.
