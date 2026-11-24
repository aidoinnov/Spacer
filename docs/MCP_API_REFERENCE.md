# MCP API 상세 명세

기준: 2026-11-09, `scripts/mcp/space_sniffer_mcp.py`의 도구 20개와 `AutomationHub`/`QueryContext`의 실제 출력. 입력표는 현재 `TOOLS` 객체에서 추출했다. [카탈로그 원문](mcp-tool-catalog.json)에는 입력 JSON Schema·annotations와 bridge 소스 SHA-256을 보관한다. 아래 출력 형태는 앱 구현을 대조해 수기로 설명했으며 런타임 `outputSchema`가 제공되는 것은 아니다.

설계·보안·비용·운영은 [기술 설계서](MCP_TECHNICAL_DESIGN.md), 처음 연결은 [사용 가이드](MCP.md)를 참고한다. 예시 경로/UUID/PID는 설명용이며 실재 경로를 뜻하지 않는다.

## 공통 호출 형식

legacy 연결은 initialize와 initialized notification 후 호출한다. JSON 예시를 실제 STDIO에 보낼 때는 객체 한 개를 한 줄로 직렬화한다.

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"example-client","version":"1.0"}}}
```

```json
{"jsonrpc":"2.0","method":"notifications/initialized"}
```

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"node_info","arguments":{"instance_id":12345,"window_id":"window-uuid","path":"/example/data"}}}
```

모든 도구의 inputSchema는 object이며 알려지지 않은 필드를 거부한다. bool을 정수로 받지 않는다. 문자열은 명시적 maxLength 또는 검증기 기본값 4096자를 적용한다. maxLength는 문자 수, 전송 한도는 bytes이므로 서로 다르다.

| 공통 입력 | 타입 | 의미 |
|---|---|---|
| `instance_id` | integer >= 1, 선택 | app_instances의 PID로 앱 선택. 일반 앱 호출에서 생략 시 후보가 정확히 1개여야 함 |
| `window_id` | string, 선택 | 창 UUID. 창 도구 생략 시 key window→유일한 창 순. 글로벌 도구에서는 범위 제한에 쓰이지 않음 |

페이지를 지원하는 도구의 `limit` 기본값은 100, 범위 1~500이다. `offset` 기본값은 0, 범위 0~10,000,000이다. `revision`은 첫 응답의 값을 후속 페이지에 전달한다. schema의 default는 문서용 metadata이기도 하며 실제 기본값은 앱의 fallback 처리로 결정된다. `kind/filtered/budget/limit/offset`은 앱에도 대응 fallback이 있다.

### 결과 envelope

일반 도구 성공:

```json
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"revision\":\"r1\",\"items\":[]}"}],"structuredContent":{"revision":"r1","items":[]},"isError":false}}
```

실패는 뒤의 오류 참조를 따른다. 도구 본문은 text에 JSON으로 한 번, structuredContent에 객체로 한 번 전달하므로 메타데이터 전송량은 중복될 수 있다. 캡처는 image block을 별도로 전달한다. tools/list annotations는 일반 읽기 도구의 readOnlyHint/idempotentHint=true, 변경 도구는 false다. cursor를 소비하는 query_nodes는 readOnlyHint=true/idempotentHint=false이며 destructiveHint/openWorldHint는 false다. annotations는 권한 검사나 자동 재시도 보장이 아니다.

## 도구 참조

각 입력표는 공통 instance_id/window_id를 제외한 도구 전용 필드다. 예시 arguments에는 필요한 경우 실제 window_id와 instance_id를 추가한다. `—`는 도구 전용 입력이 없다는 뜻이다.

### 1. `app_instances` — 앱 인스턴스 발견

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| — | — | — | — |

예시 arguments:

```json
{}
```

반환: `{instances:[{pid,bundle_id,version,started_at}]}`. PID 오름차순이며 token/socket은 제외한다. 여기서 version은 descriptor 버전 1이며 앱/bridge 버전 문자열이 아니다.

bridge가 처리한다. 입력의 instance_id/window_id로 목록을 좁히지 않는다. 결과가 비면 업데이트한 앱 실행과 bundle ID를 확인한다. 앱을 자동 실행하지 않는다.

### 2. `app_status` — 앱·창 상태

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| — | — | — | — |

예시 arguments:

```json
{}
```

반환: window_id 생략: `{pid,bundle_id,version,controller_started_at,windows:[WindowState],jobs:[JobState]}`. 지정: `WindowState` 한 개.

jobs는 최근 10개다. 창 상태와 snapshot/progress의 시점 차이는 공통 모델 절을 따른다. version은 앱 버전이며 bridge 버전이 아니다.

### 3. `app_resources` — 실제 프로세스·엔진 자원

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| — | — | — | — |

예시 arguments:

```json
{}
```

반환: `{process:ProcessMetrics,engine:{cached_roots,subscribers,scan_starts,scan_limit,active_scans,queued_scans,...},workers:{stage:{runs,main_thread_runs,...}},scratch:{...},canvases:{created,released,live}}`.

현재 연결한 앱 프로세스 전체의 값이다. window_id는 무시한다. CPU는 누적 초, 캐시는 루트 개수다. 캐시 크기를 bytes로 추정하지 않는다. process 측정과 actor 통계는 원자적인 동시 표본이 아니다.

### 4. `volumes_list` — 마운트 볼륨 목록

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| — | — | — | — |

예시 arguments:

```json
{}
```

반환: `{volumes:[{name:string,path:string}]}`.

ArtifactWorker가 별도 serial I/O queue의 DesktopFileActions를 통해 mountedVolumeURLs의 skipHiddenVolumes 옵션으로 읽는다. 대기열 포화는 operation_failed로 반환할 수 있다. 순서·중복 이름 유일성을 보장하지 않는다. path로 구별한다. hidden 옵션은 UI의 show_hidden과 별개다.

### 5. `volume_info` — 파일시스템 용량

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 예 | 최대 4096자 |

예시 arguments:

```json
{"path":"/Volumes/develop"}
```

반환: `{path,total_bytes,free_bytes,system_used_estimate_bytes,accounting_note}`.

