# R15: MCP subtree 검색·cursor·취소·context 수명

2026-11-09. 이 변경은 **Mac MCP 확장**이다. Windows SpaceSniffer에 MCP나 이 cursor 구조가 있었다는 근거로 사용하지 않는다. 파일 판정은 기존 `ScanFilter.matches`와 snapshot metadata를 그대로 사용한다. 원본 filter 계약은 [engine 계약](engine-contracts.json), 실제 공개 API의 통합 명세는 [MCP API](MCP_API_REFERENCE.md)를 따른다.

## 바뀐 동작

기존 `query_nodes`는 node 배열의 `offset`부터 `budget`개를 검사한다. scope 밖 항목도 검사 수에 포함되며, 이는 기존 client의 cursor 의미다. 이 모드는 그대로 유지했다. `traversal` 생략 또는 `snapshot`은 같은 전역 array offset과 `next_offset`을 쓴다.

`traversal="subtree"`를 명시하면 scope의 child 관계만 DFS로 방문한다. 별도 전체 path dictionary나 subtree ID 배열을 만들지 않는다. 각 frame은 node ID·다음 child 위치·상속 tag mask만 보관한다. snapshot의 child 순서를 따르며 전역 array 순서와 같다는 보장은 없다. subtree 밖 node는 방문하지 않는다.

```json
{"path":"/fixture/a","traversal":"subtree","budget":1000,"limit":100}
```

응답은 기존 `revision/items/inspected_nodes/complete`와 함께 `path/order/traversal_steps/evaluated_at/next_cursor`를 반환한다. `next_offset`은 null이다. 다음 page는 `traversal="subtree", cursor=<next_cursor>`로 요청한다. `revision`도 함께 보내는 편이 좋다. scope·expression은 다음 page에서 생략하거나 같은 값을 보낸다.

`budget`은 subtree 모드에서 **node 첫 방문·edge 하강·stack 상승을 모두 포함한 traversal step 수**다. 깊은 tree의 마지막 unwind도 무제한 한 번에 하지 않는다. `inspected_nodes <= traversal_steps <= budget`, 최대 100,000이며 rows 최대 500은 별도다. 빈 page라도 next_cursor가 있으면 완료가 아니다. scope path 해석·filter parse·metadata/정규식 계산 시간이나 전체 wall time의 상한을 뜻하지 않는다.

cursor 시작 시 filter를 한 번 파싱하고 평가 시각을 고정한다. `evaluated_at`은 이 시각이다. 여러 page에 걸친 상대 시간 조건이 매 page마다 달라지지 않는다. 상속 tag는 root의 조상부터 누적한 뒤 frame과 함께 내려가며, 원래 filter와 metadata에 같은 mask를 전달한다.

## 소유권·상한·오류

`ScanStore.automationQueries`가 창별 `SubtreeQuerySession`을 소유한다. 같은 revision의 cursor들은 한 immutable QueryContext lease를 공유한다. snapshot/weights는 Swift COW 값 공유이며 재계산·깊은 복사를 하지 않는다. worker closure는 store/window를 캡처하지 않는다.

- 창당 최대 8개 cursor/page slot, cursor당 최대 4096 frame이다. reset/cancel 뒤 dictionary에서 빠진 running page도 실제 종료 전까지 slot을 차지한다. 새 cursor가 많으면 가장 오래 쉬고 있던 cursor를 evict하고, 모든 slot이 실행 중이면 `busy`다.
- 총 logical frame 상한은 32,768이다. frame payload의 상한이지 snapshot·String·regex 객체·Array allocator slack을 포함한 RSS ceiling이 아니다. 실제 source snapshot은 현재 UI와 공유한다. 반환 JSON rows는 session cache에 보관하지 않는다.
- idle 60초는 monotonic 시각으로 다음 create/checkout 때 판정하는 **논리 만료**다. 60초 뒤 실행되는 timer는 없다. 상태 조회만으로 청소되지는 않는다. 현재 UI가 다른 revision을 publish하거나 창을 닫으면 시각과 무관하게 즉시 reset한다.
- `projectionRevision.didSet`과 `ScanStore.shutdown()`에서 reset한다. idle lease는 즉시 해제하고 running page는 취소를 관측한 뒤 해제한다. 이미 발급한 다른 immutable QueryContext reader는 유효하다.
- cursor는 성공한 page에서 **소비되고 새 token으로 교체**된다. 같은 token을 다시 보내면 `stale_cursor` 또는 아직 앞 요청이 실행 중일 때 `busy`다. 네트워크 응답을 잃었을 때 같은 cursor를 무조건 재시도하면 안 된다. `query_nodes`의 `idempotentHint`는 이에 맞게 false이며 legacy offset mode의 결정적 읽기 동작은 유지한다.
- 다른 revision이면 `stale_revision`, 이미 소비/취소/만료/evict된 token이면 `stale_cursor`, token의 scope/expression 변경 또는 비영 offset 결합은 `invalid_argument`다. source NodeTable이 같은 UUID라고 주장하면서 바뀐 경우에도 continuation을 거절한다. 정상 owner는 metadata·weights·filter·focus 변경에 새 공개 revision을 발급한다.
- frame/조상 깊이 제한을 넘으면 `query_limit`이고 cursor를 정리한다. 필요하면 기존 snapshot traversal로 재시작한다. 전체 snapshot을 매 query마다 다시 validate하지 않는다. ingress에서 검증한 snapshot과 owner revision 계약을 사용한다.

