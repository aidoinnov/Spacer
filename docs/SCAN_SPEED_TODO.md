# 분석 속도 개선 TODO

작성일: 2026-11-19. 목표는 전체 분석 완료 시간과 큰 사용처를 처음 파악하는 시간을 줄이는 것이다. 아래는 실행 계획이며 생산 앱에 적용 완료한 목록이 아니다.

근거: [disktree 비교·정체 원인·원시 측정](validation/disktree-2026-11-19/README.md), [기존 streaming 후보 성과](PROGRESSIVE_SCAN_RESULTS.md), [상세 테스트 계획](PROGRESSIVE_SCAN_TEST_PLAN.md).

## A++ 품질 목표: 책임·응집도·검증

사용자 요구인 A++ 수준은 아래 설계·정확성·성능·수명 gate를 모두 충족하는 목표로 사용한다. 문서 작성이나 파일 분리만으로 달성했다고 표시하지 않는다. 기존 [단일 책임 모듈 설계](OPTIMIZATION_MODULE_DESIGN.md)를 확장하며, 새 framework나 병렬 서비스 계층을 중복 도입하지 않는다.

단일 책임은 **변경 이유와 소유 상태**로 판단한다. 정책의 판단 로직이 여러 계층에 중복되면 응집도가 부족하고, 서로 다른 정책 변경이 한 클래스에 집중되면 책임이 과하다. 하나의 기능 변경이 명시한 계약을 따라 여러 계층에 전달되는 것은 허용한다. 같은 수명·불변식을 가진 데이터와 연산은 함께 둔다. 이름만 다른 wrapper나 단일 호출 전달용 객체는 만들지 않는다. 아래 이름은 목표 역할이며 모두 별도 파일·protocol·Swift package로 만들라는 뜻이 아니다.

### 책임과 상태 소유권

| 역할 | 유일한 변경 이유·소유 상태 | 입력 → 출력 | 맡기지 않을 일 |
|---|---|---|---|
| `DirectoryReader` | OS 열거·metadata decoding 규칙; worker의 FD·batch buffer·cursor | directory request → 검증된 entry batch·구조화 오류 | UI 갱신, 조상 합산, 전역 작업 순서, 캐시 저장 |
| `ScanRetryPolicy` | 오류별 재시도 허용 규칙; 가변 전역 상태 없음 | errno·시도 수·남은 budget → 중단/다음 시도 결정 | 직접 sleep·OS 호출, 오류 누락, 재스캔 scope 선택 |
| `ScanScopePolicy` | 볼륨·mount·alias 포함 규칙; 실행 시작 시 고정한 범위 정보 | root identity·entry/boundary → 포함/제외와 이유 | 크기 추정, worker 시작, 화면 표시 |
| `DirectoryWorkScheduler` | 실행 내 병렬도·공정성·backpressure; 대기/실행 job·예산·우선순위 | 발견한 directory job·완료/취소 → 다음 허용 job | node 변경, snapshot 직렬화, errno 해석 |
| `ScanBuilder` | 하나의 실행에서 관측 결과를 tree로 조립하는 규칙; node ID·부모 관계·상세 가변 상태 | 수락한 batch·directory 완료 → 일관된 partial/final tree | 파일 직접 읽기, worker 정책, AppKit 표시 |
| `SubtreeAccounting` | 파일 기여·분기 합산의 수학적 규칙; 합산 상태는 builder 내부 소유 | 파일 기여/변경·완료 경계 → 합계 변화 | 자체 worker/lock, 두 번째 전체 트리, OS metadata 조회 |
| `OverviewAccumulator` | 제한된 개요 집계 규칙; bucket·top-K·발견량·미확인 상태 | 동일한 수락 batch → 작은 immutable overview | 상세 node·전체 path 목록 복제, 삭제 가능한 파일 목록 판정 |
| `ScanPublicationPolicy` | 중간 발행 빈도·비용 상한; 마지막 발행 시각·크기·sequence | 진행 변화·시계 → 발행 여부 | I/O·합산, UI draw 실행, 완료 상태 독자 확정 |
| 실행 coordinator | 한 실행의 시작/종료·결과 수락; run ID·취소·in-flight 수·중복 batch 확인 | scheduler/reader 결과 → builder와 overview에 동일한 수락 이벤트 전달 | 저수준 parser, 필터 계산, 영속 캐시 형식 |
| `SummaryCacheStore` | 요약 캐시 형식·transaction·용량 상한; 파일 수명 | 명시한 cache key와 완결 summary → load/save 결과 | 실제 재검사·FSEvents 신뢰성 판정, UI 상태 변경 |
| `ChangeCheckpointPolicy` | 변경 이력의 유효성·복구 규칙 | volume identity·checkpoint·event/loss → 검증 범위/재검사 계획 | 캐시 파일 직접 쓰기, event만으로 파일 존재 확정 |

