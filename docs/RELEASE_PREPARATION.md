# GPUI 0.3.0 설치파일·배포 준비

Current installation: [Spacer 0.3.1](SPACER_0_3_1_INSTALL.md), installed on both platforms on 2026-11-25. The 0.3.0 evidence below is historical.

패키지 revision `20261124.1`은 [검증된 현재 설치본](WORK_HANDOFF.md)의 포장 버전이다.
앱 바이너리를 재빌드하지 않으며, 미채택 168B 성능 후보를 포함하지 않는다.
설치파일 제작과 외부 공개/원격 설치 교체는 별도 상태로 기록한다.

**제작 완료:** Mac DMG 생성·CRC·readonly mount 후 전체 9개 파일 SHA·서명과
production QA 명령 거부 확인. Windows NSIS EXE 생성 후 전체 38개 payload 파일
재추출 SHA 대조 통과. 앱 재빌드0·168B 후보 포함0·기존 설치 교체0·외부 게시0.

## 산출물

출력: `~/Downloads/SpaceSniffer-0.3.0-20261124.1-Release/`.

[전달 폴더](validation/release-preparation-2026-11-24/README.md).

| 파일 | 대상·동작 |
|---|---|
| `SpaceSniffer-0.3.0-20261124.1-macos-arm64.dmg` | Apple Silicon/macOS14+, Applications로 앱 드래그 |
| `SpaceSniffer-0.3.0-20261124.1-windows-x64-setup.exe` | x64 Windows, 현재 사용자 설치·시작 메뉴·제거 등록 |
| `SHA256SUMS.txt` | 전달받은 설치파일 무결성 확인 |
| `Evidence/verification.json` | 실제 수행한 검증과 미수행 범위 |

Windows는 `%LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.3.0-GPUI-20261124.1`에
별도 설치한다. 기존 `0.3.0-GPUI`와 바로가기를 덮어쓰거나 실행 중 앱을 종료하지 않는다.
시작 메뉴의 버전별 폴더에서 실행한다. 같은 revision이 이미 있으면 설치를 거부한다.
제거는 해당 payload의 명시된 파일만 삭제하고 사용자 데이터·이전 버전·알 수 없는 파일은
보존한다. 실행 파일이 사용 중이면 먼저 정상 종료하도록 안내한다. 자동 실행하지 않는다.

Mac도 설치본을 자동 교체하거나 실행하지 않는다. 이미 실행 중인 버전을 교체하려면 먼저
정상 종료한 뒤 복사한다. 이전 사용자 preview/rollback/Recovery는 유지한다.

## 제작·검증

```sh
python3 scripts/gpui-app/prepare-installers.py \
  --source-delivery "$HOME/Downloads/SpaceSniffer-GPUI-0.3.0-OS-Input-20261124" \
  --output "$HOME/Downloads/SpaceSniffer-0.3.0-20261124.1-Release"
```

macOS의 ditto/hdiutil/codesign, NSIS makensis와 7z를 사용한다.
원본 GUI/backend SHA를 고정하고 전체 manifest 대조, production QA 명령 거부,
DMG readonly mount 후 payload/서명 재검증, EXE에서 payload 재추출 후 전체 SHA를 대조한다.
출력 경로 덮어쓰기를 거부하며 임시 staging은 성공/실패 모두 정리한다.

Windows 설치 프로그램의 clean install/재설치 거부/실행 중 제거 거부/제거/이전 버전 보존은
**새 설치 프로그램의 runtime 시험 대상**이다. 기존 앱의 실제 Windows 검수나 EXE payload
해시 대조만으로 이 시험을 통과했다고 하지 않는다. 다른 작업을 중단하지 않는 별도
Windows 검수 환경에서 수행한다.

후속 Windows 시험은 다음 oracle을 사용한다.

1. 일반 사용자 clean install: UAC 상승 없이 완료, manifest 38개 파일 SHA 일치,
   시작 메뉴/현재 사용자 제거 항목 생성, 자동 앱 실행 0.
2. 시작 메뉴에서 실행: 자체 fixture 스캔·트리맵 이동·preview·정상 종료,
   GUI/backend/helper 잔류 0. 기존 버전의 파일 SHA와 바로가기 불변.
3. 같은 revision 재설치: 기존 설치 거부, 파일 SHA와 등록 상태 불변.
4. 앱 실행 중 제거: 제거 거부와 앱 유지. 닫은 후 제거 재시도.
5. 제거: manifest 파일/버전별 바로가기/제거 등록 삭제. 설치 폴더에 별도 만든
   `preserve-user.txt`, 사용자 Recovery, 이전 버전 파일은 그대로 보존.

## 배포 상태·남은 조건

- 설치된 앱 교체와 외부 게시/업로드는 수행하지 않는다.
- Mac은 ad-hoc 서명, Windows는 unsigned다. 공인 서명/공증 완료 패키지가 아니다.
- 현재는 조직 내 검수용 전달 준비다. 외부 공개 전 Windows installer runtime 검수,
  Developer ID/notarization·Authenticode와 의존성 재배포 고지 검토를 완료한다.
- 정식 속도 판정·168B 후보 배포·과거 종료 지연 원인은 [후속 목록](WORK_HANDOFF.md)에 유지한다.
