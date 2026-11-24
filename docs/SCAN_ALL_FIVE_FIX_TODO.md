# 다섯 개선 재검토 — 정석 수정 TODO

작성: 2026-11-21. **세 결함 수정·회귀 검증 완료, 성능 채택·배포 HOLD.** [실행 결과](SCAN_REVIEW_FIX_RESULTS.md). [재검토 근거](SCAN_ALL_FIVE_REVIEW.md) · [재현 결과](validation/scan-all-five-review-2026-11-21/reproduction.json) · [기존 측정](validation/scan-all-five-2026-11-21/v5/MEASUREMENTS.md).

목표는 sparse fallback 취소 결함, 경로 값 동등성 위반, ENTRYCOUNT 계측 누락을 각각 해결하고 성능 회귀의 원인을 분리하는 것이다. 실행 순서는 **기준 고정 → 취소 수정 → 동등성 수정 → 계측 보완 → 정책 실험 → 통합 검증**이다. 서로 다른 책임의 수정을 독립 변경으로 남겨 원인 추적과 되돌리기가 가능하게 한다.

후속: [최종 GUI·환경 gate 기록](SCAN_FINAL_GATE_RESULTS.md). native watch 루트 alias 삭제 누락은 별도 후속 수정으로 기록하며, 아래55개 체크가 최종 배포 완료를 뜻하지 않는다.

## 0. 기준·재현을 먼저 고정

- [x] 현재 V5 production source와 frozen probe의 SHA를 대조하고 수정 전 기준으로 보존한다. 이후 후보마다 source manifest·binary SHA·명령·정책 값을 별도로 기록한다.
- [x] 기존 작은 재현을 제품 테스트로 옮겨 수정 전 실패를 확인한다. stub으로 재현한 결과를 full reader/pool 통합 통과로 집계하지 않는다.
- [x] 기존 성능 gate와 입력·정확성 oracle을 유지한다. A/A 실패와 후보 실패를 모두 보존하며 통과 표본만 고르지 않는다.
- [x] 작업별 완료 표시는 실제 코드·회귀 테스트·결과 기록이 모두 있을 때만 체크한다. 새 sparse 테스트는 reader/pool/ticket 경계를 통과하며, builder까지 같은 sparse 주입으로 연결한 테스트라고 주장하지 않는다.

## 1. P1 — fallback stat 직전 취소 검사

대상: [MacDirectoryBatchReader.swift](../Sources/SpaceSnifferCore/MacDirectoryBatchReader.swift), [ScanOptimizationContractsTests.swift](../Tests/SpaceSnifferCoreTests/ScanOptimizationContractsTests.swift), [DirectoryReadAheadTests.swift](../Tests/SpaceSnifferCoreTests/DirectoryReadAheadTests.swift).

### 책임·수정 방식

- [x] `for ... where values == nil` 안에서 원래 배열 index의64배수만 검사하는 구조를 제거한다.
- [x] 전체 index 순회의 주기적 취소 검사와 **각 fallback stat 직전의 취소 검사**를 분리한다. metadata가 이미 있는 항목도 주기적 검사 위치에서 빠지지 않게 한다.
- [x] stat 직전 검사 → 시도 counter 증가 → 실제 stat 호출 순서를 고정한다. 검사에서 취소가 관찰되면 stat을 호출하지 않고 `.cancelled`로 반환한다.
- [x] 알려진 mount 경계는 계속 stat 전에 제외한다. 실패한 stat의 metadata는 nil로 남겨 builder의 최종 오류 관찰 계약을 유지한다.
- [x] 취소 검사와 blocking stat을 하나의 전역 lock으로 묶지 않는다. queue/control 공통 계층에 Darwin I/O를 넣지 않는다.
- [x] 재현용 seam은 실제 stat 경계에 한정한다. 기존 native call seam과 일관된 내부 closure 또는 metadata completion helper를 사용한다. 테스트에서 API 경계의 취소 시점과 호출 횟수를 제어한다.
- [x] helper 분리가 필요하면 기존 adapter 내부의 작은 함수부터 사용한다. I/O 완성 책임만 분리하고 ID 생성·트리 합산·UI 상태를 이동하지 않는다.

구조 예시(구현 시 현재 타입에 맞춘다):