`SubtreeAccounting`은 우선 builder의 순수 helper로 둔다. `ScanRetryPolicy`와 `ScanScopePolicy`도 작은 value type/함수로 충분하면 그대로 사용한다. 실행 coordinator는 모든 기능을 흡수하는 새 거대 객체가 아니라, 소유자들을 구성하고 결과 수락·종료를 조정하는 경계다.

### 기존 구조와의 연결

- `ScanService`는 root 공유·구독·watch·공개 revision 수명을 계속 소유한다. UI/MCP의 동일 root 스캔을 별개 엔진으로 분기하지 않는다.
- `ScanWork`는 full/scoped 실행 결과와 기존 snapshot의 교체·병합을 담당한다. batch parser나 worker queue를 넣지 않는다.
- `DiskScanner`는 기존 public API를 유지하는 진입점으로 남긴다. V01은 retry 결정만 먼저 분리하고, V02/V03에 필요한 실행 경계만 점진적으로 추출한다.
- 현재 `ScanAdmission`의 permit 단위는 **전체 scan operation**이다. 이를 directory job permit으로 재사용하지 않는다. V03에서는 scan 접수 상한과 프로세스 전체 directory I/O 상한을 별도 단위로 정의한다. coordinator가 I/O permit을 보유한 채 child 결과를 기다리지 않도록 하며, 실제 blocking read 작업만 I/O permit을 소비한다. 실행별 scheduler는 전체 I/O 예산 내에서 자신의 active 상한을 지킨다. 여러 root가 동시에 실행돼도 총 worker·FD·queued bytes 상한을 넘지 않는지 검증한다. 기존 admission의 변경/유지 선택과 이유는 V03 설계 산출물로 남긴다.
- `ScanStore`는 UI intent와 상태 반영만 담당한다. filesystem retry·분기 우선순위·집계·cache 판단을 수행하지 않는다. `ProjectionSession`의 계산과 무효화 책임은 유지한다.
- `DirectoryMonitor`는 OS 이벤트 수집 adapter다. checkpoint 복구 정책·캐시 저장·tree mutation을 callback에 넣지 않는다.
- Core → UI/Automation 역의존, 역할 간 순환 참조, 새 mutable 전역 backend 선택기를 도입하지 않는다. clock/reader/executor 같은 외부 경계만 필요할 때 주입한다.

### 데이터 흐름과 불변식

1. 실행 시작 시 root/volume identity·scope 정책·run ID를 고정한다. 설정 변경은 새 실행으로 처리한다.
2. scheduler가 예산 내 directory job을 내보내고 reader가 bounded batch를 만든다. blocking I/O와 retry 대기는 MainActor 및 Swift cooperative executor를 점유하지 않는다.
3. batch에는 run ID, directory job ID, enumeration attempt ID, batch sequence, 결과/오류를 붙인다. OS buffer를 가리키는 pointer는 reader 호출 밖으로 넘기지 않는다. `Sendable` 값의 소유권과 재사용 시점을 명시한다.
4. 단일 결과 수락 경계가 stale/중복 여부를 확인한 후 builder와 overview에 같은 이벤트를 적용한다. 두 집계가 각자 batch를 중복 제거하거나 서로 다른 오류 정책을 갖지 않는다. 메모리 큐를 무한히 쌓지 않고 cancellation-aware backpressure를 적용한다.
5. directory의 자신의 열거 종료와 모든 child job 종료가 확인돼야 해당 분기를 완료한다. 열거 오류는 불완전 상태로 남기고, 읽지 못한 영역을 0바이트로 확정하지 않는다.
6. UI에 발행한 partial은 이후 mutation으로 바뀌지 않는다. overview·tree·heartbeat는 run/source identity를 공유하되 각 공개 sequence/revision을 구분한다. 개요의 관측 합계와 상세 projection 시점 차이를 숨기지 않는다.
7. 취소는 신규 job 접수를 중단하고 queued 결과를 폐기·in-flight FD/buffer/permit을 정리한다. 완료 통지는 정확히 한 번이다. 즉시 interrupt할 수 없는 OS 호출은 호출 종료 뒤 결과를 차단하고 측정 한계를 기록한다.
8. 캐시는 완결 데이터만 atomic commit하며 identity·schema·checkpoint를 함께 검증한다. 요약 캐시는 이전 개요를 표시하는 용도다. 상세 증분 복원에는 별도로 완결 상세 baseline과 per-scope 상태가 필요하며, baseline이 없으면 상세를 다시 스캔한다. 오래된 summary는 이전 결과로만 표시한다. 변경 이벤트 유실과 저장 실패는 명시적 재검사/캐시 미사용으로 복구한다.

### 재검토에서 보강한 실패·용량 계약