입력 경로의 파일시스템 속성을 새로 읽는다. snapshot 없이 가능하다. used estimate는 max(0,total-free)이며 pathname 합계·회수 가능 공간이 아니다. 알려지지 않은 systemSize/free 속성은 현재 코드상 0으로 대체한다.

### 6. `scan_start` — live 스캔 시작

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 예 | 최대 4096자 |
| `watching` | boolean | 아니오 | 별도 기본값 없음 |
| `replace` | boolean | 아니오 | 기본 `false` |
| `legacy_code_page` | integer | 아니오 | 원본 Windows ANSI page 1~65535, 비ASCII v2에 필요 |
| `root_index` | integer | 아니오 | 0부터 시작, 복수 최상위 루트일 때 필수 |
| `inspect_only` | boolean | 아니오 | 기본 false, 창 변경 없이 roots metadata job 반환 |

예시 arguments:

```json
{"path":"/example/data","watching":false}
```

반환: `{accepted:true,window_id,scan_session_id,path}`.

path는 존재하는 macOS 디렉터리여야 한다. watching 생략 시 현재 창 요청값을 유지한다(새 store 기본 true). 이미 스캔 중이면 replace=true가 필요하다. 입력 검증 뒤 busy를 다시 확인한다. 완료·새 디스크 순회·감시 활성화를 보장하는 응답은 아니다. 같은 루트의 공유 캐시를 받을 수 있다.

### 7. `scan_stop` — 스캔 취소 요청

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| — | — | — | — |

예시 arguments:

```json
{}
```

반환: `{accepted:true,phase:"stop_requested"}`.

phase는 접수 응답 문자열이며 WindowState phase의 새 종류가 아니다. 기존 공유 루트의 control 취소와 대기 재스캔 정리를 요청한다. active subscription이 없으면 no-op일 수 있다. 이후 app_status를 확인한다.

### 8. `scan_rescan` — 루트·하위 폴더 재스캔

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 아니오 | 최대 4096자 |

예시 arguments:

```json
{"path":"/example/data/a"}
```

반환: `{accepted:true}`.

idle live 스캔이 전제다. path 생략은 기존 루트, 지정하면 snapshot에 존재하는 폴더여야 한다. offline/진행 중에는 busy다. 현재 session을 재사용하므로 새 session UUID로 완료를 기다리면 안 된다. snapshot 없는 초기 idle에서 path 없는 호출은 실제 구독이 없어 no-op일 수 있다.

#### GPUI 0.3.0 후속 계약 (2026-11-24)

위의 SwiftUI legacy 설명과 달리 GPUI는 `path` 생략 시 **현재 창의 원래 분석 루트**를 갱신한다. 경로를 지정하면 원래 범위 안에 있고 보관된 snapshot에 존재하는 폴더여야 한다. 화면 위치와 이동 기록을 유지하며, 원래 문서가 주차되어 있어도 그 문서의 live 세션에 요청한다. live 세션이 없으면 새 전체 분석을 암묵적으로 시작하지 않는다.

반환 예시:

```json
{"accepted":true,"requested_path":"/example/data/a","document_root":"/example/data","effective_path":"/example/data/a","scope_mode":"subtree","background":false,"previous_version":"<native document version>"}
```

Mac은 지정 하위 트리를 갱신한다. Windows는 전체 범위의 하드 링크 집계를 유지하기 위해 소유 문서의 루트를 갱신하며 `scope_mode:"root"`, `effective_path:document_root`를 반환한다. 이 차이는 platform/native port에서 결정한다. `background`는 갱신 문서가 현재 표시 문서와 다른지를 뜻한다.

`accepted`는 완료를 뜻하지 않는다. `app_status.windows[].scan_documents`에서 `document_root`가 같은 항목의 `scanning:false`와 `version != previous_version`을 기다린다. `status`, `issues`, `cancelled`, `offline`도 확인한다. 오류·취소 상태를 성공으로 취급하지 않는다. 이 목록은 각 문서의 요약이며 노드 전체를 복제하지 않는다.

실패 코드는 잘못된 입력 `invalid_argument`, 원래 범위 밖 `outside_scope`, snapshot에 없음 `not_found`, 파일 `not_directory`, 볼륨 경계 `unsupported_scope`, 저장 문서 `offline_document`, 분석 중 `scan_active`, 종료된 엔진 `engine_unavailable`이다. 잘못된 범위는 상태를 변경하지 않는다. 줄바꿈이 포함된 Unix 경로도 JSON 문자열로 전달한다.

### 9. `node_info` — 노드 상세

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 아니오 | 최대 4096자 |
| `revision` | string | 아니오 | 별도 기본값 없음 |

예시 arguments:

```json
{"path":"/example/data/a/one.bin"}
```

반환: `{revision,node:Node,ancestors:[string]}`.

path 생략은 현재 focus. ancestors는 root부터 대상 자신까지의 경로다. snapshot에 없는 파일을 파일시스템에서 새로 읽어 찾아주는 도구가 아니다.

### 10. `tree_children` — 직계 자식 페이지

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `limit` | integer | 아니오 | 기본 `100`; 1~500 |
| `offset` | integer | 아니오 | 기본 `0`; 0~10000000 |
| `revision` | string | 아니오 | 별도 기본값 없음 |
| `path` | string | 아니오 | 최대 4096자 |
| `filtered` | boolean | 아니오 | 기본 `true` |

예시 arguments:

```json
{"path":"/example/data","limit":100,"filtered":true}
```

반환: `{revision,path,items:[Node],total_children,next_offset:int|null,order:"snapshot_child_order"}`.

total_children은 filter 전 개수다. filtered=true는 현재 weights>0만 반환한다. offset은 원본 children 배열 위치이며 결과 행 수가 아니다. next_offset=null이면 이 직계 자식 목록을 끝까지 검사했다. 화면 크기순 정렬과 다를 수 있다.

### 11. `query_nodes` — 독립 필터 검색 페이지

snapshot 기본 방식은 전체 flat table 위치 `offset`(0~10,000,000)에서 최대 `budget`(기본50,000, 1~100,000)을 검사한다. 기존 입력 `path`, `expression`, `limit`(기본100, 최대500), `revision`을 지원한다. scope 밖 노드와 폴더도 검사 예산에 포함되며 빈 페이지에도 continuation이 있을 수 있다.