```swift
for index in entries.indices {
    if index & 63 == 0, control.isCancelled {
        return DirectoryReadOutput(value: .cancelled, statistics: statistics)
    }
    guard entries[index].values == nil else { continue }
    // child path 및 알려진 mount 경계 검사
    guard !control.isCancelled else {
        return DirectoryReadOutput(value: .cancelled, statistics: statistics)
    }
    statistics.statCalls += 1
    // stat 실행, 성공한 metadata만 반영
}
```

취소 보장은 검사 시점을 기준으로 정의한다. 첫 stat 직전 검사에서 이미 취소 상태이면 호출0회다. 검사 직후 또는 syscall 진행 중 취소되는 경우 이미 승인·진입한 호출1회는 완료될 수 있으나, 다음 호출의 검사에서 중단해야 한다. 동기 syscall 자체를 강제 중단한다는 보장은 하지 않는다.

### 회귀 테스트·완료 기준

| 경우 | 결정적 제어 | 필수 결과 |
|---|---|---|
| sparse 누락 | nil 위치1·65·129·193, 나머지 metadata 있음; 첫 stat 검사 전에 취소 | stat0회, `.cancelled` |
| 보완 도중 취소 | 첫 stat seam에서 취소 신호 발생 | 첫 호출만 실행, 후속 stat0회 |
| 이미 진행 중인 I/O | 첫 stat 진입을 semaphore로 정지한 뒤 취소, 이후 해제 | 진행 중1회 허용, 다음 호출 없음; 반환·drain 완료 |
| 누락 배열 형태 | 전부 nil/전부 metadata/불규칙 nil/마지막 항목 nil | 검사 지점이 nil 분포에 좌우되지 않음 |
| mount 제외 | 알려진 mount에 metadata nil | 해당 경로 stat0회 |
| stat 실패 | errno를 설정한 실패 seam | 실패 metadata를 꾸미지 않음, builder 오류·정확성 유지 |
| worker 통합 | 실제 reader→pool→ticket에서 sparse 취소 + 기존 builder 취소 통합 테스트 | 취소 결과에 usable listing 없음; FD/permit 해제 후 terminal 완료 |

- [x] sleep에 의존하지 않고 semaphore/expectation으로 순서를 제어한다. 비정상 대기를 잡는 timeout만 둔다.
- [x] 수정 전 sparse 테스트 실패, 수정 후 통과 로그를 보존한다.
- [x] 취소·FD·permit·shutdown 관련 기존 테스트 및 해당 TSAN 통합을 통과한다.

## 2. P2 — 경로 동등성을 공개 값 기준으로 복구

대상: [NodePathStorage.swift](../Sources/SpaceSnifferCore/NodePathStorage.swift), [Model.swift](../Sources/SpaceSnifferCore/Model.swift), [NodeTable.swift](../Sources/SpaceSnifferCore/NodeTable.swift).

### 책임·수정 방식

- [x] 동일한 compact components이면 즉시 true를 반환하는 fast path를 유지한다.
- [x] components가 다르다는 이유만으로 false를 반환하지 않는다. 나머지는 `lhs.wrappedValue == rhs.wrappedValue`로 판정한다.
- [x] 파일시스템 경로 정규화·대소문자 변환·symlink 해석을 equality에 추가하지 않는다. 기존 공개 `String` 값 동등성 계약을 따른다.
- [x] 경로의 raw UTF-8 차이를 감지하는 기존 NodeTable 검사는 유지한다. Swift String의 정규 동등성과 raw spelling 판정은 목적이 다르다.
- [x] 이번 수정에 Hashable, 공유 mutable cache, 경로 전역 intern table을 추가하지 않는다. 값 타입·CoW·184byte layout 계약을 유지한다.

권장 구현 형태:

```swift
if let left = lhs.leaf, let right = rhs.leaf,
   lhs.base == rhs.base, left == right { return true }
return lhs.wrappedValue == rhs.wrappedValue
```

### 회귀 테스트·완료 기준

- [x] compact `/foo`+`bar`, compact `/foo/`+`bar`, literal `/foo/bar`가 모두 같음.
- [x] 위 세 표현에 대해 대칭성·추이성·반사성이 성립함.
- [x] 다른 path는 계속 다름. `/foo//bar`와 `/foo/bar`, literal `/foo/`와 `/foo`를 임의로 같게 만들지 않음.
- [x] root `/`, Unicode NFC/NFD, Windows/UNC literal, public setter의 기존 의미를 유지함.
- [x] 공개 필드가 같은 DiskNode의 equality·JSON 결과가 저장 표현과 무관함.
- [x] NodeTable의 값 복사·변경 감지와 SNS/JSON round trip 통과. 변경된 raw spelling 감지는 사라지지 않음.
- [x] 동일 components fast path와 드문 fallback의 비용을 분리 확인. equality 수정으로 경로 저장이나 외부 wire schema를 바꾸지 않음.