- **batch exactly-once와 관측 최신성은 다르다.** 동일 batch의 재전송 차단은 `(run, job, attempt, sequence)`로 정의한다. bulk 후속 실패→POSIX fallback의 같은 이름 재등장은 파일 identity와 변경 경합까지 고려한다. 기존 `Set<String>`만으로 삭제/재생성·rename 후 관측값이 최신임을 보장하지 못한다. 변경 감지된 분기는 dirty로 남겨 재검사하고, 안정화 뒤 독립 oracle로 수렴해야 한다. 마지막으로 읽은 값이 단일 시점의 원자적 파일시스템 snapshot이라는 주장은 하지 않는다.
- **부분 scan의 취소와 완료된 baseline을 대체하는 rescan 취소를 구분한다.** 현재 `ScanWork`의 기존 완결 결과 보존 계약을 유지한다. 오류 완료·정상 완료·취소를 구별하고 error count와 저장된 최대 500개 상세 목록을 같은 수치로 취급하지 않는다.
- **공정한 순회는 resumable reader가 전제다.** directory 하나를 끝까지 읽고 나서만 yield하면 초대형 단일 폴더에서 V05를 충족하지 못한다. batch/page 단위 cursor를 pause/resume하는 방법, cursor별 FD 수명, FD 예산 소진 시 정책을 V03/V05에서 결정한다. 매 yield마다 처음부터 다시 읽는 방식은 금지한다. 현재 POSIX의 전체 이름 수집·정렬도 이 관점에서 비용을 비교한다.
- **개요 top-K 정확성·메모리 계약을 먼저 고정한다.** 후보 분기의 누적량을 버리면 뒤늦게 큰 분기가 되는 항목을 놓칠 수 있다. bounded bucket+overflow 개요와 정확한 전체 top-K를 같은 기능으로 취급하지 않는다. 디렉터리별 누적량을 builder가 보유하고 개요가 참조하는 방식 또는 명시적인 근사 개요 중 하나를 선택해 eviction·오차·오버플로 표시를 검사한다. 정확성 목표가 안 나오면 표본 수를 늘려 성공으로 덮지 않는다.
- **순서 계약은 필드 정확성과 별개다.** streaming/병렬 결과의 도착 순서로 ID를 부여하면 같은 크기 항목의 treemap·TXT·SNS 순서가 바뀔 수 있다. 외부 순서 계약을 고정하고 final canonicalization 또는 안정적 정렬 키의 비용까지 측정한다. 정렬이 끝나기 전 provisional ID가 final ID로 오인되지 않게 한다.
- **동시 파이프라인은 가정하지 않는다.** V04는 먼저 한 번의 discovery가 overview와 detail에 데이터를 재사용하는 구조를 의미한다. 별도 producer/consumer·queue는 실제 overlap 이득이 측정될 때 추가한다. queue가 필요하면 batch 수와 bytes 두 상한, 취소 중 unblock과 draining/폐기 정책을 테스트한다.
- **재시도 지연은 성능 정책이다.** V01에서 오류 분류와 시도/총대기 budget은 순수 정책으로 둔다. open/readdir/stat 단계별 errno를 즉시 캡처하고 성공·실패 구분 없이 모든 오류를 일시적 오류로 취급하지 않는다. 예상 밖 오류의 기본 행동도 정의한다. fake clock/wait seam으로 실제 sleep 없이 정책을 검사하고 native release 시험으로 종단 성과를 확인한다.

### 책임별 검증과 품질 gate

| 검증 단위 | 핵심 사례 | 통과 근거 |
|---|---|---|
| retry/scope 순수 정책 | 오류 분류·시도 상한·mount/alias 경계 | 결정 table과 경계값 테스트. 영구 오류 sleep 0, retry 총대기 budget 준수 |
| reader·parser | 필드 누락·잘린 record·후속 batch 오류·취소·실제 native entry | 독립 POSIX oracle와 필수 필드 대조, private FD/buffer 반환 |
| scheduler·수락 경계 | job 완료 순서 역전·중복/늦은 batch·queue full·root 교체 | 제어 가능한 executor로 재현, 최대 active/queued 상한·완료 1회·permit 누수 0 |
| builder·accounting·overview | 같은 발견 이벤트, 0바이트·deep/wide·partial 취소 | 독립 full scan 합계·경로 대조, 이중 합산 0, 불변 partial 보존, 개요 bucket 상한 |
| cache/checkpoint | 손상·ENOSPC·volume 재사용·event loss·재마운트 | atomic commit·이전 결과 표시·재검사 수렴 |
| UI/MCP 통합 | 실제 draw·source revision·focus/history·reader/export 동시 보유 | 정합성 검사와 실제 앱 측정. overview를 최종 상세 결과로 잘못 노출하지 않음 |