`traversal:"subtree"`는 해당 하위 트리만 DFS로 읽는다. 첫 요청의 `path`/`expression`/평가 시각을 고정하고, 후속 요청은 응답의 `next_cursor`를 `cursor`로 전달한다. `cursor`는 최대36자·한 번만 소비되며 다른 revision/창/검색 조건에 재사용하지 않는다. continuation은 `next_offset:null`, `next_cursor:string|null`, `traversal_steps`, `inspected_nodes`, `evaluated_at`을 반환한다. budget은 node/edge/unwind 단계를 모두 제한하므로 결과가 없어도 계속 호출해야 할 수 있다.

```json
{"traversal":"subtree","path":"/example/data","expression":"*.zip","limit":100,"budget":50000}
```

창당 cursor8개·cursor당 DFS frame4096개·미사용60초 만료(다음 접근 시 정리)다. `cancel_cursor:true`와 cursor를 보내면 해제한다. revision 변경/창 shutdown도 해제한다. STDIO disconnect나 notifications/cancelled로 실행 중인 호출을 선점하는 기능은 없다. 기본 snapshot 모드는 요청별 now, subtree 모드는 cursor 생성 시 now다. 현재 view filter/show_hidden은 두 모드 모두 자동 적용하지 않는다. 특수 비디렉터리 SNS 레코드는 `native_type`을 확인한다. cursor를 소비하므로 readOnlyHint=true, idempotentHint=false다.

### 12. `largest_nodes` — 상위 K 노드

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 아니오 | 최대 4096자 |
| `limit` | integer | 아니오 | 기본 `100`; 1~500 |
| `revision` | string | 아니오 | 별도 기본값 없음 |
| `filtered` | boolean | 아니오 | 기본 `true` |
| `kind` | string | 아니오 | 기본 `"files"`; `files` / `folders` / `all` |

예시 arguments:

```json
{"limit":10,"kind":"files","filtered":true}
```

반환: `{revision,items:[Node],limit}`.

kind는 files/folders/all, 기본 files. scope 자신은 제외, 양수 크기만 반환한다. filtered=true는 현재 weights로 순위를 정하고 false는 현재 size mode의 원래 bytes를 쓴다. bytes 내림차순, 동률은 작은 id 우선. 페이지 cursor 없이 전체 N을 검사한다. all/folders 결과의 상하위 합계 중복에 주의한다.

### 13. `scan_issues` — 보관된 스캔 오류 페이지

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `limit` | integer | 아니오 | 기본 `100`; 1~500 |
| `offset` | integer | 아니오 | 기본 `0`; 0~10000000 |
| `revision` | string | 아니오 | 별도 기본값 없음 |

예시 arguments:

```json
{"limit":100}
```

반환: `{revision,items:[string],issue_count,stored_count,storage_truncated,next_offset:int|null}`.

offset은 보관 오류 배열 위치다. 전체 오류 중 최대 500개만 보관하므로 next_offset=null이어도 issue_count>stored_count일 수 있다. 이 도구도 readable QueryContext를 요구한다. root별 구조화 errno 객체가 아니라 오류 문자열이다.

### 14. `view_set` — UI 탐색·표시 변경

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 아니오 | 최대 4096자 |
| `action` | string | 아니오 | `up` / `back` / `forward` / `root` |
| `expression` | string | 아니오 | 최대 4096자 |
| `size_mode` | string | 아니오 | `logical` / `allocated` |
| `show_hidden` | boolean | 아니오 | 별도 기본값 없음 |
| `depth` | integer | 아니오 | 1~6 |
| `list_mode` | boolean | 아니오 | 별도 기본값 없음 |
| `watching` | boolean | 아니오 | 별도 기본값 없음 |
| `width` | integer | 아니오 | content width 640~4096, 생략 시 현재 값 |
| `height` | integer | 아니오 | content height 480~4096, 생략 시 현재 값 |
| `window_state` | string | 아니오 | `normal` / `minimized` / `hidden`, 생략 시 현재 상태 |

예시 arguments:

```json
{"action":"up"}
```

반환: `{accepted:true,state:WindowState}`.

path와 action은 동시에 전달하지 않는다. path는 폴더만 가능하다. up/back/forward가 불가능하면 기존 UI 동작에 따라 위치가 그대로일 수 있다. expression은 사전 parse하고 기존 applyFilter를 호출한다. expression=""는 해제다. size/hidden 값이 실제 바뀌면 projection을 유발하지만 depth/list 변경만으로 revision이 바뀌는 것은 아니다. 복합 변경은 순차 적용 후 projection 요청을 하나로 묶는다. UI 상태 전체의 원자적 트랜잭션은 아니다. 개별 옵션을 확인한 뒤 안정된 상태를 다시 읽는다.

### 15. `node_tag` — 원본 태그 토글

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 예 | 최대 4096자 |
| `color` | integer | 예 | 0~4 |

예시 arguments:

```json
{"path":"/example/data/a/one.bin","color":3}
```

반환: `{accepted:true,path}`.

color=0 해제, 1 빨강/2 노랑/3 초록/4 파랑. own mask는 각각 0/1/2/4/8이다. 같은 색 재적용은 해제이므로 멱등 쓰기가 아니다. live 루트는 actor 갱신이 UI에 다시 전달된 뒤 적용, offline은 로컬 tags와 projection을 갱신한다. node_info의 own_tag로 확인한다.

### 16. `snapshot_load` — SNS 오프라인 읽기

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `path` | string | 예 | 최대 4096자 |
| `replace` | boolean | 아니오 | 기본 `false` |

예시 arguments:

```json
{"path":"/example/snapshots/input.sns"}
```

반환: `{accepted:true,job_id,phase:"running"}`.

