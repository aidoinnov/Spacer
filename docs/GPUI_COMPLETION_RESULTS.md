# GPUI 0.3.0 구현·실행 검증

> 이 문서는 2026-11-23 기준이다. [2026-11-24 후속 원인/수정/검증](GPUI_BACKGROUND_RESULTS.md)을 우선한다. 기존 dist/releases/gpui-0.3.0은 당시 보관본이며 새 수정 패키지는 dist/releases/gpui-0.3.0-console-fix를 따른다.

2026-11-23. **Mac arm64와 Windows 132 PC(x64)에 공통 GPUI 0.3.0을 설치하고 주요 기능·실행을 검증했다.** Windows 기본 바로가기도 GPUI로 교체했다. 모든 OS 입력 조합과 장시간 운영까지 완료했다는 뜻은 아니다. 남은 검수는 마지막 절에 구분한다.

기존 사용자 Mac 분석 창(PID 85872), native scan(PID 86953), 복구 데이터는 보존했다. 기존 Mac SwiftUI 배포물과 Windows WinForms 0.1 설치·바로가기는 rollback으로 남겼다.

## 구현

- 공통 UI/탐색/애니메이션을 GPUI로 조립하고 OS API는 `platform/` 및 native `Platform/` 어댑터로 분리했다. 창 생성은 `ui/windows.rs` 한 경로를 사용한다.
- projection과 geometry 각각 실행 1개 + 교체 가능한 대기 1개. 폴더당 표시 2,048개와 명시적 나머지 타일로 geometry 비용을 제한한다. 전체 목록·필터·SNS 데이터는 유지한다.
- native → GUI 바이너리 전송(schema 2), payload 버전에 고정된 문서 조회, 64KiB 문서 스트림. 파일 교체/이전 완료 이벤트 경합을 강제로 재현하고 수정했다.
- 기존 Swift SNS/DU/필터/보고서/설정 XML 소스 41개 canonical 링크를 공유한다. UI·쿼리·작업 수명·문서 입출력·표시 상태의 책임을 분리했다.
- 설정 XML/명시적 코드페이지/템플릿 선택/설정별 export. 원자적 출력 및 자동화의 기존 출력 덮어쓰기 거부.
- hover 태그·tooltip·최대 500개 접근성 타일, 오류 창, SNS/폴더 drop 라우팅, 볼륨 목록 갱신, 파일 루트 트리맵.
- Windows root 날짜·볼륨 용량과 mount opt-in. 볼륨 ID로 중복·순환을 막고 일반 junction/symlink는 제외한다.
- Windows 별도 native preview host: text/UTF-16/image/Shell/metadata, 크기·프로토콜 검증, resize/Escape/Job 및 부모 수명 관리. Mac은 기존 Quick Look 재사용.
- 인증된 Unix socket / 사용자 전용 named pipe 제어 API, 비동기 문서 작업, 다중 창·최소화·숨김·복귀·종료. Windows PID 재사용 시 사라진 pipe를 가진 오래된 descriptor를 제외한다.
- 원본과 같은 fixture로 대조해 상세 패널 간격·볼륨 막대·글꼴 계층을 수정했다. variable font의 기본 Thin(100)을 등록하던 문제는 같은 OFL 폰트의 static 400/500/600/700 face로 해결했다.

## 검증 결과