현재 정규화된 scanner 입력에서 해당 표현 차이가 실제 발생하는지는 미확인이다. 계약 위반 재현과 실제 UI 영향의 확인 여부를 따로 기록한다.

## 3. P2 — ENTRYCOUNT 실제 비용을 빠짐없이 계측

대상: [NativeDirectoryMetadata.swift](../Sources/SpaceSnifferCore/NativeDirectoryMetadata.swift), [Scanner.swift](../Sources/SpaceSnifferCore/Scanner.swift), [DirectorySiblingAdmission.swift](../Packages/SpaceSnifferScanEngine/Sources/SpaceSnifferScanEngine/DirectorySiblingAdmission.swift), bench profile/report 코드.

### 계측 책임

- [x] OS adapter가 실제 `countCall` 진입·종료를 관찰한다. 후보를 살펴본 횟수를 native API 호출 수로 대신 사용하지 않는다.
- [x] 기존 bulk `observeCall`과 유사한 동기·nonescaping observer/반환 metrics를 사용한다. builder는 자신의 scan-local statistics에 합산한다.
- [x] 공통 admission 상태기는 parent·거부 만료 판단만 담당한다. Darwin, clock, 전역 mutable counter, 로그 기능을 넣지 않는다.
- [x] 실제 `getattrlist` 직후 errno를 먼저 보존한다. clock/observer/문자열 처리 뒤의 errno를 오류 근거로 사용하지 않는다.
- [x] 단조 clock으로 query 구간을 측정한다. 고정 크기 scalar 합계만 저장하고 매 query마다 로그나 무한 배열을 쌓지 않는다.

권장 최소 metrics:

| 항목 | 정의 |
|---|---|
| `entryCountCalls` | 실제 count API boundary를 호출한 수 |
| `entryCountFailures` | API가 실패를 반환한 수; 취소·범위 거부와 구분 |
| `entryCountUnavailableResults` | API 성공 후 필요한 속성 누락·invalid buffer 등으로 count를 못 얻은 수 |
| `entryCountElapsedNanoseconds` | 실제 query 구간의 단조 시간 합계; 범위를 명시 |
| `admissionCandidatesExamined` | scheduling이 살펴본 후보 수 |
| `admissionHintHits` | 이미 확보한 hint로 판정해 count API를 생략한 수 |

- [x] 유효한0-entry 결과, API 실패, 속성 누락, query 전 취소, query 후 취소를 구분한다.
- [x] root adaptive query와 sibling admission query를 빠짐없이 포함한다. 필요하면 용도별 소계를 추가한다.
- [x] merge는 각 작업의 metrics를 정확히 한 번 합산한다. worker와 builder가 같은 mutable counter를 공유하지 않는다.
- [x] 이전 JSON에 새 필드가 없으면 **미측정**으로 표시한다. 과거 기록을 count0회로 취급하지 않는다. optional metrics 또는 명시적인 계측 schema/version을 사용한다.
- [x] 새 JSON 필드를 decoder가 반드시 요구하게 만들어 과거 진단 기록을 깨뜨리지 않는다. SNS/public node schema는 바꾸지 않는다.

### 테스트·완료 기준

- [x] fake countCall의 실제 호출 수와 report의 count가 일치함. 성공·실패·invalid/누락 속성을 각각 검증함.
- [x] hint hit는 query0회, query 전 취소는0회, 실제 호출 후 취소는1회로 계상됨.
- [x] merge에서 누락·이중 계상이 없고 이전 JSON의 미측정 상태를 보존함.
- [x] 실제 scanner의1000개 tiny sibling fixture에서 count API 수를 직접 확인함. 기존 상태기 모델의60회를 실제 측정값으로 그대로 복사하지 않음.
- [x] native query 시간과 전체 scan 시간, stat/bulk API 수를 함께 기록함. 모든 syscall의 총합이라고 표현하지 않음.

## 4. 원인 분리 후 admission 정책 판단

