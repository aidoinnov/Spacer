# Projection·geometry·presentation 무효화 계약

원본 의미는 `engine-contracts.json`의 REA 주소·Evidence ID를 따른다. 이 표의 opaque UUID, COW proof, bounded cache 및 Swift 실행 경계는 Mac 설계다. Windows에 동일한 Swift 구현이 있었다는 주장이 아니다.

| 변경 | parse | membership / weights | navigation | sort / geometry | paint |
|---|---|---|---|---|---|
| 같은 source에서 이동·뒤로·앞으로 | 동일 문자열 재사용 | 재사용 | 추적 경로 최대 4096개, 새 경로 계층 탐색, 실패 시 전체/rename 복구 | scope·selection key 검사 | 최신 표시 |
| 선택 | 재사용 | 재사용 | 현재 identity 재검증 | 선택 경로 상세화가 바뀌므로 rectangle key 포함 | 선택 윤곽 |
| depth·bounds | 제출 불필요 | 기존 값 | 기존 값 | sort key와 별도 rectangle key | 최신 크기 |
| filter 문자열 | 새 문자열만 parse | full; 오류는 이전 유효 filter | full 결과로 복구 | 새 evaluation UUID | 최신 표시 |
| logical ↔ allocated | 재사용 | full | full 결과로 복구 | 새 evaluation UUID | 크기 label 갱신 |
| hidden | 재사용 | full, 숨김 조상 포함 | full 결과로 복구 | 새 evaluation UUID | 최신 표시 |
| own/ancestor tag | 재사용 | tag 비의존 filter는 같은 NodeTable COW 확인 후 재사용, tag 의존은 full | tag metadata와 공개 revision은 새 값 | 같은 평가일 때만 sort 재사용 | own 색·inherited tag 조회·MCP metadata는 새 snapshot |
| sparse size·mtime·atime | 재사용 | 두 source identity, 같은 topology, 변경 page 상한을 입증하면 leaf 재판정·조상 기여 갱신; 시간 상대 filter는 full | 검증된 ID만 재사용 | 값이 달라지면 새 평가 key | label·width 갱신 |
| dense size·독립 branch burst | 재사용 | page/ID 상한 초과는 full | full 결과 | 새 key | 최신 표시 |
| name/path·identity·created·flags·attributes·issue | 재사용 | full | rename/삭제 복구 | 새 key | 최신 metadata |
| 추가·삭제·topology·SNS load·시작 | 필요 시 parse | full; reset으로 이전 cache 제거 | 새 입력에서 복구 | 새 source | 오래된 geometry 승인 금지 |
| 시간 상대 조건 | 문자열 재사용 가능 | 매 요청 full | 새 시각의 결과 | 새 key | 최신 결과 |
| 숨김·최소화·occlusion·분리 | 데이터 정책 동일 | 데이터 계산 계속 | 데이터 상태 유지 | pending 취소·cache reset, 최신 intent만 복귀 때 계산 | timer·중간 presentation 정리 |
| 숨긴 창 MCP capture | 데이터 최신 상태 대기 | 동일 | 동일 | async 5초 deadline으로 최신 geometry 준비 | PNG 후 숨김 cache 정리 |

직전 evaluation을 재사용해도 `ScanStore`는 새로운 공개 projection revision을 발행한다. `QueryContext`와 artifact job은 접수 시점의 snapshot/filter/weights/revision을 값으로 고정한다. 새 page·새 tag·새 weights를 오래된 pagination revision에 섞지 않는다.

## 정렬과 rectangle의 서로 다른 key

Projection의 child order는 **Int64 내림차순, 동률 ID 오름차순**이다. Treemap은 기존 **Double 변환 후 내림차순, 동률 ID 오름차순**을 보존한다. 2^53 위 정수의 Double 동률도 oracle과 그대로 비교한다. 이 두 comparator를 합치지 않는다.

`GeometrySession`의 정렬 key는 opaque evaluation identity·parent·현재 children와 comparator 정책이며, rectangle key는 이에 root·depth·selected ID·bounds·layout 정책을 더한다. selection을 지우면 선택 경로 한 단계 상세화가 깨진다. 모든 양수 leaf는 subpixel이어도 기존 면적 계산에 참여한다. tiny chunk 표시 정책은 추가하지 않는다.