path는 로컬 SNS 파일 또는 확인한 문법 범위의 .DU 텍스트 파일이다. DU는 KiB·space·backslash 경로를 읽으며 상세 파일이 없는 합계는 native_type=6 missing으로 유지하고 실제 파일 개수를 만들어내지 않는다. 활성 스캔 교체에는 replace=true가 필요하다. 실제 format decode가 성공해야 offline으로 전환한다. 현재 구현은 load 입력의 확장자를 강제하지 않고 decoder로 판정한다. job completed 후 projection까지 기다린다. DU의 비ASCII도 원본 Windows codepage를 명시해야 한다. 모호한 residual/잘못된 경로·범위 밖 문법은 실패시키며 Windows runtime 동등성은 미확인이다. SNS v1~v4를 읽으며 v2의 비ASCII는 원본 ANSI codepage를 명시해야 한다. 복수 루트는 inspect_only로 root_index/path/count/bytes를 확인하고 하나를 선택한다. 모든 root를 검증하므로 선택하지 않은 root의 손상도 오류다. inspect_only에는 scan 교체 권한이 필요하지 않다.

### 17. `snapshot_save` — 현재 범위 SNS 저장

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `output` | string | 예 | 최대 4096자 |

예시 arguments:

```json
{"output":"/example/output/new.sns"}
```

반환: 접수: `{accepted:true,job_id,phase:"running"}`. 완료 JobState.result: `{output,revision}`.

현재 focus/filter/show_hidden 범위의 SNS v4를 저장한다. 캡처한 QueryContext 기준이며 나중 UI 변경과 독립적이다. output은 절대 경로·.sns 확장자·미존재 파일이어야 한다. 완전한 staging 기록·close 뒤 renamex_np(RENAME_EXCL)로 배타적으로 게시한다. exists 사전 검사만으로 덮어쓰기를 막는 것이 아니다. 부모 디렉터리는 자동 생성하지 않는다.

### 18. `report_export` — 현재 범위 TXT 내보내기

상태 변경 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `output` | string | 내보내기 시 | 새 절대 .txt 경로, 최대4096자 |
| `configuration_path` | string | 선택 | native 전체 config 또는 standalone exportConfig XML |
| `configuration_index` | integer | 전체 config 사용 시 | 0부터 시작하는 export index |
| `inspect_only` | boolean | 선택 | configuration_path metadata만 반환, 창/파일 변경 없음 |
| `config_legacy_code_page` / `config_xml_code_page` | integer | 필요한 encoding일 때 | 각각 명시적 Windows page 1~65535 |
| `max_output_bytes` | integer | 선택 | configured export 한도 1~1,073,741,824, 기본1GiB |

예시 arguments:

```json
{"output":"/example/output/files.txt"}
```

반환: 접수: `{accepted:true,job_id,phase:"running"}`. 완료 JobState.result: `{output,revision}`.

native Simple file list: 경로만, UTF-8/LF, 파일 우선·크기 내림차순. 현재 focus/filter/show_hidden/size mode를 사용한다. output은 절대 경로·.txt 확장자·미존재 파일이어야 한다. membership를 한 시점에 한 번 평가하고 parent 포함과 weights를 분리한 뒤 UTF-8/LF를 버퍼를 거쳐 순차 기록한다. 전체 report 문자열/Data는 만들지 않는다. 선택/weights·순회 stack·형제 정렬 메모리는 남는다.

명시적 configuration_path를 사용하면 원본 템플릿·정렬·카운터를 사용한다. 전체 config는 index를 필수 선택하고 standalone exportConfig는0이 기본이다. inspect_only는 `kind`, `settings_keys`, `file_classes`, `exports` metadata·typed settings·원본 extension 문자열과 `applied_to_window:false`를 반환한다. 검사 시 configuration_index를 지정하면 해당 header/detail/footer 원문도 반환한다. Windows 설정을 화면에 자동 적용하지 않는다. 날짜·시간·age와 decimal separator는 현재 Mac locale/timezone 경계이며 Windows locale 재현이라고 하지 않는다. configured output 한도·취소·템플릿 실패 시 staging을 폐기하며 목적 파일을 게시하지 않는다. configuration_path 없이 config/codepage/index/cap 옵션을 주면 오류로 거부한다.

### 19. `task_status` — Artifact 작업 상태

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| `job_id` | string | 예 | 별도 기본값 없음 |

예시 arguments:

```json
{"job_id":"job-uuid"}
```

반환: `JobState`; 형태는 공통 모델 참조.

앱 프로세스 범위 작업이다. window_id로 소유권을 검사하지 않는다. 최근 32개 중 제거되거나 재시작하면 not_found. phase=failed는 정상 조회 응답 안의 작업 실패다. tool isError만 확인해서 성공 처리하면 안 된다.

### 20. `view_capture` — 앱 content view PNG

읽기 도구.

| 입력 | 타입 | 필수 | 기본값·제약 |
|---|---|---|---|
| — | — | — | — |

예시 arguments:

```json
{}
```

반환: MCP ImageContent 한 개 + text metadata, structuredContent=`{window_id,width,height}`.

AppKit contentView를 bitmap으로 그린다. width<=1600, height<=1200이며 원래 비율을 유지하고 확대하지 않는다. native title/toolbar·커서·다른 앱은 포함하지 않는다. 현재 UI 프레임을 캡처하며 animation 종료나 projection 완료를 자동 기다리지 않는다. 이미지 Base64는 text/structuredContent에 중복하지 않는다.

## 공통 출력 모델

### WindowState

다음 필드는 `app_status(window_id)` 및 `view_set.state`에서 사용한다. nullable은 실제 JSON null 가능성을 뜻한다. app_status 전체 envelope는 앞의 도구 설명과 같이 별도다.