- [ ] Q01: 각 변경의 책임·상태 소유자·허용 의존 방향을 설명하고 실제 import/호출/가변 참조와 대조한다.
- [ ] Q02: 관련 정책을 한곳에 응집한다. 오류 분류·중복 수락·완료 확정·캐시 유효성 판정의 중복 구현은 0곳이다.
- [ ] Q03: hot loop의 entry마다 추가되는 actor hop·lock·반복 path 재구성·snapshot 복사의 비용을 profile로 확인한다. 실제 OS 요청에 필요한 path 1회 구성이나 취소 확인의 기존 lock을 근거 없이 금지하지 않고, batch 경계로 옮길 때의 취소 응답도 함께 검증한다. 추상화 전후 비용도 측정한다.
- [ ] Q04: queue·FD·buffer·overview·cache별 상한과 해제 시점, 모든 실패/취소/종료 경로를 검증한다. 정상·오류·취소를 모두 포함해 누수 0을 확인한다.
- [ ] Q05: 상태 소유권 없이 `@unchecked Sendable`을 추가하지 않는다. 필요한 경우 보호 대상·동기화·수명 증명과 race 회귀를 남긴다. 동시성 변경은 TSAN과 결정적 interleaving 검사 모두 수행한다.
- [ ] Q06: 미지원 API의 fallback과 기존 POSIX 비교 경로를 유지한다. 전환 조건과 fallback 비용을 결과에 포함한다.
- [ ] Q07: 해당 변경에 적용되는 field 정확성·탐색/내보내기 순서·오류 의미·성능 p50/p95·메모리·UI 회귀 gate를 통과해야 기본 동작을 변경한다. V04/V08 전용 제품 목표를 V01/V02의 출시 조건과 혼동하지 않는다.
- [ ] Q08: 각 단계는 역할 경계 추출과 동작 변경을 분리 검증한다. 이전 비교 경로·표본·실패 로그를 보존하고, 미완료 항목을 전체 완료로 표시하지 않는다.

설계 검토 gate Q01/Q02는 각 V 작업에 선행한다. V01에 필요하지 않은 scheduler/cache 계층까지 먼저 만들지는 않는다. 새 역할은 실제 변경 축·수명·검증 경계가 생기는 단계에서 추출한다. 정확성·취소·소유권을 위한 필수 경계와 성능 실험을 구분한다. 필수 경계는 성능 회귀 예산 안에서 채택할 수 있고, 선택적 성능 추상화는 이득이 없거나 비용만 증가하면 채택하지 않는다.

## 현재 확인한 병목

- 실제 실행 앱의 scanner 샘플에서 접근 실패 후 재시도 대기가 관측됐다. 스캔 진행은 계속됐지만 지도 revision 갱신과 시점이 달라 정체처럼 보였다.
- 접근 불가 임시 폴더 20개 비교에서 우리 POSIX 경로 중앙값 약 2.18초, disktree 1 worker 약 3.8ms였다. 각 3회 재현한 제한된 표본이다.
- 일반 파일 2만 개/200폴더 비교 중앙값은 우리 POSIX 64.7ms, streaming 후보 45.4ms, disktree 4 workers 12.0ms였다. 각 5회, 공유 호스트·warm/unknown cache의 엔진 측정이며 GUI나 전체 볼륨 성능이 아니다.
- 우리 streaming backend는 실험 코드로 존재하지만 기본값은 POSIX다. 기존 실측에서 일부 p95 회귀와 통합 검증 미완료가 있어 기본 채택을 보류했다.

## 우선순위와 완료 조건

| 순위·ID | 개선 | 구현 방향 | 완료 조건 |
|---|---|---|---|
| 1 · V01 | 권한 오류 재시도 분류 | EACCES/EPERM/ENOENT/ENOTDIR 등 재시도로 해결되지 않는 오류는 즉시 기록. 일시적 오류만 제한적으로 재시도 | 접근 불가 20폴더 release 시험 p95 ≤200ms, 오류 누락·완료 오표시 0, 취소·삭제 경합 회귀 통과 |
| 2 · V02 | 메타데이터 배치 조회 | 기존 streaming 후보의 `getattrlistbulk` 처리 검증 확대. 후속 batch 실패 시 재발견 항목 중복 방지. worker별 buffer 재사용 평가 | wide 경계·필드별 정확성·fallback 검사 통과. stat/bulk 호출 수와 CPU/RSS/시간 전후 보고, 기존 POSIX 대비 p95 회귀 gate 통과 |
| 3 · V03 | 폴더 단위 병렬 스캔 | 1/2/4 worker 비교. worker는 bounded batch를 반환하고 단일 builder가 트리를 갱신. scan admission과 I/O permit 분리, 큐·FD·bytes 상한 설정 | 분기 입력에서 유의한 개선, flat/깊은 입력 회귀 기준 준수. 오류·취소·root 교체·다중 창 및 TSAN 통과 |
| 4 · V04 | 경량 개요와 상세 트리 분리 | bucket/overflow 또는 정확한 top-K의 상태·메모리 계약을 먼저 고정. 상세 builder와 발견 metadata 공유, 별도 전체 재스캔 없음 | 실제 draw 기준 첫 유용한 개요 p50 ≥50%, p95 ≥30% 단축 목표. 미확인/이전/현재/완료 상태 구분, 중복 합산 0 |
| 5 · V05 | 분기별 공정한 탐색 | 폴더·batch별 처리 예산, 선택 scope 우선 처리, 나머지 분기의 starvation 방지 | 큰 분기 앞/뒤 순서·90% 편중 입력에서 top-k recall·byte error·최대 대기시간 보고, 전체 완료 회귀 없음 |
| 6 · V06 | 노드·문자열 메모리 축소 | full path·문자열 identity 중복과 날짜/속성 보유 비용 계측. 이름+부모 관계 및 필요 시 경로 복원 평가 | 같은 입력에서 peak RSS·할당 감소를 실측. 경로 identity·rename·필터·SNS/TXT·MCP 조회 회귀 0 |
| 7 · V07 | 분기 완료 시 합산 | 파일마다 모든 조상에 delta를 전파하는 경로와 bottom-up/완료 분기 합산 비교. 개요 집계는 별도로 제한 | 깊이·분기별 CPU/시간 개선, 중간/최종 합계 일치, 0바이트·취소 부분 결과·변경 수렴 검증 |
| 8 · V08 | 이전 결과·변경분 재검사 | V08a 요약 캐시→이전 개요. V08b 완결 상세 baseline+checkpoint→변경 scope 재검사. baseline 부재·event loss·손상·재마운트 시 full scan | V08a 캐시 개요 p95 ≤500ms. V08b 상세 baseline이 있는 10만 파일/1% 변경에서 수렴 p95 ≤5초 목표. stale 완료 오표시 0, ENOSPC 복구 |