정렬은 총 65,536 child/order 슬롯과 128 parent, rectangle은 최근 두 key 합계 50,000 tile 상한이다. 저장하는 것은 UUID·ID·수치이며 snapshot을 잡지 않는다. lock은 입력/commit/reset에만 사용하고 실제 layout은 밖에서 실행한다. reset generation 이전 계산은 commit하지 않는다.

## 재사용 소유권·예산

| 단위 | 상태와 반납 조건 | 상한·eviction |
|---|---|---|
| 기존 NodeTable COW page | writer의 값 복사 → reader 공유 → 변경 page만 COW. UI transition·QueryContext·export·ScanService baseline 모두 Swift 값 reader | production에 mutable page/node pool을 추가하지 않음. reader 해제로 ARC가 회수 |
| private ancestor context | `FilterScratch` checkout → 단일 worker 사용 → 결과 배열과 분리 → idle 등록 → 다음 checkout/해제 | owner당 1 MiB; process idle charge 4 MiB, 최소 owner charge 64 KiB로 최대 64개. 초과·reset·shutdown·pressure에 폐기 |
| context pressure | idle owner는 try-lock eviction, active owner는 epoch 차이로 pass 종료 때 폐기 | warning/critical source, 2초 재보유 유예. active 및 published 배열은 idle pool cap에 포함하지 않음 |
| page/node 실험 후보 | pool 전용 class handles → checkout 때 writer lock 안에서 unique-reference 검사 → frozen reader가 있으면 제외 → reader가 없을 때만 reset/reuse | test/probe 전용, production 미연결. 모든 DiskNode 필드 교체, page의 children/string 요소 제거. 4 MiB는 allocator charge estimate이며 deep/RSS cap 아님 |
| text | 현재 path·정확한 UTF8 name·dir/link·bytes/font key만 유지. MapItem이 outgoing label 값 소유 | 4096 entries / 추정 UTF8 1 MiB. snapshot 없음; hidden/detach/close/reset 삭제 |
| tooltip / AX | 현재 id/path/rect 기준, token generation과 activation 시 현재 identity 재검증 | native region은 현재 presentation만, AX 최대 첫 500개. 종료 때 등록·객체 제거 |

단일 `PoolManager`로 서로 다른 반납 조건을 합치지 않는다. scratch만 mutable 재사용하며 membership/weights는 published reader와 독립된 값 배열이다. flat weights의 첫 변경은 배열 전체 COW를 만들 수 있어 sparse 경로도 O(dirty)라고 부르지 않는다.

## 실행·관측 경계

`ScanService` actor는 root/subscriber/generation 승인만 조정한다. `PathIO`의 native serial queue에서 canonical·exists·volume I/O, `ScanAdmission`의 최대 8개 native 작업에서 opendir/readdir/lstat 및 재시도 sleep, 별도 artifact serial queue에서 SNS/TXT read/write를 실행한다. actor/producer lock을 잡은 채 blocking I/O나 filter/layout을 실행하지 않는다. metrics도 별도 native serial queue에서 own-process Mach 상태를 읽는다.

scan pending 64, path/artifact 각각 pending 64, metrics outstanding 33, LatestWorker running 1+pending 1이다. running 취소는 작업이 실제 반환하기 전 slot을 반환하지 않는다. pending 취소/교체는 capture를 즉시 비우고 오래된 완료는 owner generation에서 거절한다. pool thread 생성/재사용은 시스템 Dispatch에 맡기며 앱이 매 요청 thread를 만들지 않는다.

`WorkerTelemetry.runs`는 기존 호출 지점 수다. submitted/started/completed/cancelled/failed/coalesced/stale/active/queue 및 duration을 별도로 노출한다. stage 최대 128개, stage별 최근 duration 256개·thread ID 32개이며 path를 key로 저장하지 않는다. duration은 monotonic이며 중첩 stage를 더해 wall time으로 사용하지 않는다. RSS·physical footprint는 현재 process, allocation은 MallocStackLogging 누적, retained charge는 pool 내부 계산이다. 서로 대체하지 않는다.