| 필드 | 타입 | 의미·해석 |
|---|---|---|
| `window_id` | string | 창의 store UUID |
| `scan_session_id` | string | store generation UUID; 재스캔 cycle ID와 다름 |
| `phase` | string | scanning/failed/offline/idle/cancelled/completed_with_issues/completed |
| `root` | string/null | 마지막 표시 snapshot 루트. 새 스캔 직후 null일 수 있음 |
| `scan_scope` | string/null | 엔진이 전달한 현재/최근 검사 범위 |
| `snapshot_revision` | string | 마지막 projection publish UUID. 조회 결과의 revision과 비교 |
| `projection_pending` | bool | 마지막 입력의 projection 대기/실행 중 |
| `scan_scheduling_error` | string/null | scan admission 포화/종료 오류. 파일시스템 issue 집계와 분리. 오류 시 phase=failed이며 기존 snapshot을 보존할 수 있음 |
| `snapshot_nodes` | integer | 표시 snapshot 전체 노드 수 |
| `snapshot_files` | integer | snapshot 파일 수 |
| `snapshot_folders` | integer | snapshot 폴더 수; fixture에서는 루트 폴더 포함 |
| `root_is_volume` | bool | snapshot 루트가 볼륨 루트인지 여부 |
| `snapshot_logical_bytes` | integer/null | 표시 snapshot 루트 논리 크기 |
| `snapshot_allocated_bytes` | integer/null | 표시 snapshot 루트 할당 크기 |
| `displayed_bytes` | integer | UI 헤더의 현재 focus/필터/모드 기준 크기. 특정 스캔 조건에서는 더 최신 progress 사용 |
| `volume_total_bytes` | integer | snapshot에 저장된 볼륨 전체. 없으면 0 |
| `volume_free_bytes` | integer | snapshot에 저장된 볼륨 여유. 없으면 0 |
| `issue_count` | integer | snapshot 전체 오류 수 |
| `cancelled` | bool | snapshot 취소 여부; stop 접수만으로 즉시 true가 되지 않음 |
| `progress` | Progress/null | 가벼운 엔진 진행 표본. snapshot보다 앞설 수 있음 |
| `focus_path` | string/null | 확대해서 보고 있는 폴더 경로 |
| `selected_path` | string/null | UI 선택 항목. MCP에서 임의 선택을 직접 쓰는 도구는 없음 |
| `breadcrumbs` | string[] | root부터 focus까지 |
| `history_count` | integer | 전체 방문 이력 개수 |
| `history_index` | integer | 전체 이력의 현재 위치, 초기 -1 가능 |
| `history_tail` | string[] | 전체 이력의 마지막 최대 50개. history_index는 이 배열의 로컬 index가 아님 |
| `can_back`, `can_forward` | bool | UI 이력 이동 가능 여부 |
| `filter` | string | 마지막 apply 요청 문자열. 편집 중 미적용 textfield 값과 다를 수 있음 |
| `filter_error` | string/null | UI projection의 filter parse 오류. 오류 시 이전 유효 filter가 남을 수 있음 |
| `size_mode` | string | allocated 또는 logical |
| `show_hidden` | bool | UI 숨김 속성 처리 옵션 |
| `detail_depth` | integer | 현재 상세 깊이. MCP 설정 범위 1~6 |
| `list_mode` | bool | 목록/트리맵 표시 |
| `watch_requested` | bool | 현재 store의 감시 요청 |
| `watch_active` | bool | 공유 루트의 실제 monitor 존재 여부 |
| `offline` | bool | SNS 오프라인 표시 여부 |
| `notice` | string/null | 사용자 안내·오류·오프라인 메시지 |
| `coverage_percentage_available` | bool | 현재 항상 false. 완료 백분율을 계산하지 않음 |

`completed_with_issues`와 `cancelled`를 성공적인 전체 스캔 완료로 합치지 않는다. phase는 store 속성 우선순위로 계산된다. scan admission 포화/종료 오류는 `failed`와 `scan_scheduling_error`로 표시한다. 일반 파일시스템 읽기 오류 전체를 failed로 매핑하는 것은 아니다. snapshot_nodes=0, notice, issue_count도 확인한다. offline snapshot의 counts/volume/native metadata는 현재 파일시스템 재검증 결과가 아니다.

### Progress

| 필드 | 타입 | 의미 |
|---|---|---|
| `sequence` | integer | 해당 progress의 sequence. revision·작업 ID와 다름 |
| `root` | string | 이 progress가 속한 엔진 루트 |
| `current_path` | string | 최근 진행 중인 경로 |
| `files`, `folders` | integer | 현재까지 집계 수 |
| `logical_bytes`, `allocated_bytes` | integer | 현재까지 집계 크기 |
| `visited_folders` | integer | 검사한 폴더 수 |
| `pending_folders` | integer | 현재 발견된 대기 폴더 수 |
| `issues` | integer | 진행 표본 시점 오류 수 |

sequence 또는 pending만으로 종료를 판정하지 않는다. API는 started_at/estimated_finish/percent를 Progress에 추가하지 않는다.

### Node

| 필드 | 타입 | 의미 |
|---|---|---|
| `id` | integer | snapshot 내부 ID. 새 snapshot의 영속 ID로 사용하지 않음 |
| `path`, `name` | string | 원래 snapshot 절대 경로와 항목 이름 |
| `parent_path` | string/null | 부모 경로. 루트 null |
| `is_directory` | bool | 디렉터리 여부 |
| `logical_bytes`, `allocated_bytes` | integer | 원래 집계 크기 |
| `filtered_bytes` | integer/null | 현재 view의 filter/mode weights. 독립 검색식의 재계산 결과가 아님 |
| `child_count` | integer | 원래 직계 children 수 |
| `modified_at` | number | epoch 초. metadata의 기본 과거 날짜가 실려 있을 수 있음 |
| `created_at`, `accessed_at` | number/null | epoch 초, 모르면 null |
| `own_tag` | integer | 자신의 태그 bitmask. 0은 없음 |
| `inherited_tag_mask` | integer | 자신과 조상의 tag OR |
| `native_attributes` | integer/null | core가 수집/보존한 원본 속성 bits |
| `native_flags` | integer/null | SNS 등의 내부 flags |
| `native_type` | integer/null | SNS 레코드 종류: 1 drive, 2 file, 3 folder, 4 free, 5 unknown, 6 missing |
| `file_identity` | string/null | core 파일 식별 보조값. 항상 존재·전역 유일을 보장하지 않음 |
| `issue` | string/null | 해당 노드에 저장된 오류 |

Node는 core DiskNode의 모든 필드를 외부로 내보내지는 않는다. `children` 전체 배열, `isSymbolicLink`, `ownAllocatedBytes`는 이 모델에 없다. 자식 상세는 tree_children을 사용한다. 심볼릭 링크를 live scan에서 제외하는 기존 계약은 별개다.

자신의 mask 4(초록)를 설정하려면 node_tag.color=3을 쓴다. color=4는 파랑 mask 8이다. 여러 조상의 색이 겹치면 inherited_tag_mask는 단일 색 mask가 아닐 수 있다.

### ProcessMetrics와 엔진 통계

