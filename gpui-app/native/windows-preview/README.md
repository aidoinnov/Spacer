# Windows preview port

공통 GPUI의 `platform/windows/preview.rs`가 고정된 adjacent executable인
`WindowsPreviewHost.exe`를 실행한다. UI의 OS 분기는 platform 모듈 안에 둔다.
별도 Win32 창은 GPUI 부모 창의 owned tool window이며 앱 화면을 재구현하지 않는다.

C++ helper는 읽기 전용 텍스트(UTF-8/UTF-16 BOM, 1MiB), WIC 정적 이미지
(32M pixels), 등록된 Shell preview handler, metadata fallback을 제공한다.
Shell handler는 CLSCTX_LOCAL_SERVER만 사용하고 IInitializeWithStream에
읽기 전용 stream을 먼저 제공한다. handler의 실제 제공 형식은 설치 상태에
따라 달라진다. Quick Look과 전체 형식 동등성을 보장하지 않는다.

Rust adapter는 kill-on-close Job, 10초 readiness deadline, 4096-byte readiness
line 한도와 HWND 소유 PID 검사를 담당한다. helper는 parent handle을 감시하고
Escape/Space, 창 닫기, resize, IPreviewHandler.Unload를 처리한다. 사용자 문서를
수정하거나 기본 연결 앱으로 실행하지 않는다.

[Microsoft preview handlers](https://learn.microsoft.com/en-us/windows/win32/shell/preview-handlers),
[handler 구현 계약](https://learn.microsoft.com/en-us/windows/win32/shell/building-preview-handlers).

## 빌드와 실행 gate

VS x64 developer prompt에서 `build.cmd OUTPUT_DIRECTORY`로 빌드한다.
GPUI/ExplorerBackend/Swift runtime과 helper를 함께 배치한다. Linux/macOS의
MinGW 빌드와 Rust Windows target 검사는 실제 Windows 실행 검증을 대신하지 않는다.

132 PC 복구 후 다음 시나리오를 실행하고 JSON/PNG/프로세스 목록을 보관한다.

1. 최신 source manifest를 고정하고 MSVC helper + GPUI + ExplorerBackend를 빌드한다.
2. `--features qa` GPUI에서 `--scan FIXTURE --qa-document-only REPORT.json
   --qa-visible`로 실제 준비 신호·표시·SNS 왕복을 확인한다. fixture에는 `branch`와
   그 안의 텍스트 파일이 있어야 한다. report.previewObservation의 visible 및
   renderer를 확인한다. 실제 Space 입력도 별도로 재현한다.
3. 한글·공백·긴 경로의 텍스트/UTF-16/이미지/미지원 파일/폴더를 연다.
   내용 또는 metadata가 올바르고 입력 파일 hash가 같은지 확인한다.
4. 창 resize, Escape/Space 닫기, 연속 다른 파일 preview를 확인한다.
   실행 중 helper는 최대 1개이며 이전 helper는 종료해야 한다.
5. GPUI 정상 종료와 강제 종료 모두에서 helper가 남지 않아야 한다.
   preview 창을 닫아도 GPUI와 분석은 유지되어야 한다.
6. helper 누락은 비활성화, 손상 helper/준비 실패는 10초 내 상태 오류로 처리하고
   GPUI 입력과 분석이 계속되어야 한다. 등록 handler가 없는 PC에서도 fallback을 확인한다.

2026-11-23: C++ MinGW -Werror 빌드와 Rust Windows target clippy 통과.
132 PC에 연결할 수 없어 위 runtime gate는 미완료다.
