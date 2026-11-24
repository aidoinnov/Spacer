# 공통 엔진 Windows 실기기 검증

[132번 결과·범위](../../docs/WINDOWS_132_PHASE1_RESULTS.md). Windows Swift6.2.4와 MSVC x64·Windows SDK가 설치된 개발 환경에서 실행한다. Windows 전용 테스트의 파일 I/O adapter는 검증용 Foundation 구현이며 production Win32 reader가 아니다.

Mac에서 source 묶음을 생성한다. output이 있으면 덮어쓰지 않는다.

```sh
python3 scripts/windows-validation/package_sources.py --output /private/tmp/sniffer-windows-transfer
```

이 폴더를 Windows의 새 전용 폴더로 복사한 뒤 실행한다.

```bat
run-tests.cmd C:\Users\YourName\sniffer-windows-transfer
```

`run-tests.cmd`는 `C:\BuildTools\Common7\Tools\VsDevCmd.bat`로 x64 개발 환경을 구성한다. 기존 Visual Studio 설치를 사용하면 그 한 줄을 해당 경로로 조정한다. PC 자체의 보안 설정 변경이나 재부팅은 runner가 수행하지 않는다.

PowerShell runner는 인접 manifest의 ZIP SHA와 모든 source SHA를 검사한다. 기존 `engine` 디렉터리가 있으면 중단해 수정본/결과를 덮어쓰지 않는다. debug/release 로그·exit code·경과 시간을 기록한다. `test-status.json` exit0과 실제 XCTest22개 실패0 메시지를 모두 확인한다.0 tests만 출력된 경우를 통과로 집계하면 안 된다.

19개 공통 계약과 Windows 전용 실제 파일3개 테스트가 포함된다. 새3개는 Windows에서만 실행되며 Mac에서 skip된 테스트를 Windows 통과로 집계하지 않는다. 파일9,605개를 만들고 `defer`로 전용 fixture를 삭제한다. 테스트가 프로세스 crash로 중단됐다면 해당 전용 `sniffer-win-*` fixture가 남았는지도 확인한다.

현재 runner는 기능 검증이며 전체 Windows 앱, Win32 identity/allocated-size/reparse/watch, Windows 성능 gate를 제공하지 않는다.132번에서 실제 실행한 스크립트는 [검증 폴더](../../docs/validation/windows-132-2026-11-23)에 `executed-*`로 보존했다. 인증 정보는 스크립트나 source 묶음에 넣지 않는다.
