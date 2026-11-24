# ScanSnapshot validation: bounded incoming-ID storage and cancellation

2026-11-09. `ScanSnapshot.validated`의 수백만 incoming ID `Set<Int>`를 **ceil(N/8) bytes의 bitset + insert count**로 바꿨다. production 수정은 [`Model.swift`](../Sources/SpaceSnifferCore/Model.swift)에 한정했다. 이는 Mac immutable snapshot 검증의 저장 구조 변경이며 Windows SpaceSniffer가 bitset을 쓴다는 주장이 아니다. SNS/DU wire/경로/노드 합계 정책을 새로 만들지 않았다.

## 보존한 의미

원래 메서드 전체를 [Model-before](validation/r-backlog-2026-11-09/validation-bitset/source/Model-before.swift)로 보존하고 [`FrozenSnapshotValidationOracle.swift`](../Tests/SpaceSnifferCoreTests/FrozenSnapshotValidationOracle.swift)에 Set 기반 oracle를 독립 복사했다. [출처 검사](validation/r-backlog-2026-11-09/validation-bitset/oracle-origin.json)는 method rename/wrapper 외에 원래 body가 정확히 일치함을 확인한다.

기존 child ID bounds/parent/id/path/name/size/aggregate overflow/duplicate 검사를 유지한다. child가 유효한 범위임을 확인한 뒤 해당 bit가 이미 켜졌으면 duplicate로 거부한다. 성공한 신규 bit 수가 `N-1`인지 마지막에 확인하여 누락 incoming edge를 거부한다. root bit는 사용하지 않는다. 크기는 `N/8 + (N%8 == 0 ? 0 : 1)`로 계산해 `N+7`의 정수 overflow를 피한다. successful edge 수가 N-1 이하여서 counter도 넘치지 않는다.

원래 method가 nonnegative file/folder/issue count만 요구했던 의미를 유지한다. count를 재계산해 일치시켜야 한다는 새 규칙이나 tag path가 반드시 tree에 있어야 한다는 규칙을 추가하지 않는다. 기존 malformed 입력은 `SnapshotError.invalid`로 거부한다. 토큰이 없으면 이전 호출 구문 `validated()`도 계속 사용한다.

## 취소 API

```swift
public func validated(control: ScanControl? = nil) throws -> Self
```

입구/완료 직전과 node/tag 각 256개, 전역 child edge 각 256개마다 `ScanControl`을 확인하고 `CancellationError`를 던진다. edge counter를 전역으로 두어 거대한 단일 directory의 내부 loop도 취소한다. 검증에서 snapshot을 변경하지 않으므로 취소 시 부분적으로 손상된 tree를 반환하지 않는다. 한 번의 거대한 String 처리까지 쪼개는 시간 상한이나 OS scheduling 보장은 아니다.

SNS/DU import와 task cancellation에 control을 전달하는 호출부는 root가 별도로 연결했다. 이 작업에서는 Model 외 production 파일을 수정하지 않았다. caller가 control을 전달하지 않으면 Swift Task cancellation을 자동 감지하는 API라고 주장하지 않는다. 미리 취소된 control은 malformed 입력에서도 입구에서 CancellationError로 끝난다.

## 독립 검증과 테스트

[`SnapshotValidationBitsetTests.swift`](../Tests/SpaceSnifferCoreTests/SnapshotValidationBitsetTests.swift)는 다음 5개 테스트를 추가한다.

- byte 경계 N=1,2,7,8,9,63,64,65,255,256,257,1025 및 기존의 비정확 count 허용을 frozen oracle와 비교.
- duplicate/missing/root/self/out-of-range edge, parent/id/path/name 오류, negative field, non-directory children, sum overflow 등 27 malformed cases의 판정·오류 class 비교.
- 1,000 seeded mutation corpus의 수락/거부 일치.
- valid/malformed 입력의 pre-cancel CancellationError.
- edge-heavy/node-heavy/tag-heavy 250k 입력의 concurrent cancellation.

공유 `.build`는 root가 소유했다. 이 작업은 Core를 `/private/tmp` scratch로 복사해 independent `swiftc -O -whole-module-optimization` probe를 만들고 실행했다. [`oracle-check-fixed.json`](validation/r-backlog-2026-11-09/validation-bitset/oracle-check-fixed.json)은 frozen Set **2,012 cases 일치**, pre-cancel도 통과했다. [`cancellation-check-fixed.json`](validation/r-backlog-2026-11-09/validation-bitset/cancellation-check-fixed.json)은 세 입력 모두 취소됐고 worker submission부터 완료까지 약 0.38–1.25ms였다. 이는 정확한 cancellation 지점이나 모든 입력에 대한 latency 상한이 아니다.