## 별도 필수 계약: 볼륨 범위

- [x] V00 구현: 선택 볼륨 기본 / GUI·CLI·MCP 다른 볼륨 포함 옵션. mode별 root cache와 원래 root에 고정한 부분 재검사.
- [x] System/Data firmlink와 직접 Data alias, 실제 두 중첩 HFS+ mount, 직접 mounted root 선택을 검증했다. 임의의 물리 dedup까지 완료한 것은 아니다.
- [x] 제외 경계는 오류와 별도인 bounded provenance로 표시한다. 범위 축소를 동일 범위 엔진 개선으로 계산하지 않는다.
- [x] 시스템 사용량·경로별 할당 합계·회수 공간을 구분한다. allVolumes는 단일 root 용량에서 합계를 빼는 SpaceAccounting을 제공하지 않는다.
- [ ] V00 기본 배포본 채택: 기본 selected의 동일-input gate는 통과, optional allVolumes/control10000 p95는107.54→124.33ms로 엄격 기준 보류. [성과·원시 근거](SCAN_SCOPE_RESULTS.md).

## 실행 순서

1. 기준선의 소스·binary hash, 입력 manifest, 권한·볼륨 범위·캐시 상태를 고정한다.
2. V01만 수정하고 재현 시험·오류/취소 회귀 및 실제 앱의 해당 병목을 검증한다.
3. V02를 단독 비교한 뒤 V03을 1/2/4 worker로 비교한다. V00 범위 정책도 이 전에 확정한다.
4. V04는 V02의 batch 경계만으로 단일 worker에서도 먼저 구현·비교할 수 있다. V03 병렬화와 묶어 측정하지 않는다. V05의 폴더 간 공정성은 V03 scheduler에서, 초대형 폴더 내부 yield는 resumable reader/FD 계약을 확정한 뒤 구현한다.
5. V06/V07은 계측에서 실제 비용이 확인된 부분부터 독립 적용한다.
6. V08a 요약 복원과 V08b 상세 baseline 기반 증분 갱신을 분리해, 첫 실행·이전 결과 표시·현재 재검증 지표를 따로 검증한다.
7. 채택 후보만 통합하고 release 앱·UI·관련 회귀를 검증한 뒤 패키징한다.

## 단계별 필수 산출물과 출시 gate

| 단계 | 설계/구현 산출물 | 기본 적용 조건 |
|---|---|---|
| V01 | errno 결정표, 기존 재시도와의 Mac 정책 차이, pure policy·native 재현·취소 로그 | 정상 입력·오류 의미 보존, 권한 오류 open 시도 1회/대기 0, 절대/상대 지연 목표 검증. V04 개요·V08 캐시는 V01 출시에 필수 아님 |
| V02 | parser/reader 소유권, fallback 및 재열거 경합·정렬 계약, API 호출·메모리·엔진/UI 회귀표 | 해당 backend의 정확성·자원·p95·탐색/내보내기 계약 통과. 별도 전체 개요 50% 목표와 분리 |
| V03/V05 | 두 permit 단위·acquisition 순서, worker/FD/queue bytes 상한, cursor 수명·공정성, 제어된 순서 역전/취소 시험 | 모든 root 합계 상한·deadlock/누수 0·TSAN·분기 성능 및 단일 폴더 회귀 검사 |
| V04 | 개요 집계 의미·source/revision·상세 전환, actual draw 계측·출처 표시 | 실제 첫 유용한 개요 개선 목표와 최종 합계/상세 지연·RSS gate 통과 |
| V06/V07 | 모델/합산 변경 전후 메모리·복잡도, full/scoped/partial/export oracle | 필드·순서·기존 baseline 보존과 관련 성능 gate 통과 |
| V08a/V08b | 별도 schema·cache key·baseline 보관 비용·checkpoint 시작/commit 경계 | 과거 표시와 현재 수렴 분리, 이벤트 gap/유실·중단 commit·손상·ENOSPC 복구 |

