# 스캔 실행기·필터 scratch 구현 검증 — 2026-11-09

이번 범위는 **E02의 scan 실행 경계/취소/admission**과 **E01의 worker 전용 context 재사용**이다. node/page pool 전체, ArtifactWorker I/O 격리, 전체 TODO 완료가 아니다. UI 배치·현재 애니메이션·파일 집계/필터 의미는 바꾸지 않았다.

## 책임 분리와 실행 계약

| 모듈 | 소유 책임 | 소유하지 않는 것 |
|---|---|---|
| [ScanService](../Sources/SpaceSnifferCore/ScanService.swift) | root/subscriber/watch, generation/revision, 진행/완료 승인, 태그 일관성 | OS 작업 실행 슬롯·스레드 정책 |
| [ScanAdmission](../Sources/SpaceSnifferCore/ScanAdmission.swift) | process 공유 active 슬롯8, FIFO 대기64, 취소·포화·종료, Dispatch 실행 | root snapshot 수정·필터 의미·UI |
| [ScanWork](../Sources/SpaceSnifferCore/ScanWork.swift) | 기존 full/scoped scan·상위 fallback·merge 조합, DirectoryScanOperation 주입 경계 | root 수명·공개 revision·전역 admission |
| [FilterScratch](../Sources/SpaceSnifferCore/FilterScratch.swift) | 창별 projection worker 전용 ancestor context bytes | published membership/weights·NodeTable pages |

ScanAdmission은 고정 OS thread8개를 만드는 구현이 아니다. Dispatch가 스레드를 관리하며 **허가된 작업 슬롯**을8개로 제한한다. queued는 대기, admitted는 dispatch 전 슬롯 예약도 포함한다. 실제 scanner 진입은 WorkerTelemetry의 scan.enumeration으로 구별한다. 필터/geometry LatestWorker와 artifact job 최대2/최근32 정책은 별도다.

- queued 취소: FIFO에서 제거, 캡처 해제, scanner 호출0, 완료 callback 한 번.
- running 취소: ScanControl에 요청하고 실제 동기 작업이 반환할 때까지 슬롯을 유지한다. syscall 자체의 즉시 중단이나 취소 지연 상한은 보장하지 않는다.
- 정상/취소 종료: 슬롯을 반납하고 다음 작업을 허가한다. callback은 admission lock 밖에서 실행하며 root actor가 generation을 재검사한다.
- shutdown: 대기 작업은 취소 완료, running은 협력 취소; 새 submit은 거부한다.
- active8+queued64를 넘거나 shutdown된 경우: 새 작업 거부. 파일시스템 issue/크기를 만들지 않고 ScanUpdate.schedulingError → app_status.phase=failed / scan_scheduling_error / notice로 전달한다. 기존 snapshot은 보존할 수 있다. 재시도 시작 시 자기 scheduling 오류 notice만 정리한다.

대기열 상한은 **admission payload 수의 상한**이다. 전체 앱의 창·root·RSS·OS 스레드 수 상한을 뜻하지 않는다. root 경로 정규화와 ArtifactWorker의 동기 I/O 등은 아직 분리되지 않았다.

원본 근거는 W16 newThread `0x45a7c0`의 reuse/상한 원리, 기존 scan/cancel 계약이다. Dispatch·대기64·포화 실패·상한8은 Mac 정책이며 원본 static cap1을 복제하지 않았다. [engine contracts](engine-contracts.json)의 새3파일은 platform으로 분류했다. 기존 W15의 FS/TM node pool을 구현했다고 체크하지 않는다.

## scratch 선택의 할당 근거

Allocations xctrace는 [연결 오류](validation/scan-resource-2026-11-09/xctrace-failure.log)로 사용할 수 없었다. 보안 설정을 바꾸지 않고, 소유한 synthetic process의 MallocStackLogging/NoCompact와 malloc_history -allEvents로 대체했다. [집계·source/probe/raw hash](validation/allocations-adopted-2026-11-09/report.json)에 압축 원문을 연결했다.

2천 노드 metadata tree를5회 만드는 builder에서 NodeTable.append 경로의 ALLOC는20회/1,885,080bytes, path 생성 위치는10,000회/640,000bytes였다. 실제 타입은 DiskNode 구조체이며 노드마다 객체가 하나씩 할당된다는 전제가 성립하지 않는다. 이 표본이 page pool의 무효용을 증명하지는 않는다. page 저장소와 문자열/경로 비용을 별도 후보로 남긴다.