| 구분 | 결과 | 원문 |
|---|---|---|
| Rust | Mac/Windows 각각 23개 통과 | `complete-font-rust-tests.log`, `windows-rust-tests.log` |
| clippy | 양쪽 QA/all-targets `-D warnings` 통과 | Mac/Windows clippy 로그 |
| 공통 Domain | Mac/Windows 각각 6개 통과 | Domain/native 빌드 로그 |
| Windows scanner | 실제 SDK 9개 통과 | `windows-scanner-tests.log` |
| 기존 Swift 전체 | 332개, 실패 0, 의도된 skip 1 | `complete-swift-tests.log`; 이후 formatter 이동은 Domain/native 빌드로 확인 |
| MCP Python | 9개 통과 | `mcp-tests.log`; Windows client의 실제 Python 실행과 구분 |
| 구조 | canonical 41개, 엔진 77파일/85계약/309근거, 공통 UI OS 분기 검사 통과 | shared-domain/platform/engine 로그 |
| 폰트 | 4개 static face의 실제 OpenType weight/family/hash 검사, 양쪽 렌더 확인 | `complete-font-validation.json` |
| 실제 GPUI | 양쪽 문서·미리보기·태그·다중 root·취소, mouse 탐색·history·진행 중 타일·100만 파일 렌더 | static document/navigation/progress/scale JSON |
| 설치된 production | 양쪽 조회 5종·SNS 저장/검사/재열기·XML 검사/템플릿 export·출력 보존·창 상태·다중 창·복귀 후 캡처 | primary-installed Mac/Windows JSON |
| Windows 바로가기 | 실제 `.lnk` 실행, 0.3.0.0, asInvoker/PerMonitorV2 manifest, visible 창, 번들 Swift DLL 확인 | primary shortcut/runtime/deployment JSON |
| OS watch | Mac 파일 3→4→3, Windows 2→3→2 실제 생성·삭제 반영 | watch/runtime JSON |
| 실제 볼륨 | 양쪽 공통 UI에서 100→6,100→100 파일, 선택 범위 복귀 | volumes JSON; owned mount fixture 모두 제거 확인 |
| 부모 종료 | 이전 native child는 1,500ms 내 미종료; 수정본 Mac 약 45ms/Windows 약 29ms에 종료·자체 임시 폴더 정리 | parent before/after JSON |
| 파일 작업 | Mac 실제 PNG 기본 앱 열기·내용 확인·경로 복사/붙여넣기·Finder 선택·native SNS 선택기·Space Quick Look/복귀 | `manual-mac.json` |
| 휴지통 | 양쪽 같은 pinned dependency로 자체 파일 이동·복원·내용 동일·fixture 정리 | trash port JSON; UI 확인 이후 전체 시퀀스와 구분 |

Mac CUA에서 원본 SwiftUI와 같은 폴더를 비교했고 Cmd+N/W/Q 및 휴지통 확인 취소도 관찰했다. 테스트 이미지 창만 닫고 기존 Preview 문서는 건드리지 않았다. Windows의 UI 이벤트 검증은 실제 visible GPUI 창에서 renderer/command/mouse/keystroke 경로를 실행한 acceptance다.

## 정량 측정

최종 폰트·패널 소스의 같은 QA executable로 **100만 파일 / 1,000,002노드 SNS**를 JSON/binary 교대 5회씩 측정했다. `complete-current-scale-summary.json`에 executable/input SHA-256과 전체 표본이 있다.

| 지표 | JSON | binary |
|---|---:|---:|
| 첫 표시 중앙값 | 15,481ms | 7,681ms |
| 첫 표시 표본 | 13,732 / 15,481 / 16,408 / 12,943 / 19,060ms | 5,016 / 5,399 / 9,825 / 7,681 / 7,716ms |
| 필터 전체 표본 중앙값 | 871ms | 759ms |
| 연속 요청 200개 중 교체 | 매회 198개 | 매회 198개 |
| burst 중 시작 / 최대 동시 실행 | 2 / 1개 | 2 / 1개 |

첫 표시 중앙값은 **약 50.4% 감소**했다. 타이머는 GPUI/폰트 초기화 이후에 시작해 SNS decode/전달/projection/geometry 및 visible tile opacity > 0.5까지 기다린다. **전체 앱 시작 시간, 파일시스템 탐색 처리량, disktree 대비 배수가 아니다.** 사용 중 사용자 분석 창·개발 작업을 유지한 환경이며 p95나 통제된 성능 채택 판정으로 쓰지 않는다. resize에는 고정 60ms settle이 포함된다.

Windows 최종 static-font QA 1회에서는 같은 100만 파일 첫 표시 **7,787ms**, 필터 580~727ms, burst 624ms, coalesced 198개/최대 동시 1개였다. Mac과 하드웨어/컴파일 상황이 달라 플랫폼 우열 비교로 쓰지 않는다.

바이너리 전송의 의미 동등성은 100만 파일 5쌍과 Unicode/metadata/tag 입력에서 통과했다. 전송 파일은 약 **201.7MB → 81.9MB(59.4% 감소)**. 별도 native decode+publication 측정 중앙값은 24.86초→6.92초였으나 같은 사용 중 환경의 편차를 포함하므로 GUI 측정과 합산하지 않는다. 앞선 18.45→11.96초 결과는 패널/폰트 보완 전 이력으로 보관한다.

최종 설치 Mac에서 100만 파일 반복 import 2회, 큰 import를 작은 SNS로 교체·취소, resize revision 보존, native child 종료를 확인했다. 현재 실행 종료는 약 17ms. 100ms 샘플 최대 RSS는 GUI 약 750MB, GUI+native 합계 약 1.47GB였다. 실제 peak allocation/타 도구 대비 메모리 우위를 의미하지 않는다.

