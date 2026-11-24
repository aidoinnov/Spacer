# Windows 앱 빌드·실행

[실행 결과와 구조](../../docs/WINDOWS_APP_RESULTS.md). Windows10 x64에서 Swift6.2.4, MSVC x64, Windows SDK10.0.22621, .NET Framework 환경으로 검증했다.

```bat
scripts\windows-app\build.cmd
WindowsApp\bin\SpaceSnifferLauncher.exe
```

빌드 스크립트의 BuildTools/Swift 경로는 검증한132번 개발 환경 기준이다. 빌드된 폴더에는 Swift runtime DLL도 복사한다. launcher는 PATH를 Windows/System32만으로 제한해 SDK 경로에 우연히 의존하지 않게 한다. 별도 PC는 해당 OS/.NET/VC runtime 조건을 갖춰 검증해야 한다.

UI는 WinForms, 스캔은 별도 Swift 프로세스다. `WindowsScan.exe --scan ROOT --output NEW.json`의 진행은 JSONL stdout, 취소는 stdin의 `cancel` 한 줄이다. 결과에는 schema1·node tree·logical/allocated·오류·경계·취소 상태가 담긴다. UI에서 해당 프로세스의 lifecycle과 generation을 관리한다.

```bat
swift test --package-path Packages\SpaceSnifferWindows -c debug --jobs 2
swift test --package-path Packages\SpaceSnifferWindows -c release --jobs 2
```

플랫폼 경계 확인:

```sh
python3 scripts/windows-app/check-boundaries.py
```

Windows 조립 지점은 `WindowsScanner`, 경로 전략은 `WindowsPath`, 정책은 `WindowsScanPolicy`, I/O는 `WindowsDirectoryReader`+C target이다. 공통 worker에는 Windows/macOS 분기를 넣지 않는다.

GUI QA는 로그인된 interactive desktop에서 다음처럼 새 전용 output 폴더를 사용한다. 실제 파일을 생성하므로 사용자 데이터 폴더를 output으로 쓰지 않는다.

```bat
WindowsApp\bin\SpaceSnifferLauncher.exe --self-test C:\Temp\sniffer-ui-new-run
```

`ui-result.json`의 `status=passed`와17개 흐름·파일 수·용량, 실제 창 session/visible을 확인한다. 이 모드는 fixture와 snapshot/TXT/PNG를 남기므로 QA 앱을 닫고 fixture를 따로 정리한다. 검증 전용17개 흐름을 일반 사용자 화면의 체크리스트로 노출하지 않는다. SNS는 이 버전의 JSON 스냅샷과 다른 포맷이다.