최초 concurrent timing probe는 main/cooperative executor의 `Task.sleep` 재개가 validation 완료보다 늦을 수 있어 exit133으로 실패했다. 원문/로그를 보존했다. 취소를 보내는 별도 Dispatch thread가 ready 된 뒤 worker를 시작하고 100µs 지연 후 취소하도록 테스트·probe만 고쳤다. production Model은 변경하지 않았다. 최종 probe는 통과했다.

root 보고 기준으로 Model API/DU import selected 13개는 통과했다. 전체 TSAN v4는 latest cancellation helper 변경 전에 244 tests/1 performance skip/0 failures였다. **현재 5개 XCTest의 최신 TSAN 통과로 확대하지 않는다.** [최신 targeted TSAN 로그](validation/r-backlog-2026-11-09/validation-bitset-tsan-final.log)의 build는 성공했으나 helper 실행은 sanitizer dylib의 platform-policy load rejection으로 막혔다. security 설정은 바꾸지 않았다. 최종 release selected/full 결과는 root 로그에 연결해야 하며 아래 probe 결과로 대체하지 않는다.

## 반복 250k fresh-process 측정

[`250k-profile.json`](validation/r-backlog-2026-11-09/validation-bitset/250k-profile.json): 5 alternating fresh-process pairs, process당 validation 3회. 동일한 optimized copied Core에 frozen Set oracle와 bitset을 함께 빌드했다. fixture 생성은 타이머 밖이며 input/checksum이 pair별 동일하다. timed validation은 기본 control=nil 경로이고 실제 import의 nonnil token checkpoint 비용을 별도로 분리 측정하지 않았다. 사용자 GUI/다른 host 작업이 함께 실행됐다.

| 구현 | validation 3회 median (range) | process peak RSS median |
|---|---:|---:|
| frozen Set | 0.43724s (0.37109–0.95013) | 93.03MB |
| bitset | 0.42572s (0.30680–0.58258) | 70.25MB |

이 입력에서는 peak RSS median이 약 22.8MB 감소했다. 시간 차이는 작고 range가 겹치므로 큰 속도 개선율을 주장하지 않는다. bitset payload는 31,250B다. process RSS에는 fixture/node/string 등 다른 메모리도 포함되므로 payload와 RSS 차이를 동일시하지 않는다.

## 실제 7,092,351-node SNS 측정

기존 frozen `/Users/aido/.local/share/mac-space-sniffer/validation/2026-11-09/develop-baseline.sns`를 read-only로 사용했다. 744,975,698B, SHA256 `ffee4c3f9d58eb8fd62bb6f095a600db0ef495ccce0d02aa1c386d39e8f7a3f4`를 [재확인](validation/r-backlog-2026-11-09/validation-bitset/input-identity.json)했다. 현재 GUI에서 관찰한 약 6.99m nodes와는 다른 기존 fixture다. 새 대형 입력 파일은 만들지 않았고 GUI를 제어하지 않았다. 실행 전 25.8GB host memory의 free 31%를 확인하고 process를 하나씩 실행했다.

[`actual-profile.json`](validation/r-backlog-2026-11-09/validation-bitset/actual-profile.json)은 **1 pair만** 실행했다. decode는 양쪽 모두 같은 bitset production validator를 거친 뒤 validation만 별도 측정한다. decode/fixture 준비는 validation 타이머 밖이다.

| 구현 | decode/prepare | 추가 validation | peak RSS before / after validation |
|---|---:|---:|---:|
| frozen Set | 36.127s | 15.071s | 1.590 / 1.590GB |
| bitset | 31.980s | 11.565s | 1.862 / 1.862GB |

두 결과 모두 노드 checksum 7,092,351, bitset payload 886,544B다. 이 한 pair에서 validation은 짧아졌지만 반복된 속도 인증은 아니다. **실제 대형 입력 RSS 개선은 입증하지 못했다.** bitset process peak가 오히려 높았고, 두 process 모두 decode 단계에서 이미 high-water를 기록해 validation 전후 delta가 0이었다. host 압축/페이지 residency/decode peak를 validator의 독점 allocation과 분리하지 못했다. 반복 synthetic에서의 RSS 감소와 N/8의 bounded payload만 확정 근거로 사용한다.

## 보관 범위

[validation-bitset evidence](validation/r-backlog-2026-11-09/validation-bitset/)에 pre-change Model, frozen oracle, copied Core source, 두 probe binary hash, malformed/cancel 결과, 원시 반복·실제 입력 프로파일과 실패 로그를 보관한다. profile-version probe와 cancellation-helper-fixed 버전은 구분한다. production Model body는 두 probe에서 같다. Windows runtime equivalence나 전체 import pipeline의 140초가 이 변경 하나로 해결됐다고 주장하지 않는다.