앞선 메모리 압박 중 1회는 종료 후 프로세스 회수가 8초 기준을 넘었고 OS 상태 `E`가 관찰됐다. 코드를 바꾸지 않은 다음 3회는 12~22ms, 최종 설치본은 17ms였다. 실패 로그도 보존하며 원인을 제품 수정으로 해결했다고 주장하지 않는다.

## 빌드·설치·배포

- Mac: `scripts/build-gpui-app.sh`의 실제 실행과 패키징 통과. host architecture를 빌드하며 현재 검증 대상은 arm64/macOS 14+. `~/Applications/Mac Space Sniffer.app`에 설치했다. ad-hoc 서명 및 `codesign --verify --deep --strict` 통과.
- Windows: VS x64 SDK에서 `scripts/build-gpui-app.ps1` 실제 실행 통과. Swift backend/일치하는 runtime DLL/native preview/Rust UI를 조립했다. `%LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.3.0-GPUI` 설치와 기존 바탕화면 바로가기 교체·실행을 확인했다. unsigned이며 Authenticode를 수행하지 않았다.
- `dist/releases/gpui-0.3.0`에 두 플랫폼 ZIP/manifest. 설치본·primary build·배포본 hash를 확인했다. 각 build는 새 출력 경로를 사용하고 기존 SwiftUI/WinForms를 덮어쓰는 기본 경로로 돌아가지 않는다.
- 기존 `scripts/build-app.sh`/native SwiftUI target은 참조·기존 CLI/회귀 검증용이다. README 기본 UI 빌드 명령을 GPUI로 바꿨다.
- production은 `--qa-*`를 exit 64로 거부한다. upstream capture API용 feature와 우리 acceptance 명령을 구분했다.
- 테스트 전용 mount와 자체 파일을 정리했다. 검증이 끝난 자체 debug dependency/cache 약 10GB를 정리했고 사용자 분석/복구 파일은 보존했다.

재현:

```sh
scripts/build-gpui-app.sh
python3 scripts/check-gpui-boundary.py
python3 scripts/gpui-app/check-shared-domain.py
python3 scripts/gpui-app/check-fonts.py
python3 -m unittest discover -s scripts/mcp -p 'test*.py'
# 별도 QA instance의 문서를 자체 fixture로 바꾸고 마지막 창을 닫는다.
python3 scripts/gpui-app/check-control.py --instance PID --output /ABS/fresh-control.json
python3 scripts/gpui-app/benchmark-scale.py /ABS/QA.app/Contents/MacOS/space-sniffer-gpui --sns /ABS/scale.sns --pairs 5 --output /ABS/fresh-scale.json
```

scale 생성 옵션은 `ScaleTests.swift`의 `SNIFFER_GPUI_SCALE=1000000`, `SNIFFER_GPUI_SCALE_FLAT=1`, `SNIFFER_GPUI_SCALE_OUTPUT`을 따른다. Windows SDK/Swift 인자는 [GPUI README](../gpui-app/README.md)를 확인한다.

## 남은 검수와 지원 경계

- [ ] 두 OS의 실제 앱 간 SNS/폴더 drag/drop 전체 입력. 라우팅 구현과 native 선택기/문서 열기는 검증했으나 실제 OS drag gesture 통과로 대체하지 않는다.
- [ ] Windows 기본 앱 열기·클립보드 및 양쪽 UI 휴지통 확인→재스캔→OS 복원을 하나의 실제 입력 시퀀스로 검수. API/port 시험과 구분한다.
- [ ] 장시간 watch/반복 작업 soak, 종료 회수 8초 초과 1회의 환경·제품 원인 분리.

Mac PNG 기본 앱 열기는 통과했다. 텍스트 기본 앱 Notepad Pro는 호출됐으나 그 앱이 데이터 오류를 표시해 내용 표시는 미검증이며 파일 연결 설정은 바꾸지 않았다. Windows Python MCP client 자체의 실기기 실행은 별도이며 named-pipe 제어 API는 실제로 검증했다.

원본과의 배치·행동 대조와 두 GPUI 화면 검수는 수행했지만 system chrome/SF Symbols/서체의 픽셀 일치나 모든 Quick Look/Shell 형식 지원을 주장하지 않는다. Windows export locale formatter/상대 기간 표기는 문서화한 OS 차이가 있다. 과거 엔진 A/A·분기/tiny/deep 성능 HOLD나 최신 disktree 재대결을 이번 GUI 시험으로 해소했다고 주장하지 않는다.

[검증 원문과 source/artifact manifest](validation/gpui-2026-11-23/completion/README.md).