같은2천 노드와 tag 조건의 **실제 membership40회**를 비교했다. 아래는 ScanFilter/FilterScratch membership stack에 속한 ALLOC만 집계했으며 VM_ALLOC·그 외 코드의 할당은 포함하지 않았다.

| membership 내부 | fresh | context 재사용 |
|---|---:|---:|
| ALLOC 호출 | 80 | 45 |
| 누적 allocated bytes | 162,640 | 83,625 |

이는 peak/live RSS가 아니다. toy scratch 배열 실험도 raw에 있으나 **production 판정은 실제 membership 경로**로 했다. 결과 membership checksum은 같고, 새2개 회귀에서 tag/hidden/folder 조건 교대·취소 이후 재평가·oversized eviction·frozen 결과 불변을 확인했다.

재사용하는 것은 private UInt8 context뿐이다. 모든 방문 node의 상태를 새 부모 상태로 덮어쓴다. 반환하는 Bool membership, weights, snapshot page는 매번 독립 결과로 유지해 이전 reader를 덮어쓰지 않는다. context의 **실제 capacity가1MiB를 넘으면 pass 종료 시 보유하지 않는다**. 헤더/lock을 포함한 물리 RSS budget이라는 뜻은 아니다. root/load/reset/창 종료에서는 소유자를 교체해 UI가 running pass의 lock을 기다리지 않게 했다. 메모리 압력 callback·프로세스 전체 scratch budget·node/page 재활용은 남은 평가다.

25만 노드 membership40회 release 5쌍의 compute 중앙값은 fresh **1.312s**, reuse **1.309s**다. [원시값](validation/scan-resources-2026-11-09.json). fixture 생성은 compute 시간에서 제외했고 checksum 비용은 포함했다. CPU 시간·전체 앱 RSS·UI 속도의 뚜렷한 개선을 주장하지 않는다. 채택 이득은 확인된 누적 할당 감소이며, context 보유량은 별도 제한한다.

## scan 상한 비교와 선택

32개 독립 root 각각1천 파일×256bytes의 따뜻한 파일시스템 fixture에서1/8/32 roots를 비교했다. [5회 순차 회전 실행 raw·manifest·source/probe hash](validation/scan-admission-2026-11-09.json). fixture 생성은 제외했다. baseline은 기존 서비스처럼 utility Task.detached를 callback/continuation으로 완료하며 Task handle을 await하지 않는다.

| roots | 기존 detached(ms) | K1 | K2 | K4 | K8 |
|---|---:|---:|---:|---:|---:|
| 1 | 4.06 | 4.17 | 4.15 | 4.07 | 4.47 |
| 8 | 11.37 | 26.68 | 15.27 | 11.80 | 11.56 |
| 32 | 35.93 | 98.32 | 55.86 | 43.97 | 35.94 |

K1/K2는 다중 root 처리 시간을 늘렸다. K8은 이 fixture에서 기존 처리 시간에 가까우면서 admission 상한을 제공해 기본값으로 선택했다. 보편적인 최적 K나 디스크 전체 스캔 가속을 증명한 것은 아니다. 차이/분산과 상세 RSS는 raw를 따르며, 차가운 디스크·외장/NFS·다른 Mac·대규모 실제 develop은 미검증이다. 단일 root의4ms 전후 micro 표본으로 확정적인 속도 개선/회귀율을 주장하지 않는다.

추가로32개의 최소50ms blocking sleep과20k-node CPU filter를 함께 실행했다. 이는 디스크가 아닌 synthetic wait다. 실제 operation 안에서 센 최대 동시 작업 중앙값은 기존 **10**, K8 **8**이었다. CPU filter 응답 중앙값은 각각 **6.69ms / 6.62ms**다. 응답 속도 향상이나 UI p95를 주장하지 않는다. K4의 전체 wait 처리 시간이 더 길어지는 tradeoff도 [raw](validation/scan-resources-2026-11-09.json)에 보존했다. operation counter는 callback 대기를 제외하며 OS thread 수가 아니다.

## 회귀·진단·패키징

