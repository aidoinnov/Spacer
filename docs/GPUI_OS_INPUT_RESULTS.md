# 실제 OS 입력 검수·취소 역할 수정 — 2026-11-24

사용자가 CGEvent·UI Automation·SendInput 사용을 승인한 뒤 검사용 파일과 우리 앱만 대상으로 실제 입력을 검수했다. **공통 UI의 휴지통 확인 버튼 역할을 수정했다.** 이전 Quick Look 재진입 수정은 유지하며 엔진은 기존 184B 버전 그대로다. 정식 속도 검증과 168B 엔진 후보의 채택은 별개다.

## 새 수정과 확인된 원인

기존 `window.prompt`의 문자열 배열은 GPUI에서 `PromptButton::Other`가 된다. 설치된 Windows 의존성 `gpui-pre-windows 0.3.6`의 `window.rs`는 이 버튼을 음수 ID로 만들며, `dialog.rs::task_dialog_callback`은 명시적인 `Cancel`이 없을 때 Escape/X의 `IDCANCEL` 요청을 거부한다. UI에 ‘취소’라는 글자가 있는 것만으로 취소 역할이 생기지 않는다.

`gpui-app/src/ui/file_actions.rs`에서 `PromptButton::cancel("취소")`, `PromptButton::ok("휴지통으로 이동")`로 바꿨다. 결과 인덱스 1일 때만 휴지통으로 이동하는 기존 계약을 유지한다. OS 조건이나 별도의 Windows 삭제 구현을 추가하지 않았다.

- 수정 전 Windows: 실제 Escape 후에도 확인창이 남는 것을 확인했다.
- 수정 후 Windows: 실제 Ctrl+Backspace로 연 확인창의 버튼 ID가 `CommandButton_2`/`CommandButton_1`로 바뀌었고, 실제 Escape로 확인창이 제거됐다. 파일 SHA-256도 보존됐다.
- 수정 후 Mac: 실제 Cmd+Backspace → 네이티브 sheet → Escape → 원래 지도 복귀와 파일 보존을 확인했다. staging과 실제 설치 경로에서 각각 수행했다.
- 새 소스로 release 테스트 Mac **29/29**, Windows **30/30**, 양쪽 QA/all-targets clippy `-D warnings` 통과.

## 실제 입력·파일 대조

| 검수 | 결과 | 근거와 범위 |
|---|---|---|
| Mac Finder → 앱 폴더 드래그 | 통과 | 실제 CGEvent 드래그 후 live root가 `beta`로 바뀜 |
| Mac Finder → 앱 SNS 드래그 | 통과 | `owned-snapshot.sns`를 실제 드래그, offline=true·저장된 root/파일 수 확인 |
| Windows 탐색기 → 앱 폴더 드래그 | 통과 | 실제 SendInput 드래그, live root가 `alpha`로 바뀜 |
| Windows 탐색기 → 앱 SNS 드래그 | 통과 | 실제 SendInput 드래그, offline=true·root=alpha·파일 1개 |
| Windows 실제 탐색 단축키 | 통과 | Ctrl+[ / Ctrl+] / Ctrl+Up을 각각 focus_path와 대조 |
| Windows 방향키·Escape | 통과 | 선택 경로 생성/제거 확인 |
| Windows 새 창·닫기 | 통과 | 실제 Ctrl+N / Ctrl+W, 창 수 1→2→1 |
| Windows 실제 태그 | 통과 | 1/2/3/4 → native own_tag 1/2/4/8, 같은 4 재입력→0, 0→0 |
| Windows 경로 복사 | 통과 | 실제 UI action의 클립보드 문자열을 선택 파일 경로와 대조, 이전 클립보드 복원 |
| Windows 실제 미리보기 | 통과 | 실제 Space, 설치 경로의 PreviewHost 자식 PID·보이는 native HWND·파일 제목 확인 |
| Windows 탐색기에서 보기 | 통과 | 실제 Ctrl+Shift+F 후 탐색기의 선택 항목이 대상 파일과 일치 |
| Windows UI 휴지통·복원 | 통과 | UI 이동 후 파일 수 3→2, OS recycle 복원 후 3; 원래 49바이트 내용 복원 |

드래그·태그·클립보드·휴지통의 위 시퀀스는 이번 취소 역할 수정 **전** UI에서 수행했다. 역할 수정 후에는 양쪽 네이티브 취소를 다시 확인했다. 모든 이전 실제 입력을 수정 후 전부 다시 실행했다고 표시하지 않는다. 이전 실제 Mac 저장/열기/보고서·태그·휴지통/Finder 복원은 [앞선 결과](GPUI_PREVIEW_REENTRY_RESULTS.md)에 범위를 기록했다.

49바이트 Windows 시험 파일은 원래 할당량이 0이라 할당 크기 지도에 없었다. 원본을 별도 보관하고 자체 marker로만 늘려 검수했다. recycle의 동일 이름 항목은 원래 경로·준비한 전체 내용 SHA-256·삭제 시각으로 구분해 가장 최근의 정확한 항목만 OS `undelete`로 복원했다. 이어 원래 49바이트를 복원했다. 다른 recycle 항목은 삭제하거나 복원하지 않았다.

## 검수 도구의 실패와 판정 제한

Finder 내부 이동을 양성 대조군으로 확인한 뒤 앱을 먼저 올리고 Finder를 올려 실제 드래그했다. 임시로 이동한 `beta`는 원래 위치로 복원했다. 앞선 화면 밖 Finder 창/다른 창의 가림 때문에 실패한 드래그를 앱 결함으로 분류하지 않는다.