| 필드 | 타입 | 의미 |
|---|---|---|
| `process.pid` | integer | 연결된 앱 자신의 PID |
| `process.measured_at` | number | 측정 코드에서 기록한 epoch 초 |
| `process.resident_bytes` | integer/null | MACH_TASK_BASIC_INFO resident_size |
| `process.virtual_bytes` | integer/null | virtual_size. 실제 RAM 사용량이 아님 |
| `process.physical_footprint_bytes` | integer/null | TASK_VM_INFO phys_footprint |
| `process.cpu_user_seconds` | number/null | getrusage user 누적 초 |
| `process.cpu_system_seconds` | number/null | getrusage system 누적 초 |
| `process.mach_basic_status` | integer | Mach basic 결과 코드. 0은 KERN_SUCCESS |
| `process.mach_vm_status` | integer | Mach VM 결과 코드. 0은 KERN_SUCCESS |
| `engine.cached_roots` | integer | 현재 ScanService의 root entry 수 |
| `engine.subscribers` | integer | 전체 루트 구독 합계 |
| `engine.scan_starts` | integer | 엔진 launch 요청 누적 횟수. 대기/포화 실패 포함; 실제 I/O 시작 수가 아님 |
| `engine.scan_limit` | integer | 공유 scan admission 슬롯 상한. 기본8, 고정 OS 스레드 수가 아님 |
| `engine.active_scans` | integer | 이미 허가된 슬롯 수. dispatch 직후 실제 scanner 진입 전도 포함 |
| `engine.queued_scans` | integer | 허가 전 FIFO 대기 작업 수 |
| `engine.scan_queue_capacity` | integer | 대기열 상한, 기본64. 포화 시 새 작업을 거부하고 failed/notice로 알림 |
| `engine.peak_active_scans` | integer | admission 생존 기간의 active 슬롯 최대값 |
| `engine.admitted_scans` | integer | 슬롯 허가 누적 횟수. 파일 I/O 호출 횟수와 다름 |
| `engine.finished_scan_workers` | integer | 허가된 작업의 종료 누적 횟수, 취소/실행 전 중단 포함 |
| `engine.cancelled_queued_scans` | integer | 대기열에서 취소·shutdown으로 제거한 누적 수 |
| `engine.rejected_scans` | integer | 포화 또는 shutdown 후 submit 거부 누적 수 |
| `workers.<stage>.runs` | integer | 해당 계측 지점 누적 진입 횟수 |
| `workers.<stage>.main_thread_runs` | integer | 계측 시 Thread.isMainThread=true 횟수 |

Mach 실패 시 관련 bytes는 null이다. getrusage 실패 시 CPU 값은 null이지만 별도 usage status 필드는 제공하지 않는다. 모든 worker가 반드시 표에 존재하는 것은 아니며 실행되지 않은 stage는 없을 수 있다. runs는 성공 완료 수나 현재 실행 중 수가 아니다. API는 CPU 백분율·peak RSS·스레드 스택을 제공하지 않는다.

추가 진단은 기존 필드를 유지한다. `process.thread_count`, `mach_threads_status`, 최대 64개 `sampled_thread_states[{id,run_state,flags}]`, `sampling_thread_id`, `sampling_on_main_thread`로 실제 own-process thread와 sampler 위치를 확인한다. Mach thread port/list는 조회 후 해제한다. thread ID는 정밀도 손실을 피하려 문자열이다.

각 `workers.<stage>`는 `submitted/started/completed/cancelled/failed/coalesced/stale_drops/active/peak_active`, `timed_calls/total_seconds/maximum_seconds/recent_seconds`, `queue_samples/queue_seconds/maximum_queue_seconds/sampled_thread_ids`를 제공한다. 최근 duration 최대 256개, thread ID 최대 32개, stage 이름 최대 128개다. stage마다 측정 지점이 다르고 duration은 중첩될 수 있다. `completed`는 그 실행기의 정상 반환 수이며 MainActor publish 승인 수와 다를 수 있다. `failed`와 `cancelled`의 구체적 경로도 구별한다. queue 시간은 submit부터 시작까지의 monotonic 누적/최대값이다.

`scratch`는 private ancestor context의 idle retained/charged bytes·4 MiB charge limit·owners·active·hits/misses·evicted bytes·pressure events를 제공한다. active 작업과 published 배열은 idle 상한 밖이다. `canvases`는 created/released/live 수다. `app_status(window_id).presentation`은 items·timer/transition·geometry pending/deferred·text entry/추정 UTF8 bytes·format/measure 수·tooltip/AX 수·sort 슬롯/rect tile/hit·observer 수·canvas 크기를 제공한다. text estimate와 scratch charge는 deep heap/RSS가 아니다. 창 상태에는 `visible/minimized/occluded` 및 content 크기가 추가됐다.

`view_set.window_state`는 테스트·자동화를 위한 해당 창의 표시 상태다. 데이터 scan/projection은 숨겨도 계속 처리한다. `view_capture`는 async로 projection과 최신 geometry를 최대 5초 준비하며, 숨긴 창도 현재 PNG를 만들고 presentation cache를 다시 정리한다. MainActor semaphore를 사용하지 않는다. PNG 최대 1600×1200 계약은 유지한다.

`window_retained_hidden`은 명시적으로 숨긴 창의 수명 lease다. 마지막 창을 숨겨도 store/window를 유지하고, 다시 표시하거나 실제 닫을 때 해제한다. `canvases.explicitly_hidden_windows`는 이 lease 수다. SwiftUI `onDisappear`는 창 닫기 판정에 쓰지 않는다. 실제 `NSWindow.willCloseNotification`에서 shutdown/unregister한다.

`window_on_active_space`, `application_hidden`, `application_active`는 각각 native NSWindow/NSApplication의 관측값이다. `window_frame={x,y,width,height}`는 AppKit screen 좌표(points, 아래쪽 원점)의 창 외곽이다. content 크기 및 PNG pixel 크기와 다르며, 창이 visible이어도 occluded일 수 있다. 이 값으로 여러 창의 가림/Space 검증 범위를 구분한다. read-only 상태 조회는 창을 전면으로 이동시키지 않는다.

