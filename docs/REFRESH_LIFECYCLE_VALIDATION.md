# B08.08 이벤트 폭주·취소·감시 세대·큐 수명 검증

2026-11-09. 이전 [큐 구현과 성능 측정](REFRESH_QUEUE_VALIDATION.md)에서 남긴 B08.08을 추가 검증한다. 전체 최적화 TODO 완료를 뜻하지 않는다.

## 검증을 가능하게 한 내부 경계

ScanService에 internal MonitorFactory/async delivery 경계를 두었다. public initializer는 기존 DirectoryMonitor/FSEvents를 그대로 만들고 serial FSEvents callback에서 Task를 통해 actor로 전달한다. 테스트에서도 동일한 `changed`의 monitorGeneration/구독 guard를 통과한다. 별도 테스트용 packing 구현이나 guard 우회 경로는 없다. 공개 MCP 도구·UI 동작·필터·스캔 정책은 변경하지 않았다.

RefreshQueue의 internal 진단은 count/slot과 저장소의 **약한 참조 witness**만 반환한다. 진단 객체가 Storage를 강하게 보유하거나 큐 사본을 저장하지 않는다. 실제 Storage 객체의 소멸을 관측하므로 slot=0 숫자만 확인하는 검사보다 직접적이다. Storage 소멸 시 FIFO 배열·두 index arena·free list 소유권도 함께 해제된다. Swift allocator가 OS에 즉시 페이지를 반환하거나 프로세스 RSS가 일정 byte만큼 줄었다는 의미는 아니다. 전체 deep retained byte 크기를 합산하는 profiler는 아니다.

이 추가 코드는 Mac 관측/의존 경계다. 원본 W09의 packing/FIFO 계약과 근거 주소는 변경하지 않는다. 원본 Windows에 해당 factory/witness가 존재한다고 주장하지 않는다.

## 결정적 callback 주입 검사

[RefreshLifecycleTests](../Tests/SpaceSnifferCoreTests/RefreshLifecycleTests.swift)의 `testOldMonitorCallbackCannotQueueAfterReplacementOrRootRecreation`:

1. 48분기 fixture를 스캔하고 monitor delivery를 보존한다.
2. 감시 off/on 후 새 monitor를 구성한다. 실행 중인 root scan worker를 semaphore로 정지시킨다.
3. 현재 delivery로 서로 독립된 48개 파일 이벤트를 넣어 큐가 인덱스로 전환되는지 확인한다.
4. 이전 delivery로 mustRescan root 이벤트를 전달한다. 현재 48개 scope를 root 하나로 덮지 못하는지 확인한다. await delivery 이후 검사하므로 callback 처리 전의 빈 상태를 잘못 통과시키지 않는다.
5. stop에서 실행 중 control의 취소, pending=0/slots=0, weak Storage 해제를 확인한다.
6. 마지막 구독을 없앤 뒤 같은 경로를 다시 구독한다. 이전 Entry의 callback이 새 root를 재스캔하거나 pending에 들어가지 못하는지 확인한다.

주입은 실제 guard를 결정적으로 검사하기 위한 것이며, OS가 임의로 오래된 callback을 해당 순서로 전달했다는 주장은 아니다.

## 실제 FSEvents + 실행 중 취소 + 저장소 해제

`testRealFSEventsBurstCancelsRunningScanAndReleasesPromotedQueue`는 **기본 public initializer**, 실제 DirectoryMonitor, 실제 DiskScanner를 사용한다. 기존 48개 파일의 내용을 1→2 bytes로 바꾸며, event delivery를 주입하지 않는다. 디스크 작업이 실행된 것을 확인한 상태에서 scanner 경계만 잠시 막아 actor의 대기 큐를 관측한다.

생성 직후 이벤트가 가라앉은 뒤 root rescan을 시작한다. 실행 중 worker가 막힌 상태에서 48개 파일을 실제 수정하고, pending=48과 index slot>0 및 살아 있는 Storage witness를 요구한다. 단순히 FSEvents callback 횟수만 보고 index 사용으로 간주하지 않는다. 이 조건을 만족하지 않으면 테스트가 timeout으로 실패한다.

