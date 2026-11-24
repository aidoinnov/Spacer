# GPUI 문서·필터·태그 이식 결과

2026-11-23. SNS/DU, 필터, 기본 보고서는 기존 Swift 코드를 공유하도록 연결했다. Mac과 132번 Windows PC의 실제 GPUI 창에서 문서 왕복과 탐색을 검증했다. Mac preview 앱을 `/Volumes/develop` 분석으로 실행했고, 진행 중 트리맵 표시를 CUA로 확인했다. **전체 UI 이식·대형 디스크 성능 gate·정식 배포 완료는 아니다.**

## 반영한 동작

- SNS 바이너리 읽기/쓰기, DU 읽기, 여러 root 선택, 구형 Windows 인코딩 15종 명시 선택. root/인코딩 목록은 공통 GPUI 가상 목록이다.
- 불러오기 성공 전에는 기존 문서를 유지한다. 취소·다른 파일/폴더 선택은 이전 요청을 무효화하고 해당 importer를 종료한다.
- 기존 `ScanFilter`의 기간·속성·클래스·태그·폴더·명시 크기 문법을 사용한다. 크기 경계는 원본의 포함 경계, 폴더 include는 OR다.
- SNS/기본 TXT는 기존 선택·정렬·인코더를 사용한다. TXT는 파일 경로만 UTF-8/LF로 출력한다. 저장은 인접 임시 파일 → 전송 길이 확인 → 동기화 → 원자적 교체다. 실패하면 기존 파일을 보존한다.
- 태그는 1/2/4/8 비트마스크다. 직접 태그의 첫 색을 표시하고, 조상 OR는 필터에만 적용한다. 같은 색 재입력은 해제, 0키는 현재 focus 범위 해제다.
- Enter는 선택 파일의 포함 폴더를 확대한다. Mac Space는 기존 `QuickLook.swift`를 동적 UI port로 호출한다. Windows 미리보기는 아직 비활성이다.
- 수정·생성·접근 시각을 wire/inspector에 연결했다. Windows 열거 결과의 FILETIME을 사용하며 파일별 추가 조회를 하지 않는다. Windows 스캔 root 자체의 날짜/볼륨 용량 조회는 아직 남아 있으며 알 수 없는 값은 `—`로 표시한다.
- 현재 폴더 재검사와 단축키를 연결했다. Mac은 기존 부분 갱신 API, Windows는 scan-wide 하드 링크 중복 계산을 지키기 위한 전체 root 재검사다.
- SNS drop/파일 실행 인자는 문서 열기 경로를 사용한다. 빈 필터 안내·필터 지우기·오프라인 재투영을 연결했다.
- 반복되는 child 전체 경로를 parent/name으로 압축했다. 탐색/완료 갱신 때 전체 노드 hash map을 만들던 동작을 조상·직접 자식 검색으로 바꿨다. 큰 그래프와 이전 문서 owner의 해제는 UI 밖에서 한다.

## 실제 시작 지연과 수정

서명한 앱의 실제 볼륨 실행에서 0B 상태가 지속됐다. [샘플](validation/gpui-2026-11-23/documents/mac/startup-blocked-sample.txt)은 시작 약 42초 뒤 `ScanService.subscribe → configureMonitor → FSEventStreamCreate → watch_path → open`에서 기다리는 모습을 보였다. 감시 등록이 스캔 시작 앞에서 actor를 막고 있었다.