## 취소 계약

`query_nodes(traversal="subtree", cursor=..., cancel_cursor=true)`는 token을 제거하고 cooperative cancellation을 전달한다. 응답은 `cancelled=true,next_cursor=null,complete=true`다. idle cursor뿐 아니라 별도 동시 IPC client가 보낸 실행 중 continuation도 취소할 수 있다. active page가 실제 끝나기 전 slot을 조기 반환하지 않는다.

`QueryExecution.run`은 부모 Task 취소를 detached read Task에 명시적으로 전달한다. 기존의 `.value` 대기만으로는 전달되지 않던 부분이다. query 진입·path child lookup·node metadata의 조상 walk·페이지 traversal에 취소 지점을 둔다. 취소는 Hub에서 `cancelled` 오류로 반환한다. revision publish/창 종료 역시 session reset을 통해 실행 중 subtree page를 취소한다.

파일 syscall/정규식 내부를 강제 중단하는 기능은 아니다. Python STDIO bridge는 한 요청씩 처리하므로 그 connection에서 처리 중인 요청을 뒤따르는 `notifications/cancelled`로 선점하는 기능이나 socket disconnect 감지는 추가하지 않았다. 현재 지원하는 취소는 owner reset, native parent Task cancellation, explicit cursor cancel이다. 다른 query 도구 전체가 subtree budget 또는 hard deadline을 가진다는 주장도 하지 않는다.

## 상태 관측

`app_status(window_id).query_session`은 `cursors/active_pages/maximum_cursors/maximum_frames_per_cursor/created/reused_contexts/evicted/cancelled`를 반환한다. reset으로 token 수가 0이 돼도 active page가 협력 종료 전이면 active_pages는 남는다. cancelled는 명시적 cursor cancel 접수 수이며 모든 원인의 worker terminal count가 아니다.

## 검증

[최종 선택 회귀 로그](validation/r15-query-2026-11-09/selected-tests-final.log)는 subtree 10개·실제 Store owner 수명 1개·기존 automation/resource 10개, 총 21개 실패 0이다. [Python protocol/schema 7개](validation/r15-query-2026-11-09/python-tests.log)도 통과했다. 포맷 loader를 병행 수정하던 시점의 compile 실패 로그와 초기 통과 로그는 덮어쓰지 않고 보존했다. 전체 TSAN/release·정식 package·실제 최신 앱 MCP는 root 통합 단계의 후속 기록을 따른다.

확인한 핵심은 다음과 같다.

- 전역 ID가 interleave된 tree에서 focused subtree 4개 node만 방문하고 기존 전체 배열 filter oracle와 결과가 일치했다. child 순서·한국어 이름·조상 tag·budget=1의 빈 page/ascend도 대조했다.
- old offset의 의미와 명시적 schema default(false 포함)를 유지했다. one-use token, scope/expression/revision/source 변경 거절, slot eviction, 접근 시 idle 만료를 확인했다.
- running/reset/new-submit 경합에서 active slot과 weak context lease가 실제 worker 종료까지 살아 있고 이후 해제됨을 native thread gate로 결정적으로 검사했다. explicit cancel도 실행 중 continuation에 전달했다.
- 부모→detached 취소와 이미 취소된 한-node offset page가 결과를 반환하지 않음을 확인했다. 실제 Store revision publish와 shutdown이 session lease를 해제하면서 이전 immutable reader는 유지됨을 weak witness로 검사했다.

실제 앱용 재현 스크립트는 [query_cursor_smoke.py](../scripts/mcp/query_cursor_smoke.py)다. 먼저 별도 QA 창에 작은 fixture를 load/scan한 뒤 사용한다. 기존 cursor client가 있는 창에서는 시작하지 않는다.

```sh
python3 scripts/mcp/query_cursor_smoke.py --bundle-id <qa.bundle.id> \
  --output <새로운-결과-폴더> --verify-revision-reset
```

기본 실행은 query/cursor 상태만 바꾸고 scan/파일 쓰기를 요청하지 않는다. `--verify-revision-reset`은 QA 창의 filter를 의미가 같은 문자열로 바꿔 새 revision을 실제 관측하고 원래 문자열로 복원한다. 코드가 존재한다는 이유로 이 실제 앱 검증을 실행했다고 세지 않는다.