Windows 기본 `.NET MainWindowHandle`은 실제 보이는 preview HWND가 있어도 0이었다. 실제 설치 경로·부모 PID를 확인한 PreviewHost에 대해 native `EnumWindows`/`IsWindowVisible`을 사용했다. UIA Root children만으로 보조 창의 부재를 판정하지 않았다.

Windows 공통 파일 대화상자의 일부 컨트롤은 UIA에서 `Pane`으로 노출되고 Invoke/SetFocus를 제공하지 않았다. 여러 입력 시도와 실패를 원문에 남겼다. `GetWindowText`는 다른 프로세스의 edit 텍스트 조회에 사용할 수 없어 `WM_GETTEXT`로 대조 방법을 수정했다. 이 제약은 [Microsoft 문서](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowtextw)에 명시돼 있다. 저장/열기/내보내기의 단순 ‘키를 보냈다’는 기록은 통과 판정이 아니다. 파일 생성·offline 상태·실제 oracle까지 대조한 결과만 사용한다.

## 속도와 과거 종료 지연

이번 상태 점검에서도 기본 host admission은 실패했다. CPU idle **0–8.91%**, load1 **14.03–19.32**, pressure가 2까지 올라갔다. CPU/load/pressure 미통과, swap/disk 통과다. 다른 프로젝트 작업을 종료하거나 기준을 낮추지 않았다. 이 상태에서는 A/A 및 정식 7입력 성능 자료를 새로 만들지 않는다.

이전 UI의 Windows 실제 main window를 네이티브 확인창이 있는 상태에서 정상 `WM_CLOSE`로 닫아 **95.24ms·exit 0**을 확인했다. 강제 종료하지 않았다. 새 UI staging의 실제 문서/기본 앱 검수 후 닫기도 **99.80ms·exit 0**이었다. 이는 과거 한 번의 8초 지연 원인을 입증하지 않으며, 과거 원인은 계속 미확정이다.

## 최종 설치·정량 판정

| 항목 | Mac arm64 | Windows 132 x64 |
|---|---:|---:|
| 실제 설치본 파일/폴더 oracle | 5 / 4 | 3 / 4 |
| logical bytes | 102,399 | 52,049 |
| 설치 manifest 전체 hash 확인 | 9개 | 38개 |
| frontend SHA-256 접두사 | `71b58ddcacc0` | `77280faa7f57` |
| 실제 설치본 Escape 취소 | 통과 | 통과 |

Mac `~/Applications/Mac Space Sniffer.app`, Windows `%LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.3.0-GPUI`의 새 설치본을 직접 실행했다. 실제 설치 경로·PID·스캔 완료·파일 oracle을 확인했고 양쪽 창을 검사용 root에 열어뒀다. Mac은 ad-hoc deep/strict 서명과 production QA 옵션 exit 64, Windows도 production QA 옵션 exit 64 및 기존 바로가기 유지 확인. 두 OS의 엔진 전체 SHA는 교체 전과 동일하다. 이전 설치본은 `Before Dialog Fix` / `before-dialog-fix` timestamp rollback으로 보존했다.

Windows 새 UI에서는 실제 파일 선택기로 SNS를 열어 **offline=true·trash-case·파일 1개·49바이트**를 대조했다. 실제 생성한 SNS는 **308바이트**, 보고서는 **75바이트**이며 `restore-me.txt` 경로를 포함한다. 네이티브 폴더 선택 이후 live root·파일 3개·폴더 4개·52,049바이트도 파일시스템과 대조했다. 실제 문맥 메뉴 ‘열기’로 새 시스템 메모장 창이 뜬 것을 정확한 대상 파일·새 PID·visible HWND로 확인하고 해당 검수 창만 정상 닫았다.

검수기는 Windows 공통 대화상자의 **열기(Edit 1148/ComboBox), 저장(Edit 1001/ComboBox), 폴더(Edit 1152/dialog)** 변형을 구분하고, 동일한 소유 프로세스/활성 창/입력/완료 대조 절차로 처리했다. 저장 창의 덮어쓰기 확인 때문에 후속 창이 대기한 시도는 통과로 사용하지 않았다. 자체 SNS의 덮어쓰기를 거절하고 대기창을 정상 취소한 뒤 단계별로 다시 확인했다. 성공 결과와 앞선 오류 원문은 함께 보존한다.

정량 결과는 **드래그 4/4, 최종 설치본 Escape 취소 2/2, Windows 태그 값 6/6**, 새 소스 unit **29/29·30/30**이다. `verification-summary.json`의 **25/25**는 버전을 구분한 원문·경로·파일 해시·내용·카운터의 사후 일관성 검사 수이며, 25회의 독립 벤치마크나 모든 입력의 최종 패치 재실행을 뜻하지 않는다.

자료 복사 중 호스트 Data 볼륨이 가득 찼다. 완료한 자체 Rust target 캐시만 `cargo clean --target-dir /private/tmp/sniffer-gpui-20261123/target`으로 정리했다(6,360개·1.9GiB). production/QA 실행 파일·설치본·소스·복구본·이전 근거는 보존하고 소스 해시를 다시 확인했다. 다른 프로젝트 작업은 중단하지 않았다. 이후 여유 공간도 약 1.78GiB로 기본 성능 gate의 2GiB보다 적었다. 자체 Windows UI/launch 예약 작업도 정리했다.

남은 것은 안정된 호스트에서의 정식 성능 판정·168B 후보 채택, 과거 8초 지연의 재현/원인 확인이다. 모든 키/창 상태/보조기술 조합과 모든 preview 형식의 전수 검사는 이번 통과 범위가 아니다.

[정량 JSON·실행 원문·패키지·소스](validation/gpui-os-input-2026-11-24/README.md) · [전체 TODO](GPUI_MIGRATION_TODO.md).

