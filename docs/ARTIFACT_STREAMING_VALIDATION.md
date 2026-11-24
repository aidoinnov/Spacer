# Artifact I/O·SNS/TXT streaming 검증 — 2026-11-09

이번 범위는 B07과 E02의 ArtifactWorker blocking I/O 분리다. UI 배치·애니메이션·파일 집계/필터 문법은 유지했다. W19의 순차 출력 대응이며 Windows 실행 동등성이나 전체 최적화 완료가 아니다.

## 책임·호출 경계

| 책임 | 실제 소유자 |
|---|---|
| async API·immutable 입력 캡처·판정 시각 고정 | [ArtifactWorker](../Sources/SpaceSnifferCore/ArtifactWorker.swift) |
| blocking 작업의 직렬 실행·bounded 접수 | [ArtifactIOExecutor](../Sources/SpaceSnifferCore/ArtifactIOExecutor.swift) |
| 한 번의 membership·weights·ancestor selection | [ArtifactSelection / ArtifactProjection](../Sources/SpaceSnifferCore/ArtifactSelection.swift) |
| SNS field 또는 TXT path의 순수 직렬화 | [SNSSnapshot](../Sources/SpaceSnifferCore/SNSSnapshot.swift), [Report](../Sources/SpaceSnifferCore/Report.swift) |
| byte 소비 경계 | [ArtifactByteSink](../Sources/SpaceSnifferCore/ArtifactByteSink.swift) |
| staging·write/close·게시·실패 cleanup | [ArtifactFileTransaction / ArtifactFileSink](../Sources/SpaceSnifferCore/ArtifactFileTransaction.swift) |
| selection/codec/transaction 조합 | [ArtifactTransfer](../Sources/SpaceSnifferCore/ArtifactTransfer.swift) |
| Foundation volume/trash | [DesktopFileActions](../Sources/SpaceSnifferCore/DesktopFileActions.swift) |

ArtifactWorker actor는 file/codec 작업을 실행하지 않고 serial Dispatch queue를 await한다. 기존 직렬 작업 순서를 유지하며 예약1+대기64, 초과 busy를 제공한다. MCP job 접수2/최근32와 다른 정책이다. scan admission8과도 별개라 앱 전체 I/O 동시 상한8이라는 뜻이 아니다. actor 대기 중 다른 요청/상태 처리는 계속할 수 있다.

executor는 enqueue 전 Swift task cancellation을 확인한다. **접수 후 operation 취소 API는 추가하지 않았다.** 접수된 파일 작업은 기존처럼 완료 또는 I/O/codec 오류까지 실행된다. snapshot_load의 세대·artifact token 검사는 그대로 유지하며 stale UI 반영을 막는다. 프로세스 종료 시 job 복구·영속화는 없다.

## 판정·형식 보존

TXT는 한 시각의 leaf membership를 한 번 평가하고 weights를 만든 뒤 ancestor 포함을 전파한다. 원본 leaf flags를 먼저 부모 포함으로 바꾸지 않으므로 합계를 중복 가산하지 않는다. zero-byte 파일 포함 여부를 weights>0로 대체하지 않는다. SNS 필터 저장은 weights 없이 selection만 만들고 원래 node 크기·태그/flags를 기록한다. 필터된 folder totals를 임의로 재작성하지 않는다.

CLI는 source-bound ArtifactProjection 하나를 summary와 SNS/TXT 출력에 공유한다. UI/MCP는 snapshot/filter/hidden/mode/root를 값으로 전달하고 ArtifactWorker 접수 시 판정 Date를 고정한다. 이는 화면의 과거 projection 시각과 같다는 보장은 아니다. 대기 중 데이터/필터/탐색이 바뀌어도 해당 작업은 캡처 입력으로 끝난다.

SNS/Data API와 file stream은 같은 record emitter를 소비한다. UTF16LE Base64, LE integers, FILETIME, v4 field 순서·tag/flag·각 노드 종료 bytes를 유지했다. TXT/String API와 stream은 같은 visitor를 사용해 UTF8/CRLF·파일 우선·크기 내림차순·reverse-ID 동률을 유지한다. 공개 Data/String API는 기존 결과를 제공하지만 파일 저장 경로에서는 전체 Data/String을 만들지 않는다.