width/height는 resize 요청값이다. SwiftUI/AppKit의 최소 창 크기·화면 제약 때문에 실제 크기가 달라질 수 있으므로 후속 app_status의 content 크기와 window_frame을 읽는다. accepted를 정확한 픽셀 크기 보장으로 해석하지 않는다.

같은 PID의 두 표본에서 `(Δuser + Δsystem) / Δwall_seconds × 100`을 구하면 클라이언트가 한 CPU 코어 기준 사용률을 추정할 수 있다. 이는 서버가 반환한 사용률이 아니고, 여러 코어 합계는 100을 넘을 수 있다. 측정 간격·PID 재시작과 실패 null을 확인해야 한다.

### JobState

running 예시:

```json
{"job_id":"job-uuid","phase":"running","started_at":1794130000.0}
```

저장 완료 예시:

```json
{"job_id":"job-uuid","phase":"completed","result":{"output":"/example/output/new.sns","revision":"projection-uuid"},"finished_at":1794130001.0}
```

읽기 완료의 result:

```json
{"loaded":true,"projection_pending":true}
```

실패 예시:

```json
{"job_id":"job-uuid","phase":"failed","error":"localized failure message","finished_at":1794130001.0}
```

현재 구현은 completed/failed 객체로 교체할 때 started_at을 유지하지 않는다. 따라서 완료 기록에 duration 필드가 있다고 가정하지 않는다. task_status 조회 자체가 성공했어도 phase=failed이면 artifact 작업은 실패다.

## 오류 참조

### JSON-RPC 오류

| 코드 | 발생 조건 | 후속 처리 |
|---|---|---|
| `-32700` | JSON parse 실패, NaN/Infinity 등 거부 | 올바른 JSON 한 줄로 수정 |
| `-32600` | 잘못된 envelope/ID, 1MiB 초과 요청 | object·jsonrpc·method·정수/문자열 ID와 크기 확인 |
| `-32601` | 미지원 메서드, modern 경로의 initialize | 현재 메서드 표와 버전 경로 확인 |
| `-32602` | schema 타입·필수/추가 필드·enum·범위·meta 오류, 알 수 없는 tool/URI | tools/list의 schema 확인 |
| `-32000` | initialize 전 legacy 요청 | 먼저 initialize |
| `-32022` | 미지원 요청별 protocolVersion | error.data.supported/requested 확인 |
| `-32603` | resource read 연결 실패 또는 처리되지 않은 내부 예외 | 앱 상태와 입력을 확인한 뒤 재시도 여부 결정 |

예시:

```json
{"jsonrpc":"2.0","id":3,"error":{"code":-32602,"message":"arguments.limit is outside the allowed range"}}
```

### 도구 실행 오류

앱/연결 오류는 보통 정상 JSON-RPC result 안의 `isError:true`로 반환한다. 현재 실패에는 structuredContent가 없다.

```json
{"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"stale_revision: Snapshot changed; restart pagination with the returned revision"}],"isError":true}}
```

| 앱 코드·메시지 | 의미 | 복구 |
|---|---|---|
| `window_required` | unique active window 선택 불가 | 전체 app_status에서 window_id 지정 |
| `not_found` | 사라진 창·미존재 snapshot 경로·job 미보관 등 | 대상을 새로 발견하고 올바른 ID/path 사용 |
| `not_ready` | readable snapshot 없음 | start/load 후 기다림 |
| `projection_pending` | 현재 projection 처리 중 | app_status를 poll한 뒤 조회 |
| `stale_revision` | 요청 revision 불일치 또는 async path 해석 중 변경 | 현재 revision으로 첫 페이지/변경 다시 판단 |
| `invalid_argument` | 상대 macOS 경로/NUL·폴더 필요·출력 확장자·옵션 충돌 등 | 의미 조건 수정 |
| `busy` | active scan 교체 거부·rescan 조건 불일치·artifact 2개 실행 중 | 완료 대기 또는 명시적 replace 의도 판단 |
| `already_exists` | 출력 경로 사전 존재 검사 실패 | 새 경로 사용 |
| `capture_failed` | bitmap allocation/PNG encoding 실패 | 창 크기/자원 확인 |
| `operation_failed` | filter parse·파일시스템 등 일반 오류를 Hub가 변환 | 상세 localized message 확인 |
| `unknown_command` | 내부 IPC 명령 불일치 | bridge/app 버전 일치 확인; MCP schema는 보통 앞에서 차단 |
| `unauthorized`, `invalid_request` | 내부 token·프레임·decode 오류 | 앱/bridge 연결 재확인. 인증값을 결과에 출력하지 않음 |
| `No unique running app controller...` | 후보 없음 또는 여러 개 | 업데이트한 앱 실행·instance_id 선택 |
| `App disconnected before responding` | 앱 종료·응답 크기 초과·전송 실패 등 | app_instances/status부터 재확인 |
| socket timeout·OSError 텍스트 | IPC I/O 실패 | 명령이 이미 적용됐는지 상태 확인 후 재시도 |

`ipc_unavailable`는 앱 controller 초기화 실패 코드다. 이때 MCP로 정상 접속하지 못해 도구 오류 대신 instances 비어 있음과 앱 NSLog로 관찰될 수 있다.

`busy`와 `not_found`는 여러 자원에서 공용으로 사용하므로 code만으로 창/파일/job 중 무엇인지 결정하지 않는다. 실패 텍스트는 영문 상수와 OS localized 메시지가 섞일 수 있다.

### 비동기 실패

job 생성 전 출력 확장자 오류는 isError, 생성 후 쓰기 충돌·권한·SNS decode 실패는 JobState.failed 경로일 수 있다. 이미 존재하는 파일을 동시에 요청한 두 job처럼 race가 있으면 같은 문제도 사전/사후 서로 다른 계층에서 실패할 수 있다.

클라이언트는 다음 세 가지를 각각 확인한다.

1. JSON-RPC에 error가 있는가.
2. tools/call result.isError가 true인가.
3. 접수된 작업의 task_status.phase가 failed인가.

## MCP 리소스

| URI | 대응 명령 | 반환 |
|---|---|---|
| `space-sniffer://status` | app_status, 창 생략 | `contents:[{uri,mimeType:"application/json",text:"<JSON>"}]` |
| `space-sniffer://resources` | app_resources | 동일 contents 형식 |

