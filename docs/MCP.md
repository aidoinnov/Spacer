# MCP로 Mac Space Sniffer 제어

실행 중인 앱의 실제 ScanStore/ScanService에 연결합니다. 별도 모형 데이터나 재구현 스캐너를 사용하지 않습니다. UI와 플랫폼 연동 계층만 추가했으며 기존 필터·합산·태그·SNS 계약은 그대로 사용합니다.

상세 구현은 [기술 설계서](MCP_TECHNICAL_DESIGN.md), 도구별 입력·출력·오류는 [API 명세](MCP_API_REFERENCE.md), 현재 입력 스키마 원문은 [카탈로그](mcp-tool-catalog.json)에 정리했습니다.

## 연결

1. `./scripts/build-app.sh --universal`로 앱을 빌드하고 `dist/Mac Space Sniffer.app`을 실행합니다.
2. 이 컴퓨터의 Codex에 `mac_space_sniffer` STDIO 서버를 등록했습니다(`codex mcp list --json`에서 enabled 확인). 새 Codex 세션 또는 MCP 재연결 후 사용합니다. 저장소의 `.codex/config.toml`에도 같은 설정을 제공합니다. 프로젝트 설정은 신뢰된 프로젝트에서 적용됩니다. [공식 Codex MCP 설정](https://developers.openai.com/codex/mcp).
3. 다른 클라이언트에서는 Python 3.9 이상으로 다음 스크립트를 STDIO 서버로 등록합니다. 외부 Python 패키지는 필요하지 않습니다.

```sh
python3 "/absolute/path/Mac Space Sniffer.app/Contents/Resources/MCP/space_sniffer_mcp.py"
```

서버는 앱을 자동 실행하지 않습니다. 앱이 없으면 명시적 연결 오류를 반환합니다. 앱을 다른 위치로 이동하거나 Python을 제거하면 클라이언트 설정 경로를 갱신해야 합니다.

## 도구 20개

| 용도 | 도구 |
|---|---|
| 인스턴스·창·진행·자원 | `app_instances`, `app_status`, `app_resources` |
| 볼륨 용량·여유 공간 | `volumes_list`, `volume_info` |
| 스캔 시작·중지·재스캔 | `scan_start`, `scan_stop`, `scan_rescan` |
| 파일/폴더 상세·자식·검색·큰 항목·오류 | `node_info`, `tree_children`, `query_nodes`, `largest_nodes`, `scan_issues` |
| 탐색·필터·논리/할당 크기·숨김·깊이·목록·감시 | `view_set` |
| 원본 방식 색상 태그 토글 | `node_tag` |
| SNS 저장·읽기·TXT 내보내기 | `snapshot_save`, `snapshot_load`, `report_export`, `task_status` |
| 앱 화면 PNG | `view_capture` |

`space-sniffer://status`, `space-sniffer://resources` 읽기 리소스도 제공합니다.

## 호출 순서와 정확성

- `app_instances` → `app_status`로 시작합니다. 여러 앱은 `instance_id`(PID), 여러 창은 `window_id`로 지정합니다. 창을 생략하면 현재 key window, 하나뿐인 창 순으로 선택합니다. 스캔 경로는 절대 macOS 폴더 경로입니다.
- `scan_start`는 접수 결과만 반환합니다. `app_status.phase`가 `scanning`에서 벗어났는지, `projection_pending=false`인지 확인합니다. `completed_with_issues`, `cancelled`, `offline`을 구별합니다. `scan_stop` 역시 취소 요청이므로 이후 상태를 확인합니다.
- 진행 중 `progress.current_path`, `pending_folders`, `visited_folders`, 파일 수·바이트를 제공합니다. 전체 파일 수를 아직 모르므로 완료율은 제공하지 않습니다. 표시용 snapshot의 수치와 더 최신 progress 수치를 각각 반환합니다.
- `volume_info`는 파일시스템 total/free 및 차이 추정값입니다. APFS 공유·스냅샷, 접근 오류, 제외되는 심볼릭 링크 등 때문에 경로 스캔 합계와 같지 않을 수 있습니다. 볼륨 용량으로 파일 스캔 완료를 판단하지 않습니다.
- 조회는 최대 500행입니다. 첫 결과의 `revision`을 다음 페이지에 전달하고 `next_offset`을 그대로 사용합니다. 트리가 바뀌면 `stale_revision` 오류를 반환하므로 처음부터 다시 조회합니다. `projection_pending` 오류는 상태가 안정된 뒤 재시도합니다.
- `tree_children`의 커서는 자식 배열 위치입니다. `query_nodes`는 페이지당 최대 100,000개 노드를 검사합니다. 결과가 비어도 `next_offset`이 있으면 계속 읽어야 합니다. 검색식은 현재 화면 필터와 독립적으로 평가하며 파일을 반환합니다. 예: `*.zip;*.dmg`, `*.zip;>100mb`, `:tag:red`, `\\node_modules`.
- `largest_nodes`는 상위 K개만 유지합니다. 기본적으로 현재 화면 필터/크기 모드의 가중치를 사용합니다. `filtered=false`는 선택한 모드의 원래 크기를 사용합니다. 폴더와 파일을 함께 조회하면 상하위 크기가 중복되므로 행 합계를 전체 사용량으로 취급하지 않습니다.
- GPUI의 `scan_rescan`은 경로 생략 시 원래 분석 루트, 지정 시 보관 snapshot의 폴더를 갱신하며 화면 위치를 유지합니다. Windows는 소유 루트 전체를 갱신합니다. 응답의 `document_root`와 같은 `scan_documents` 항목에서 분석 종료·새 `version`을 확인합니다. [상세 계약](MCP_API_REFERENCE.md#gpui-030-후속-계약-2026-11-24)을 참고합니다.
- `view_set`의 `path`로 폴더 진입, `action:"up"`으로 상위 이동, `back/forward/root`로 이력·시작 위치를 탐색합니다. 화면 변경은 비동기 projection을 거치므로 상태를 다시 확인합니다.
- SNS/TXT 작업은 `job_id`로 `task_status`를 조회합니다. 완료 상태만 성공입니다. 동시 artifact 작업은 2개, 최근 작업은 32개까지 유지합니다. 저장/내보내기는 기존 파일을 덮어쓰지 않습니다. SNS 저장은 현재 focus/filter 범위이며 원본 SNS v4와 기존 exporter를 사용합니다.
- `scan_issues`는 총 오류 수와 보관 수를 구별합니다. 최대 500개 오류를 저장하며 `storage_truncated`로 누락 여부를 표시합니다.
- `app_resources`의 RSS/physical footprint/virtual bytes는 실제 앱 프로세스 Mach 수치입니다. CPU 값은 누적 초이며 CPU 사용률이 아닙니다. 엔진의 캐시 루트/구독/스캔 시작 수와 worker 실행·메인 스레드 실행 수도 반환합니다. 내부 캐시 메모리의 정확한 바이트 수를 추정해서 반환하지 않습니다.
- `view_capture`는 해당 앱 창의 content view만 PNG로 반환합니다(최대 1600×1200). 다른 앱 화면이나 커서는 포함하지 않습니다.

## 실행 구조와 범위

Python STDIO ↔ 사용자 전용 Unix socket ↔ `AutomationHub` ↔ 기존 앱 상태/worker입니다. 네트워크 포트를 열지 않습니다. IPC 디렉터리는 0700, 소켓·인스턴스 descriptor는 0600이며 같은 UID와 실행별 토큰을 검증합니다. 토큰은 MCP 조회 결과에 노출하지 않습니다. 같은 사용자 계정에서 실행되는 MCP 클라이언트가 앱의 접근 권한 범위로 경로 메타데이터를 읽고 명시한 경로에 SNS/TXT를 저장할 수 있습니다.

페이지 조회·상위 K 검색·프로세스 측정은 메인 스레드 밖에서 실행합니다. 트리는 기존 page 공유 snapshot을 참조하며 전체 JSON 트리를 한 번에 직렬화하지 않습니다. PNG 생성과 실제 UI 상태 변경은 AppKit/SwiftUI 메인 스레드에서 수행합니다. 파일 삭제·휴지통 이동·셸 실행 도구는 노출하지 않습니다.

STDIO는 UTF-8 newline JSON-RPC로 동작하고 stdout은 프로토콜 전용입니다. [공식 STDIO 전송 규약](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports). 2024-11-05~2025-11-25 initialize 협상과 2026-07-28 요청별 버전 metadata/server discovery를 지원합니다. STDIO 입력 한 줄은 1MiB, 내부 IPC 응답은 16MiB로 제한합니다. 외부 MCP 결과는 text와 structuredContent 중복으로 더 커질 수 있습니다. 취소 notification으로 이미 실행된 GUI 명령을 되돌리지 않으며 스캔 취소는 `scan_stop`을 사용합니다.

## 검증

```sh
swift test --sanitize=thread
python3 scripts/mcp/test_server.py
python3 scripts/mcp/integration_smoke.py --bundle-id local.macspacesniffer.mcpqa --output dist/qa-mcp-new-run
```

마지막 명령은 별도 bundle ID로 실행한 일회성 QA 앱 창에 스캔·필터·탐색·태그·SNS·TXT 작업을 수행합니다. 메인 사용자 창에 실행하지 않습니다. 각 실행에는 새 output 디렉터리를 지정합니다. 검증 결과와 MCP 캡처는 `docs/validation/mcp-*`에 보관합니다.