- [x] 계측만 추가한 기준 후보와 정책 변경 후보를 분리 동결한다. 현재4후보/64기회 정책을 먼저 측정한다.
- [x] 비교할 조건과 표본 수를 실행 전에 고정한다. 대조군은 동일 binary·동일 mode로 구성한다.
- [x] 다음 세 정책을 독립 실험한다: 현재 재표본, 단일 후보+재표본, 최초 거부 후 재표본 비활성(원인 분리용 실험 전용).
- [x] 재표본 비활성은 tiny-first 뒤의 큰 폴더를 영구 배제할 수 있으므로 그대로 production에 채택하지 않는다.
- [ ] tiny1000, 전부 중간 크기, tiny→large, large→tiny, 첫 후보 oversized/접근 거부/소멸 입력을 포함한다. 성능 matrix는 소멸을 제외한 일곱 입력 완료. 소멸은 결정적 scanner 회귀 테스트로 검증했으며, 소멸 입력의 반복 성능 측정은 남음.
- [x] native countCalls·총 query 시간·hint hit·사용된 작업 수·scan p50/p95·CPU·RSS를 같은 표에 기록한다.
- [x] 정확한 노드·ID·전체 필드·파일/용량 oracle·SNS/TXT 결과를 보존한다. hint를 coverage 생략 조건으로 쓰지 않는다.
- [x] query가 실제 지배 비용이고 정책 변경의 효과가 재현될 때만 Mac 정책 값을 조정한다. 공유 worker 수나4후보 수치를 먼저 임의 변경하지 않는다.

현재 표준 p95는21표본 중 두 번째 느린 값이다. 작은 tail 판단을 강화할 targeted 반복 수(예:100쌍)와 수집 조건을 사전 고정하고 기존21쌍 전체 matrix와 구분해 보고한다. 같은 binary A/A가 흔들리면 환경 편차와 구현 비용이 분리되지 않은 상태로 남긴다.

## 5. 통합 검증·채택 gate

- [x] 새 회귀 테스트 → 관련 reader/worker/NodeTable 테스트 → 프로젝트 전체 및 공통 debug/release 테스트 순으로 검증한다.
- [x] 변경된 Mac 통합의 TSAN, producer API/플랫폼 경계/원본 근거 검사, ARM·Intel TXT/SNS 상호 운용을 확인한다.
- [x] source·probe·실행 앱의 계측 대상을 구분하고, 각 결과에 binary SHA·정책·입력·실패·표본 수를 기록한다.
- [x] 표준7입력과 mixed 입력 비교 및 동일 binary A/A를 수집한다. CPU/메모리 숫자만으로 시간 기준 실패를 덮지 않는다.
- [x] scan 내부 시간과 validation/digest 포함 process wall 시간을 별도 기록한다. GUI 표시 지연이라고 표현하지 않는다.
- [x] 모든 실패·중단·warmup·fixture 삭제를 보존한다. 정책 fixture는 내부 APFS에서 최대 약2.1만 파일이며 reserve2GiB를 적용했다. 표준 입력은 기존 harness의 reserve 조건을 유지한다. 전용 fixture만 정리한다.
- [x] 앱을 정지해 측정한다면 identity 확인·watchdog·finally 재개를 사용하고, 별도 사용자 프로세스를 임의 중지하지 않는다.
- [ ] A/A 신뢰도 및 아래 기존 기본 정책 gate를 모두 충족한 후 GUI/watch·패키징·배포를 진행한다.

| 기준 | 그대로 유지할 통과 조건 |
|---|---|
| 정확성 | 모든 measured/warmup의 oracle·Swift digest·필수 export 계약 일치 |
| latency | p50·p95 각각 기준의1.10배 이하 |
| paired CI | 개선율95% CI 하한 −10% 이상 |
| CPU | p95 기준의1.20배 이하 |
| RSS | p95가 max(기준1.10배, 기준+32MiB) 이하 |
| 표본 | 기존 채택 판단 최소20쌍; targeted tail 실험은 별도 사전 고정 |

V5의6/7 통과와 기존309개 테스트 통과는 이 수정의 완료 증거로 재사용하지 않는다. 새로 바뀐 코드에서 새 경계와 관련 통합 검증을 완료해야 한다. Windows native 실행 및 거대 폴더 중간 선점은 이 세 결함 수정과 별도 후속으로 유지한다.