변경 전 writer를 [독립 reference](../Tests/SpaceSnifferCoreTests/LegacyArtifactReference.swift)로 보관했다. [stream 회귀](../Tests/SpaceSnifferCoreTests/ArtifactStreamingTests.swift)는 Unicode/emoji·Windows path·flags/attrs/tags·0바이트·빈 결과·root/file/folder scope·hidden/filter 조합·고정 시간 경계를 비교한다. 기존 독립 SNS golden bytes와 decoder 검증도 유지했다. W19 원본 근거는 `0x408a80`, `0x408a10`, `0x416650`, Simple file list preset `0x413b30`/정렬 `0x46b6b0`이다. [contract](engine-contracts.json)에서 format 의미와 Mac I/O 구현을 분류했다.

## 출력 transaction의 보장·한계

1. 출력과 같은 parent에 UUID staging을 O_CREAT/O_EXCL/O_NOFOLLOW로 만든다. 새 파일은 umask를 따르며 overwrite에서는 기존 regular target의 POSIX 접근 bits를 보존한다.
2. 64KiB payload buffer로 기록한다. 큰 단일 chunk는 직접 write하고 short-write를 끝까지 처리하며 EINTR은 재시도한다. producer/IO 오류 시 publish하지 않는다.
3. flush 후 close가 성공해야 한다. close 오류는 ambiguous fd를 재사용해 다시 close하지 않는다. 게시 직전 staging dev/inode를 확인한다.
4. UI/CLI overwrite는 rename으로 교체한다. MCP 미존재 정책은 renamex_np(RENAME_EXCL)로 게시한다. exists 확인 후 일반 rename을 하는 방식이 아니다. 로컬 SDK sys/stdio.h에서 이 API의 macOS10.12 availability를 확인했고 배포 기준은14다.
5. 실패 cleanup은 알려진 staging inode만 대상으로 하며 destination은 unlink하지 않는다. staging이 다른 inode로 바뀌면 게시/삭제하지 않는다. 정상 commit 뒤 deinit도 output을 지우지 않는다.

short/zero write, EINTR, partial ENOSPC, close failure, publish EACCES, exclusive race, 임시 inode 교체를 주입했다. UI atomic 교체의 permission bits와 symlink target 미변경도 확인했다. 기존 Foundation atomic writer는 별도 synthetic 실험에서0640 mode를 보존하고 symlink 자체를 regular file로 교체했으며 custom xattr는 보존하지 않았다. 새 코드가 모든 ACL/확장 metadata를 보존한다고 약속하지 않는다.

이는 **로컬 namespace atomicity**다. fsync/crash durability, SIGKILL 뒤 자동 staging 청소, 적대적인 same-UID process가 namespace를 바꾸는 모든 경쟁을 방어하는 보장은 아니다. close/파일시스템 오류 후 cleanup도 best effort다. 출력 parent는 자동 생성하지 않는다. 데이터 검증 오류나 읽기 오류는 job failed/기존 UI 오류 경로로 전파한다.

## 비용 비교

[5회 교차·40 process raw](validation/artifact-export-2026-11-09.json). 25만 파일 metadata·100 branches, *.bin, 전체 또는 첫 branch의1250선택 파일을 저장했다. 실제 디스크 출력은 시간에 포함하고 fixture 생성은 시간에서 제외했다. process peak RSS는 fixture를 포함하며 SwiftUI/전체 앱 비용은 아니다. 모든 output SHA-256은 child 종료 후 별도 process에서 읽어 RSS 측정을 오염시키지 않았다.

baseline은 독립 이전 writer와 직렬 actor의 기존 ID/weights/String/Data 경로다. 새 경로는 production ArtifactWorker/Transfer를 사용했다. release -O/whole-module-optimization으로 컴파일했고 빌드/프로파일러와 측정을 겹치지 않았다.

| 형식·범위 | 경과시간 중앙값(ms), 이전→새 | process peak RSS 중앙값(MiB), 이전→새 |
|---|---:|---:|
| txt-all | 125.46 → 86.50 | 108.45 → 81.64 |
| sns-all | 203.87 → 183.45 | 111.84 → 90.33 |
| txt-focus | 63.94 → 41.75 | 81.09 → 81.05 |
| sns-focus | 29.75 → 31.15 | 79.22 → 79.17 |

4개 그룹 각각10출력의 bytes와 SHA가 일치했다. 전체 TXT/SNS의 peak RSS 표본 범위는 서로 겹치지 않아 이 fixture의 메모리 이득을 확인했다. 작은 focus SNS는 시간 중앙값이 소폭 늘었고 범위가 겹친다. 모든 범위의 속도 개선이나 전체 앱 최대 RSS 감소를 일반화하지 않는다.