그 상태에서 statistics actor 응답 시간을 기록하고 stop을 호출한다. 실행 중 control이 취소되고 실제 Storage weak 참조가 nil이 되는지 확인한다. worker를 풀어 완료를 받은 뒤 재스캔하여 파일 48개/논리 96 bytes 및 전체 DiskScanner와 같은 allocated 합계로 수렴하는지 확인한다. 마지막 unsubscribe 후 root=0도 검사한다. scanner gate는 실패 시 12초 뒤 풀리며 defer에서도 해제한다.

최종 Swift ThreadSanitizer **90개**, 실패 0·경합 보고 0. 실제 event 큐 **48개 / 152슬롯**을 관측했고, 취소 뒤 Storage 해제/pending=0/복구 logical=96 bytes/root=0을 모두 확인했다. statistics 직접 actor 요청은 이 표본에서 **9.791µs**였다. 단일 통합 표본이며 시간 보장이나 전후 개선 배율이 아니다. Python **6개** 통과. [전체 TSAN](validation/refresh-lifecycle-2026-11-09/tsan.log), [Python](validation/refresh-lifecycle-2026-11-09/python-tests.log).

## 실제 앱 및 패키지

별도 lifecycle QA 앱에서 기존 20개 도구와 projection/admission/artifact/PNG 통합 검사 **MCP 87회**, 추가 실제 48분기 감시 교체 burst **27회** 요청을 통과했다. [통합 결과](validation/refresh-lifecycle-2026-11-09/mcp-results.json), [burst 결과](validation/refresh-lifecycle-2026-11-09/burst-results.json).

Universal **arm64/x86_64**, ad-hoc 서명 검사·packaged MCP 동일성 확인. [빌드](validation/refresh-lifecycle-2026-11-09/build.log), [패키지](validation/refresh-lifecycle-2026-11-09/package.json). ZIP SHA-256: `2dd06a1c23c373b5e5c5d707abfc717af5a337b711723bb910918ba82dc4f202`. 버전 ZIP `dist/releases/refresh-lifecycle-2026-11-09-2dd06a1c23c3.zip` 보존.

## 측정과 범위의 한계

이번 변경은 관측 경계·검증 보강이다. 이전 큐 benchmark 100표본의 소스 hash를 이번 소스로 바꾸지 않았다. 당시 소스·probe·버전 ZIP을 보존하고 `check-refresh-validation.py --historical`로 검사한다. 기존 성능 수치는 당시 구현의 기록이며 이번 바이너리에서 새로 측정한 수치가 아니다.

실제 디스크 worker를 의도적으로 지연시킨 통합 검사다. 전체 볼륨에서 발생한 자연적인 수백만 이벤트 폭주나 긴 디스크 장애의 성능을 대표하지 않는다. weak 소멸은 실제 큐 소유 객체의 해제를 증명하지만 OS allocator/RSS의 반환량은 증명하지 않는다. status 직접 actor 시간과 실제 앱 MCP 왕복 시간을 구분한다. Windows 동적 동등성·실제 Intel 하드웨어 검증은 별도 미완료다.

재현:

```sh
swift test --sanitize=thread
python3 scripts/check-refresh-lifecycle-validation.py
python3 scripts/check-refresh-validation.py --historical
```

Xcode의 `--filter` test discovery helper가 TSAN dylib 로드를 거부한 시도는 [로그](validation/refresh-lifecycle-2026-11-09/filtered-discovery-failure.log)에 보존했다. Xcode 서명/시스템 보안 설정을 변경하지 않고 전체 test suite 실행으로 검증한다.


QA 앱을 종료했고 메인 앱의 idle/jobs=[]를 확인한 뒤 최종 빌드로 재실행했다. 새 PID·idle을 read-only MCP로 확인했다. [재실행 전](validation/refresh-lifecycle-2026-11-09/main-before.json), [재실행 후](validation/refresh-lifecycle-2026-11-09/main-after.json).


후속 B05 단계부터 현재 소스/ZIP은 변경된다. 이 문서의 90개 테스트와 버전 ZIP/source 기록은 `check-refresh-lifecycle-validation.py --historical`로 검사한다. 과거 기록을 새 소스의 측정값으로 바꾸지 않는다.
