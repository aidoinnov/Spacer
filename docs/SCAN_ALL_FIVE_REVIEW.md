# 다섯 개선 재검토 — 2026-11-21

**아래는 수정 전 검토 기록이다. 세 결함의 후속 수정·회귀 검증은 [실행 결과](SCAN_REVIEW_FIX_RESULTS.md)에 기록했다. 배포 HOLD는 유지한다.** 기존309개 테스트 통과는 해당 테스트 범위의 사실이며, 아래 경계를 검증했다는 뜻은 아니다. 이번 검토는 V5 코드·동결 raw 결과·작은 Swift 재현을 대조했다. production 코드는 수정하지 않았다.

[재현 결과와 source SHA](validation/scan-all-five-review-2026-11-21/reproduction.json) · [현재 TODO](SCAN_ALL_FIVE_TODO.md) · [정석 수정 TODO](SCAN_ALL_FIVE_FIX_TODO.md)

## P1 — sparse metadata fallback에서 취소 검사가 빠진다

위치: `Sources/SpaceSnifferCore/MacDirectoryBatchReader.swift:17–18`.

`for ... where values == nil` 내부에서 원래 배열 index의64배수에만 취소를 검사한다. 보완할 항목이1·65·129·193번이고0·64·128·192번에 metadata가 있으면 검사 지점을 모두 건너뛴다. eligibility 확인 직후 취소되는 유효한 interleaving에서 이후 lstat을 계속할 수 있다. 마지막에 cancelled를 반환하더라도 이미 수행한 I/O와 active worker drain 지연은 없어지지 않는다.

production adapter 본문을 그대로 컴파일한 작은 재현에서 `actualAdapterCancelled=true postCancelStatCalls=4`를 확인했다. 독립 타입 stub으로 eligibility 평가와 loop 시작 사이의 취소를 강제했고 실제 Darwin lstat 호출을 셌다. full reader/pool integration 실행은 아니다. 현재 취소 검증에는 이 sparse 배치 경계가 빠져 있다.

수정 방향: 전체 index 순회에서 취소를 검사한 뒤 metadata 유무를 분기하거나, 각 fallback stat 직전에 검사한다. 취소 시점이 index64의 배수와 맞지 않는 회귀 테스트 및 worker drain 검증을 추가한다.

## P2 — admission의 count 조회 비용이 통계에서 누락된다

위치: `Scanner.swift:23–46,238`, `NativeDirectoryMetadata.swift:81–97`.

새 정책은 첫 거부 후에도 재표본을 한다. 실제 공통 상태기로1000개 같은 부모·전부 작은 폴더를 모델링하면4후보/64기회 설정에서 count probe60회가 나온다. 실제 scanner 전체의 호출 수를 측정한 결과는 아니지만 추가 조회 경로의 존재와 bounded 반복 수는 코드로 재현된다.

이 `getattrlist(ATTR_DIR_ENTRYCOUNT)` 호출은 statCalls/bulkCalls/openDirectoryCalls 어디에도 계상되지 않는다. Native reader 자체에도 ENTRYCOUNT가 일부 volume에서 비쌀 수 있다는 설명이 있다. 따라서 tinyfolders1000의 p95 증가를 환경 편차로만 분류하거나 stat/bulk counter만으로 scheduling 비용을 판단하면 안 된다. 기존 보고서는 syscall 총합을 주장하지 않았지만, 회귀 원인 분석에 필요한 계측이 부족하다.

수정 방향: count query/실패/소요 시간 또는 표본 횟수를 분리 계측하고, 현재4후보/64 재표본과 단일 표본·재표본 비활성 대조를 동일 입력에서 비교한다. p95는21개 중 두 번째 느린 값이므로 tail 신뢰도도 별도 확인한다. 이 추가 비용이 관측 p95 회귀의 원인이라고 확정하지는 않는다.

## P2 — 경로 저장 표현에 따라 값 동등성이 달라진다

위치: `NodePathStorage.swift:15–17`.

compact끼리는 base/leaf를 바로 비교하고 다르면 false를 반환한다. 실제 구현을 컴파일한 결과:

```
base=/foo,  leaf=bar → /foo/bar
base=/foo/, leaf=bar → /foo/bar
publicEqual=true, storageEqual=false
```

동일 공개 경로를 가진 내부 compact 표현을 같지 않다고 판단한다. DiskNode의 synthesized Equatable에도 전파되며 변경 감지에서 불필요한 차이를 만들 수 있다. 현재 scanner의 정규화 입력에서 이 상태가 실제 발생하는지는 확인하지 않았다. 내부 constructor가 허용하는 값의 경계 계약 문제다.

수정 방향: 같은 components이면 빠르게 true를 반환하고, components가 다르면 실제 공개 경로 비교로 판정한다. trailing slash, literal/compact 혼합, double slash 보존을 회귀 테스트에 넣는다.

## 기존 성능 결론 재확인

V5 raw에서6/7 성능 기준 통과, tinyfolders1000 p95 17.234→20.355ms, 같은 바이너리 A/A4개 중3개 보류는 보고서와 일치했다. 전체 process wall의 wide100000 321.25→381.21ms도 그대로다. 메모리34.2%는 외부 APFS의 실제10만 파일 paired 실험·엔진 범위이며 GUI 전체나 V5의100만 파일 수치가 아니다.

이번에는 대규모 파일 생성이나 전체 테스트 재실행을 하지 않았다. 작은 재현 결과는 compiler 실행0으로 종료했으나, assertion을 통과한 제품 회귀 테스트로 집계하지 않는다. 재현이 드러낸 결함과 기존 테스트 통과 기록을 구분한다.