V01의 오류 분류 변화는 기존 Windows식 10회 재시도와 다른 Mac 정책임을 기록한다. V00의 새 볼륨 모드를 V01과 동시에 기본 적용하지 않는다. 속도 차이의 원인이 오류 대기인지 범위 축소인지 분리해 측정한다. 첫 실행 latency 목표는 V04, 재실행 cache 목표는 V08의 책임이며 모든 V 작업을 불필요하게 묶는 출시 조건으로 사용하지 않는다.

## 공통 정량 검증

- [ ] 작은 입력, 작은 파일 다수, wide 4,095/4,096/4,097/4,100/100,000개, 깊은 트리, 큰 파일 방문 순서 역전, 불균형 분기를 비교한다.
- [ ] 접근 거부·사라진 폴더·중간 batch 오류·미지원 API·취소·변경 경합·다중 창을 검사한다.
- [ ] hardlink/symlink/sparse/clone/resource fork/Unicode/숨김/0바이트의 기존 집계 계약을 보존한다.
- [ ] 실제 GUI의 첫 유용한 개요 시간과 엔진 callback 시점을 구분해 기록한다.
- [ ] 완료 시간·첫 개요·선택 scope 응답·취소 응답의 p50/p95, CPU seconds, peak RSS, I/O 호출·재조회 수를 보고한다.
- [ ] 후보별 5 alternating pairs로 탐색하고 핵심 성능 셀은 최소 20 valid pairs와 paired 95% CI로 판정한다.
- [ ] S02~S07 총시간 p50/p95 회귀 ≤10%, peak RSS p95 ≤max(기존×1.10, 기존+32MiB)를 적용한다. 작은 입력 예외·세부 정의는 기존 테스트 계획을 따른다.
- [ ] timeout/OOM/crash/불일치·skip을 분모에서 숨기지 않는다. CI가 기준을 걸치면 보류한다.
- [ ] 디스크 여유와 실제 backing filesystem reserve를 확인하고 own fixture만 생성·정리한다.
- [ ] 성과표에는 입력·범위·전후 수치·표본 수·CI·실패/보류 사유·raw 링크를 남긴다.

## 체크 상태

- [x] 비교 앱 소스·Mac 배포본 다운로드 및 checksum 확인
- [x] 고정 Core 버전의 일반 파일 40회·접근 거부 6회 비교
- [x] 실제 앱의 진행 상태·worker stack으로 정체 원인 확인
- [x] 개선 순서와 정량 완료 조건 문서화
- [x] V00 볼륨 범위 계약 확정·후보 검증. 기본 배포본 채택 보류는 별도 추적한다.
- [x] V01 권한 오류 재시도 개선·관련 레거시 정리, 전체 Swift 260개(1 skip)/실패 0 및 TSAN 20개 통과
- [x] V01 V2 전후 100 pairs/입력 비교: 권한 오류 p50 2301→56ms, p95 137ms, 오류·합계·digest 불일치 0
- [ ] V01 기본 실행본 채택: 정상 입력 p50/p95 점 기준은 통과했지만 paired CI 하한 -14.5%가 -10% 경계를 넘어 보류. [성과표](SCAN_SPEED_RESULTS.md) 참조
- [x] V02 ordered 배치 조회·device별 local APFS 정책·정렬/내보내기/경합·예산 검증 구현
- [x] V02 V4 단독 비교: 8개 입력의 정확성·지연·CPU/RSS gate 통과. Swift269개(1 skip), TSAN44개 실패0. [성과표](SCAN_BULK_RESULTS.md)
- [ ] V01+V02 기본 배포본 채택: 이전 앱 대비 small1000 p95 8.52→10.26ms(+20.4%)로 엄격 기준 보류. V02 단독 통과와 구분한다. 20+사전 고정80 pairs를 모두 보존했으며 같은 후보를 성공할 때까지 재측정하지 않는다.
- [x] V03 제한된 폴더 병렬화 구현·엔진 검증. 기본 적용은 7개 입력 비교의 회귀로 보류한다.
- [x] V04 bounded snapshot 개요·상세 공유 pipeline·실제 native draw20회 측정
- [ ] V05 공정한 순회·선택 scope 우선순위
- [ ] V06 메모리 축소 평가·채택
- [ ] V07 합산 비용 축소 평가·채택
- [ ] V08 캐시·증분 재실행
- [ ] 통합 회귀·실제 앱 검증·패키징

## 재검토 기록