`DirectoryMonitorRegistration`에 등록/해제를 분리했다. 등록 전용 직렬 utility lane으로 OS 대기 thread 수를 제한하고, 취소 후 돌아온 native object는 채택하지 않고 정리한다. `watchActive`는 실제 stream 준비 상태다. 스캔 전에 이벤트 ID를 잡아 지연 등록 중 변경을 재생하고, 기준점을 얻지 못한 경우에는 보수적으로 root를 갱신한다. 순수 HistoryDone 표시는 변경으로 취급하지 않고, 유실 플래그의 root 갱신은 유지한다. 이 기준점 사용은 [Apple의 이벤트 ID 문서](https://developer.apple.com/documentation/coreservices/1442917-fseventsgetcurrenteventid)와 [sinceWhen 계약](https://developer.apple.com/documentation/coreservices/1443980-fseventstreamcreate)에 따른다.

watch 준비 상태만 바뀐 동일 revision은 전체 tree로 다시 직렬화하지 않는다. 수정 앱에서 실제 `/Volumes/develop`의 3.5MB/폴더 91개 진행과 트리맵을 확인했다. 이것은 분석 시작 차단 해소의 확인이며, 그 볼륨 전체 완료/감시 OS 호출 자체의 무지연 보장은 아니다.

## 책임 경계

| 책임 | 소유자 |
|---|---|
| 원본 SNS/DU/필터/보고서 의미 | canonical `Sources/SpaceSnifferCore` 파일 |
| 공유 모듈·Windows 조립 | `Packages/SpaceSnifferExplorerBridge` |
| source token·64KiB 스트림 | `ExplorerService/DocumentService.swift` |
| 프로세스 입출력·원자적 저장 | Rust `backend.rs`, `document.rs` |
| 문서 작업/선택/재검사 UI | `ui/artifacts.rs`, `document_choices.rs`, `scan_commands.rs` |
| OS 인코딩·미리보기·감시 | 전용 platform adapter/registration owner |

소스 링크/Windows materialization 28개를 hash로 고정한다. Mac bridge는 Core, Windows backend는 ExplorerDomain을 사용하며 같은 프로세스에서 모델을 섞지 않는다. Windows 탐색·집계 알고리즘을 새로 만들지 않았으며, 기존 reader의 시간 metadata 전달만 추가했다.

## 검증 결과

| 검사 | 결과 | 근거 |
|---|---|---|
| Mac Core release | 283개, 3 skip, 실패 0 | [로그](validation/gpui-2026-11-23/documents/mac/core-tests.log) |
| Rust | 16개 통과, clippy `-D warnings` 통과 | [테스트](validation/gpui-2026-11-23/documents/rust-tests.log), [clippy](validation/gpui-2026-11-23/documents/clippy.log) |
| 공유 Domain | Mac/Windows 각 3개 통과 | SNS·복수 root·태그·한국어 CP949·Unicode mask |
| Windows scanner release | 7개 통과 | [로그](validation/gpui-2026-11-23/documents/windows/engine-tests.log) |
| Mac 실제 GPUI | 문서 왕복/선택/취소/필터/Enter/Quick Look 통과 | [JSON](validation/gpui-2026-11-23/documents/mac/document-gui.json), [화면](validation/gpui-2026-11-23/documents/mac/document-gui.png) |
| Windows 실제 GPUI | 같은 공통 시나리오 통과, preview 제외 | [JSON](validation/gpui-2026-11-23/documents/windows/document-gui.json), [화면](validation/gpui-2026-11-23/documents/windows/document-gui.png) |
| 실제 mouse 경로 | 두 플랫폼 폴더 진입/history/파일 확대/원래 scan PID 유지 | [Mac](validation/gpui-2026-11-23/documents/mac/navigation-click.json), [Windows](validation/gpui-2026-11-23/documents/windows/navigation-click.json) |
| 등록 대기·수명 TSAN | 5개 통과, race 보고 없음 | [직접 host 로그](validation/gpui-2026-11-23/documents/mac/monitor-tsan-host.log) |
| 실제 볼륨 preview | 실행·progress treemap 확인, 분석 진행 중 | [live record](validation/gpui-2026-11-23/documents/mac/live.json) |

Core의 skip 3개는 이 실행에 중첩 볼륨 fixture를 준비하지 않은 native integration 검사다. TSAN의 SwiftPM discovery helper는 sanitizer platform-policy 오류로 실행되지 않았다. 저장소의 기존 `run-tsan-host.sh`로 개인 test host에서 같은 instrumented bundle을 실행해 5개를 통과했다. 시스템/Xcode 파일이나 보안 설정은 바꾸지 않았다. [초기 helper 로그](validation/gpui-2026-11-23/documents/mac/monitor-tsan-discovery.log)를 함께 보관한다.

## 정량 결과

9,001노드/9,000개의 0바이트 파일 fixture, warmup 3회 후 30회 native 문서 RPC다. `/Volumes/develop` 실제 분석과 병행한 실행으로, 전체 파일 탐색 엔진의 전후 성능 비교가 아니다.

| 항목 | 측정 |
|---|---:|
| 필터 RPC p50 / p95 | 5.51 / 9.65ms |
| 792,000B 보고서 RPC p50 / p95 | 45.30 / 82.06ms |
| parent/name wire / full-path payload | 약 2.10 / 2.97MB |
| 반복 경로 제거에 따른 크기 감소 | 약 29.4% |
| 문서 data chunk 최대 | decoded 65,536B |
| 관측 JSONL 최대 line | 87,435B |

[원시 결과](validation/gpui-2026-11-23/documents/document-bridge.json). 전송/클라이언트 decode까지 포함하며, p95는 nearest-rank다. full-path 비교는 동일 semantic payload를 재구성한 값이므로 원본 앱 전체 메모리나 1TB 스캔 속도 개선률로 확대하지 않는다.

## 재현

```sh
swift test --package-path Packages/SpaceSnifferExplorerBridge -c release
cargo +1.97.0 test --manifest-path gpui-app/Cargo.toml --features qa
cargo +1.97.0 clippy --manifest-path gpui-app/Cargo.toml --features qa --all-targets -- -D warnings
python3 scripts/gpui-app/check-shared-domain.py
python3 scripts/gpui-app/check-document-bridge.py /path/to/MacScanBridge --portable /path/to/ExplorerBackend --output /tmp/document-result.json
space-sniffer-gpui --scan OWNED_FIXTURE --qa-document-only /tmp/document-gui.json
# Windows interactive desktop probe에는 --qa-visible 추가
```

GUI fixture에는 비어 있지 않은 `branch` 폴더와 파일이 필요하다. `--qa-navigation-only`는 실제 GPUI mouse-down/up 경로를 검증한다. 문서 probe는 실제 프로세스·인코더·입출력과 같은 command handler를 사용하되, 파일 dialog/OS drag의 물리 입력 전체를 대신하지 않는다. hidden Windows 1×1 viewport는 시각적 근거로 사용하지 않는다.

## 남은 완료 조건

[동등성 표](GPUI_FEATURE_PARITY.md)를 따른다. Windows 미리보기/정밀 부분 갱신, mounted-volume opt-in UI, 설정 export/자동화·다중 창, tooltip·가상 접근성·hover 키 의미, 실제 OS 파일 작업·drag 검수, 대형 그래프/연속 필터 작업 교체와 메모리 gate, 두 OS release 패키징은 남았다. 현재 앱은 Rust dev + Swift release의 ad-hoc 서명 preview이고 기존 production 설치 앱은 교체하지 않았다. Windows도 검증 candidate이며 기본 WinForms 설치를 GPUI 정식 설치로 바꾼 상태가 아니다.