리소스 읽기는 instance_id/window_id를 지정하는 별도 schema가 없다. 따라서 후보 앱이 여러 개면 도구 호출로 명시적 instance를 선택한다. resource subscription·push change notification은 구현하지 않았으므로 새 값은 다시 읽는다. URI scheme은 리소스 식별자이며 네트워크 주소가 아니다.

## 클라이언트 구현 예제

아래 Python은 알고리즘 예제다. `call(name, arguments)`는 JSON-RPC/도구 오류를 검사하고 structuredContent를 반환하는 클라이언트 wrapper가 있다고 가정한다. 실행 가능한 전체 STDIO 예제는 [integration_smoke.py](../scripts/mcp/integration_smoke.py)를 참고한다. QA fixture용 25초 deadline/50ms poll 값을 운영용 기본값으로 그대로 옮기지 않는다.

### 직계 자식 페이지

```python
args = {"instance_id": pid, "window_id": window_id,
        "path": root_path, "limit": 100, "filtered": False}
rows = []
revision = None
offset = 0
while True:
    request = args | {"offset": offset}
    if revision is not None:
        request["revision"] = revision
    page = call("tree_children", request)
    revision = page["revision"]
    rows.extend(page["items"])
    if page["next_offset"] is None:
        break
    offset = page["next_offset"]
```

stale_revision을 받으면 rows/cursor/revision을 모두 버리고 새 요청으로 시작한다. 모든 rows를 모으지 않고 바로 소비하면 클라이언트 메모리도 줄일 수 있다. 큰 트리의 전체 결과를 LLM 한 메시지에 넣는 대신 필요한 scope/page만 전달한다.

### 검사 예산이 있는 검색

```python
request = {"instance_id": pid, "window_id": window_id,
           "expression": "*.zip;*.dmg", "budget": 50000,
           "limit": 100, "offset": 0}
while True:
    page = call("query_nodes", request)
    consume(page["items"])
    if page["next_offset"] is None:
        break
    request["offset"] = page["next_offset"]
    request["revision"] = page["revision"]
```

`if not page["items"]: break`는 잘못된 종료 조건이다. 결과 0개 페이지에서도 검사 budget을 소비하고 뒤에 일치 항목이 남아 있을 수 있다.

### 태그 변경의 재시도

```python
wanted_mask = 4  # 초록; node_tag color 번호는 3
before = call("node_info", target)["node"]["own_tag"]
if before != wanted_mask:
    call("node_tag", target | {"color": 3})
# 이후 deadline 안에서 node_info의 own_tag가 wanted_mask인지 확인한다.
# timeout이면 먼저 현재 mask를 다시 읽고, 같은 toggle을 무조건 반복하지 않는다.
```

동시 UI/다른 client 변경을 막는 compare-and-swap 계약은 없다. 정확한 변경 순서가 필요한 client는 같은 창에 대한 자기 요청을 직렬화하고 사용자 변경 가능성을 고려한다.

### 작업 완료

```python
accepted = call("snapshot_save", window | {"output": new_sns_path})
job = poll_task_until_terminal(accepted["job_id"], deadline_seconds=60)
if job["phase"] == "failed":
    raise RuntimeError(job["error"])
assert job["phase"] == "completed"
```

60초는 이 예제의 클라이언트 선택값이며 서버 artifact 제한 시간이 아니다. deadline 도달 시 작업은 계속 running일 수 있다. 같은 경로로 새 save를 접수하기 전에 기존 job을 다시 확인한다.

## 명세 유지 방법

1. 도구 추가·이름·타입·필수/기본값을 바꾸면 Python `TOOLS`와 앱 dispatch를 먼저 함께 검토한다.
2. 카탈로그 JSON의 tools를 현재 `TOOLS`에서 다시 추출하고 source_sha256을 갱신한다. secret이 들어 있는 runtime descriptor를 카탈로그로 저장하지 않는다.
3. 이 문서의 입력표·출력 설명·예제와 설계서의 제한을 갱신한다.
4. protocol 테스트와 Swift automation 테스트, 별도 QA 앱 smoke 중 변경에 맞는 검증을 수행한다.
5. 결과 counts는 실행 로그를 확인하고 갱신한다. 이전 51/6/99를 새 검증 결과처럼 복사하지 않는다.

2026-11-09 실행 경로 갱신: blocking scan은 ScanAdmission/Dispatch로 분리하고 root generation 승인은 ScanService에 유지했다. 대기 취소는 scanner를 호출하지 않으며 running 취소는 실제 작업이 반환할 때까지 슬롯을 유지한다. 파일 I/O syscall 자체의 즉시 중단은 보장하지 않는다. FilterScratch는 worker 전용 context만 최대1MiB capacity까지 보유하고 snapshot/membership/weights는 재사용하지 않는다. 개별 scratch bytes는 API에 노출하지 않는다. [검증](SCAN_RESOURCE_VALIDATION.md).

2026-11-09 artifact 갱신: UI/MCP의 파일·codec·volume/trash 작업은 ArtifactWorker actor에서 별도 serial Dispatch queue로 이관했다. 예약 작업1+대기64를 제한하며, MCP artifact 접수2/최근32 기록 정책과는 별개다. 접수 후 취소 API·job 영속화는 추가하지 않았다. 쓰기 실패는 소유 staging만 정리하고 destination은 unlink하지 않는다. UI overwrite는 atomic rename, MCP는 exclusive rename이다. fsync/crash durability 및 모든 확장 metadata 보존은 보장하지 않는다. [검증](ARTIFACT_STREAMING_VALIDATION.md).

## 2026-11-09 용량 회계 관측

WindowState.space_accounting은 live whole-volume snapshot에서만 객체이며 폴더/offline/idle은 null이다. total_bytes, free_bytes, system_used_bytes(total-free), observed_physical_bytes, unclamped_residual_bytes, unattributed_bytes(max(0,used-observed)), diagnostics를 제공한다. volume_metadata_timing=captured_at_scan_start이므로 현재 OS fresh poll이 아니며 부분 scan 합계와 시점이 다를 수 있다. coverage_percentage_available=false이고 잔여량을 접근거부나 미스캔 바이트로 단정하지 않는다.