2026-11-19 문서 재검토에서 다음 설계 결함을 보완했다. 코드 구현 완료·성능 목표 달성을 뜻하지 않는다.

- [x] scan operation admission과 directory I/O permit 단위를 구분하고 중첩 대기 위험 명시
- [x] 요약 캐시와 상세 baseline 기반 증분 복원 분리
- [x] whole-directory callback을 bounded batch로 정정하고 pause/resume cursor·FD 의존성 추가
- [x] 중복 batch 차단과 삭제/재생성·rename 뒤 현재값 수렴을 분리
- [x] bounded overview와 정확한 top-K의 메모리/정확성 충돌 및 final 순서 계약 추가
- [x] 책임 분리의 파일 수 과대해석·entry별 비용 전면 금지·선행 전체 구조 개편을 수정
- [x] V04의 단일 worker 선행 실험 허용, 작업별 출시 gate와 실제 산출물 연결
- [x] V01 errno 결정표·허용 대기 budget·native fixture 범위 확정: EINTR 즉시, EAGAIN/EBUSY/ETIMEDOUT만 10ms, 최대 3회 open/요청 대기 합계 20ms; 나머지는 즉시 실패. 20개 native denied 폴더+읽기 가능한 sibling과 정상 1만 파일을 before/after 비교한다.

## V01 구현 진행과 관련 레거시 정리

- 오류 분류는 `ScanRetryPolicy`, POSIX open/readdir/close와 errno 보존은 `POSIXDirectoryReader`, 취소·대기 해제는 `ScanControl`이 소유한다. reader는 가변 tree나 UI에 의존하지 않는다.
- scanner 내부의 모든 오류 10회 재시도·고정 sleep·`lastError!` 경로를 제거했다. POSIX 기본 스캔과 bulk fallback이 같은 reader를 사용한다.
- 재시도 범위를 directory open으로 제한한다. 이미 읽기 시작한 디렉터리의 readdir 오류는 자동 처음부터 재실행하지 않고 기존 오류 의미를 보존한다.
- 실제 비교에 필요한 POSIX/bulk/streaming backend와 과거 source archive는 보존한다. 사용 중인 실험 경로와 재현 기준선을 무차별 삭제하지 않는다.
- 구조 추출·동작 변경·정확성·취소·동시성 및 전후 벤치마크를 검증했다. [성과표](SCAN_SPEED_RESULTS.md)와 [원시 검증 기록](validation/scan-retry-2026-11-19/README.md)을 따른다. 정상 입력 latency의 신뢰구간이 채택 경계와 겹쳐 전체 채택은 보류하며, 현재 실행 앱을 자동 교체하지 않는다.

### V01 책임·레거시 감사 결과

| 항목 | 실제 반영·근거 |
|---|---|
| Q01/Q02 | retry 결정표는 ScanRetryPolicy 한 곳, POSIX open/read/close는 POSIXDirectoryReader 한 곳. 기존 Scanner의 중첩 children 함수 제거 |
| Q03 | 첫 후보의 hot NSCondition 변경은 철회. 기존 hot NSLock 유지, retry condition 분리. 중복 NSError.localizedDescription 계산 제거. 두 후보의 실측 모두 보존 |
| Q04/Q05 | open 성공/실패·read 오류·취소 FD 종료·대기 취소·1000 terminal callbacks·stale generation 검사. TSAN 20개 통과. 기존 @unchecked Sendable 추가 없음 |
| Q06/Q07 | POSIX/bulk fallback 공통 reader, full/scoped/partial·필터·SNS/TXT 회귀 포함 260개. latency CI 기준 미확정은 그대로 보류 |
| Q08 | 수정 중 빌드한 잘못된 기준선은 제외 후 고정 source archive에서 재빌드. 초기 timeout·loader 오류·V1 gate 실패·V2 전체 100 pairs raw 보존 |

과거 성능 자료·분석 대상 소스·실험 backend는 재현에 사용 중이므로 삭제하지 않는다. V02 채택 이후 폐기할 backend와 benchmark 전용으로 남길 경로를 별도 판정한다. 이번 완료는 V01 구현/검증이며 전체 A++ 목표·V00/V02~V08 완료가 아니다.

- [x] V01 후보 전용 Universal 앱/ZIP: ARM64·Intel CLI·signature·실제 GUI의 접근 오류 표시·readable sibling 집계 확인. 테스트 프로세스와 fixture 정리, 기본 앱 hash 불변.
- [ ] V01 정식 채택은 정상 입력 latency CI 보류 해소 후 결정한다. 100 pairs 결과를 성공 판정이 나올 때까지 반복하거나 기준을 완화하지 않는다.

## V02 구현·검증 결과