- 이번 기준선의59개 assertion은 통과했지만 **TSAN 경고7개와 exit1**이 재현됐다: [원문](validation/scan-resource-2026-11-09/baseline-tsan-warning.log). 이전에 보관한 clean 실행과 별개다. mutable Job payload 생성/인계/take 구간에 명시적 NSLock 동기화를 넣었고 suppression은 사용하지 않았다. 채널에 의존한 인계만으로 충분하다고 가정하지 않는다. 경고만으로 런타임 채널의 memory-order 원인을 단정하지 않는다.
- 최종 Swift **68개 TSAN, exit0/경고0**: [로그](validation/scan-resource-2026-11-09/final-tsan.log). 추가9개는 admission4·root scheduling3·scratch2다. FIFO/포화/대기 캡처 해제, running 취소의 슬롯 유지, shutdown 한 번, 1천 concurrent submit 완료 한 번, root 재구독/대기 rescan 세대, 포화의 비파일시스템 오류, scratch frozen/eviction/조건 교대 검사다.
- Python bridge **6개 통과**: [로그](validation/scan-resource-2026-11-09/python-tests.log).
- 별도 QA 실제 STDIO **101요청**: [결과](validation/scan-resource-2026-11-09/mcp-results.json), [캡처](validation/scan-resource-2026-11-09/mcp-capture.png). 새 admission 통계·scheduling error 필드, 탐색 재사용, 동일 설정·복합 요청, tag toggle, SNS/TXT job와 기존 output 거부를 확인했다. 포화 실패는 Core의 주입된 scanner/작은 capacity로 검사했으며 GUI에서65개 창을 열어 재현한 것은 아니다.
- Universal arm64/x86_64 build·strict signature: [로그](validation/scan-resource-2026-11-09/universal-build.log). 최종 packaged CLI로 SNS→TXT 왕복 바이트·3,145,728 logical bytes/2파일과 packaged MCP 일치를 확인했다: [결과](validation/scan-resource-2026-11-09/package-cli-check.json). 실제 runtime QA는 Apple Silicon이다.
- 새 ZIP SHA-256: `550fd9fd5c327e9c6b1ea321b2eb17c77d58d2f561306bd7c96efc197e44b953`. 메인 앱이 idle이고 실행 중인 job/구독이 없음을 [재실행 전](validation/scan-resource-2026-11-09/main-before.json)에 확인한 뒤 새 bundle로 재실행했다. [재실행 후](validation/scan-resource-2026-11-09/main-after.json)에 새 PID·idle·실제 scan_limit8/capacity64를 확인했다.

기존 smoke의 scoped rescan/stop은 새 cycle의 실제 완료·실행 중 취소 전체를 증명하지 않는다. admission의 취소/세대는 별도 controlled 회귀로 보완했다. UI/geometry/VoiceOver 변경은 하지 않았으며 전체 module16개 추출 완료로 보고하지 않는다.

## 재현 명령

```sh
swift test --sanitize=thread
swiftc -O -g -parse-as-library Sources/SpaceSnifferCore/*.swift scripts/bench/allocation-probe.swift -o /tmp/sniffer-alloc
python3 scripts/bench/profile-allocations.py --probe /tmp/sniffer-alloc --output /tmp/sniffer-allocation-new
```

scan/response probe는 각 swift 파일을 같은 Core 소스와 release로 컴파일한다. fixture는 measure-scan-admission.py manifest의32 roots×1천 파일로 준비한다. 빌드/프로파일러와 성능 비교를 겹치지 않고 새 output으로 실행한다.

```sh
python3 scripts/bench/measure-scan-admission.py --probe dist/scan-executor-2026-11-09/scan-admission --fixture dist/scan-executor-2026-11-09/fixture --output /tmp/sniffer-scan-new.json
python3 scripts/bench/measure-scan-resources.py --directory dist/scan-executor-2026-11-09 --output /tmp/sniffer-resources-new.json
```

E01/E02는 **부분 진행**이다. full node/page pool, 전체 할당 rank/scan·rename·export 경합, ArtifactWorker의 별도 I/O 실행기, OS thread 관측·긴 I/O/메모리 압력·장시간 실제 볼륨 검증은 [TODO](../TODO.md)에 남긴다.