선택 Bool/weights·현재 snapshot·순회 stack·형제 정렬·가장 긴 경로/encoded name 메모리는 남는다. 64KiB는 file payload buffer 상한이며 전체 메모리 O(1)이나 물리 RSS64KiB를 뜻하지 않는다. SNS 입력은 여전히 mapped-if-safe Data와 전체 tree decode다.

## 실제 검증·패키징

- 수정 전 **68개 TSAN**: [기준선](validation/artifact-2026-11-09/baseline-tsan.log).
- 최종 **81개 TSAN/경고0**: [로그](validation/artifact-2026-11-09/final-tsan.log). 추가13개는 stream/transaction/selection10개와 executor3개다. 캡처된 snapshot, 고정 시각, frozen reader, 부분 write, close/게시 실패, 출력 경합, 버퍼 경계, idle capture 해제, actor 대기 중 포화 응답, blocked artifact write와 독립 scan/state 조회를 확인했다.
- Python **6개**: [로그](validation/artifact-2026-11-09/python-tests.log).
- 별도 QA 실제 STDIO **133요청**: [결과](validation/artifact-2026-11-09/mcp-results.json), [PNG](validation/artifact-2026-11-09/mcp-capture.png). SNS/TXT jobs·existing output 거부·세대별 load·navigation/tag/scan counters를 확인했다. 주입 오류는 Core 회귀이며 GUI에서 디스크를 실제로 채운 실험은 아니다.
- Universal arm64/x86_64·strict signature: [빌드](validation/artifact-2026-11-09/universal-build.log), [packaged CLI](validation/artifact-2026-11-09/package-cli-check.json). full/filtered SNS→TXT 왕복과 CLI summary1MiB 일관성을 확인했다. 실제 runtime은 Apple Silicon이며 Intel 하드웨어 실행 검증은 아니다.
- 새 ZIP SHA-256: `f0a92ca9c7312435c1eb20816d325fc4fe34761b072a28b831413fed8d5be590`. exact archive는 `dist/releases/artifact-2026-11-09-f0a92ca9c731.zip`에 보관했다. [이번 source/tests archive](validation/artifact-2026-11-09/source-archive-manifest.json)도 hash로 연결했다.

이전 scan/scratch 검증은 [정확한 당시 source archive](validation/scan-resource-2026-11-09/source-archive-manifest.json)와 함께 historical mode로 검사한다. 변경된 파일은 추정문을 받아들이지 않고 이전에 기록한 SHA와 byte 단위로 일치하는 경우만 보관했다. 이전 benchmark hash를 현재 코드의 측정값처럼 덮어쓰지 않았다. 이전 ZIP은 당시 기록이고 최신 ZIP은 이번 검사로 구별한다.

메인 앱은 [이전](validation/artifact-2026-11-09/main-before.json) idle/실행 job 없음 확인 후 새 bundle로 재실행했다. [이후](validation/artifact-2026-11-09/main-after.json) 새 PID·idle·volume 작업 main_thread_runs0을 확인했다.

## 재현

```sh
swift test --sanitize=thread
# frozen reference의 import만 제거하여 같은 Core module로 benchmark 빌드
swiftc -O -whole-module-optimization -parse-as-library Sources/SpaceSnifferCore/*.swift dist/artifact-2026-11-09/LegacyArtifactReference.swift scripts/bench/artifact-export.swift -o /tmp/sniffer-artifact
python3 scripts/bench/measure-artifact-export.py --probe /tmp/sniffer-artifact --output /tmp/artifact-new.json --work /tmp/artifact-new-outputs
python3 scripts/check-artifact-validation.py
python3 scripts/check-scan-resource-validation.py --historical
```

B07 구현 범위는 완료했지만 전체 TODO는 남아 있다. 실제 큰 develop·외장/네트워크 filesystem·긴 load/export와 메모리 압력, Windows SNS 양방향 runtime, SNS v2/SNF, job persistence/cancel, M16 job registry 추출과 나머지 UI/pool 최적화는 별도 잔여 작업이다.


후속 B08 단계부터 현재 앱 소스/ZIP은 달라진다. 이전 artifact 단계의 byte-exact source archive와 versioned ZIP을 검사하려면 `python3 scripts/check-artifact-validation.py --historical`을 사용한다. 이 모드는 현재 소스로 과거 성능 측정을 대체하지 않는다.