- [x] Q01/Q02: decoder/예산은 `NativeDirectoryMetadata`, device 선택은 `ScanMetadataPolicy`, cursor/retry는 기존 reader/policy, tree/집계는 scanner 단일 소유로 유지했다.
- [x] 정렬된 첫 이름 목록과 bulk의 raw UTF-8 이름을 대조하고, 정확한 node ID/children/TXT/SNS 순서를 보존한다. 실패 시 첫 목록을 재사용해 재열거를 줄였다.
- [x] tiny/deep 회귀는16개 최소 admission으로, wide RSS 회귀는 exact-count reserve와 검증 완료 이름 조기 해제로 수정했다. 실패 후보 소스·측정을 보존했다.
- [x] 4095/4096/4097/4100 native 경계, partial/unsupported/malformed/later failure, Unicode/flags/link/fork/sparse, 오류/취소/FD, 실제 rename 경합 후 다음 스캔 수렴을 검사했다.
- [x] V4 정량720회(기본8셀×20pairs×3변형 + small80pairs×3), 실패·불일치0. 단독V02의8셀 지연/CPU/RSS 통과. 이전 앱 small p95 미달은 별도 보류한다.
- [x] ARM/Intel Universal 후보·서명·CLI·SNS 재로드·TXT동일·GUI 오류/지도 capture·watch rename/create 수렴 검증. 테스트 프로세스와 own fixture 정리, 기존 기본 앱/사용자 스캔 유지.
- [ ] 기본 배포본 채택: strict small p95 보류. 같은 V4를 추가로 반복해 통과를 만들지 않는다. [전체 성과와 원시 근거](SCAN_BULK_RESULTS.md).
- [x] V00 범위 정책은 Scope 후보에 구현·검증했다. 기존 `/` 스캔이 NAS까지 방문하는 문제와 V02 엔진 속도 향상은 별개다.

## V03 구현·검증 진행

- [x] `OrderedDirectoryReader`가 inline/read-ahead의 이름 정렬·bulk 검증·fallback 정책을 공통 소유한다. 중복된 ordered 조회 구현을 제거했다.
- [x] 단일 builder가 node·ID·집계를 소유한다. `DirectoryReadPool`은 고정4 threads/대기24 jobs, 실행별 최대 concurrency−1개 listing을 유지한다.
- [x] directory I/O8 permits와 전체 scan operation8 admission을 분리했다. ticket 대기 중 permit을 보유하지 않으며, 완료 전에 자체 reader·FD·permit을 정리한다.
- [x] speculative 이름2048개/추정128KiB·metadata512KiB, overflow inline 복귀, 취소64 records 이내 확인·native call 전후 확인을 구현했다. allocator RSS와 native call 지연은 별도 측정한다.
- [x] ID/전체 필드/children/TXT/SNS 동일, 순서 역전, queue full·queued/active/root 취소, FD 종료·8개 master 동시 실행 회귀를 추가했다. 전체289개(1 skip)·TSAN29개 실패0.
- [x] 사전 고정100 pairs×7입력×4변형=2800회 정량 비교와 원시 결과 기반 scorecard 판정. 실행 실패·파일/크기/digest 불일치0. 4-worker의 normal10000 p50 48.65→28.96ms·paired42.33% 개선을 확인했지만 small/wide/deep 회귀로 전체 적용은 보류한다. [성과표](SCAN_PARALLEL_RESULTS.md).
- [x] 채택 후보의 실제 GUI/watch 수렴·패키징. 최종 public concurrency2, 기본 앱0.2.0 교체 완료.

[설계·소유권](SCAN_PARALLEL_DESIGN.md), [원시 검증 기록](validation/scan-parallel-2026-11-19/README.md), [재현 명령](../scripts/bench/scan-parallel/README.md).
V04 경량 개요와 V05 폴더 내부 공정 순회는 이번 read-ahead 구현에 포함하지 않는다.

## 2026-11-20 최종 채택

2026-11-20 완료: [최종 성과표](SCAN_DELIVERY_RESULTS.md). 기본 병렬도2·64 sibling 진입 조건, bounded snapshot 개요 소비·50ms 활성화·native draw 계측을 적용했다. 7입력×51쌍×3변형=1071회에서 지연/CPU/RSS/정확성 gate를 기준선과 직렬 양쪽으로 통과했다. 전체294개(1skip), TSAN34개 실패0. 최종 GUI20회 개요 draw 확인 p95 299ms,20만 파일 상세 재검사1.01초·취소·rename 감시·빈 root 교체를 검증했다. ARM/Intel CLI와 SNS/TXT, 실제 nested-volume GUI도 통과했다. Universal0.2.0/20261120.1을 기본 앱에 설치·서명 검증·실행했고 이전 앱/ZIP은 dist/releases에 백업했다. 전체 실제1TB 완료 시간 보장은 아니며, 현재 선택 볼륨 검사와 관측 개요를 사용한다.

V01/V02/V00/V03의 이전 후보 보류 기록은 역사로 보존한다. 이번 최종 gate는 고정 V00 기준과 같은 scope에서 실시했으며, 이전 production POSIX 앱·다른 장치·cold cache 전체까지 동일 성능을 보증하지 않는다. V05~V08의 나머지 계획은 별도 미완료다.
