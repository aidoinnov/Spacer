# R05 focus-first 필터 prototype 평가

2026-11-09. **production 일괄 채택은 보류한다.** 작은 focus의 첫 결과를 빨리 준비하는 효과는 확인했지만, root/큰 focus·단순 조건에서는 총시간이 악화되고 중간 불변 배열을 보유하는 비용도 발생한다. 이 기록은 kernel prototype의 평가 완료이며 실제 앱의 부분 publish·MCP revision·취소 UI 통합이나 Windows 실행 동등성 완료를 뜻하지 않는다.

## 원본에서 확인한 경계

- `TFilterThread` [ctor 0x4590a0](validation/windows-optimization-functions/0x4590a0.txt), Evidence `ev_908d01c963acf8a3796c395502f6706bfd33cf145ddc221fe80fbe113553c67b`: 전체 범위·focus 범위와 inherited-tag 인자를 보관한다.
- [Execute 0x459170](validation/windows-optimization-functions/0x459170.txt), `ev_562c3d17a1e6dc585f3b79fe82a30f627f6faef724f6fe654115a34899512532`: 두 범위가 다르면 focus를 먼저 갱신하고, 취소/제거 guard 뒤 전체 범위를 갱신하면서 focus를 제외 인자로 넘긴다. 같으면 한 번만 수행한다.
- [updateFiltering 0x46a490](validation/windows-optimization-functions/0x46a490.txt), `ev_2ca77b3b513bbe7a458b603e55564e044e7616d195d3d26386de64deb8fe409b`: 전달된 제외 subtree와 현재 node가 같으면 즉시 돌아간다. 이미 처리한 focus를 나머지 재귀에서 다시 평가하지 않는다.
- [applyFilterTo 0x42cba0](validation/windows-optimization-functions/0x42cba0.txt), `ev_54626e5c9d021b058bdd218aec92c839b4cec312f8c66a80de8e19625937e9f1`: 기존 filter thread 종료와 새 worker 생성 경계다. [reapplyFilterIfTagInvolved 0x430400](validation/windows-optimization-functions/0x430400.txt), `ev_2af873cf5c31f442b5c1af60d4c4f1650b9c27ca8fd4158c34d13c1f0bee7baf`는 tag-dependent 조건에서 root/focus를 넘긴다.

위는 shipped EXE의 정적 관측이다. 원본에서 Swift 배열·아래 latency·COW 비용을 관측했다는 주장이 아니다. 원본의 filter ID/재필터 high byte는 [별도 R13 분석](R13_INVALIDATION_FINDINGS.md)을 따른다.

## prototype와 공정한 대조

[prototype extension](../scripts/bench/r05-focus-extension.swift)은 복사한 Filter.swift **동일 파일**에만 덧붙여 private predicate와 UInt8 ancestor context를 사용한다. production source/API를 수정하거나 test helper를 앱에 링크하지 않았다. [build script](../scripts/bench/r05-build-probe.py)가 당시 Core 36개 파일과 probe source를 고정했다. [원본 source archive·컴파일 manifest](validation/r-backlog-2026-11-09/r05/build-v3/build-manifest.json)와 생성 Filter의 hash를 별도로 보관한다.

세 구현을 같은 executable에서 fresh process로 비교한다.

| mode | 계산과 첫 callback |
|---|---|
| `full` | 현재 bulk membership(U8 context) → 현재 flat weights/역방향 집계 → callback |
| `fused` | 같은 private predicate/context로 ascending membership와 leaf weight를 한 loop에 계산 → 전체 역방향 집계 → callback. 루프 융합 효과를 별도로 구분하는 control |
| `focus` | ancestor chain을 한 번 준비 → focus DFS로 membership/leaf weights 계산·내부 edge 집계 → focus callback → 나머지 ascending pass에서 focus node 판정 skip → 전체 역방향 pass에서 이미 집계한 focus 내부 edge skip |

각 leaf에서 조상을 다시 걷는 O(depth) 대조군을 만들지 않았다. focus 내부의 순서/visited 상태를 저장하는 추가 배열과 DFS stack·나머지 skip 분기도 실제 비용에 포함했다. root focus도 unguarded focus 후보로 측정해 손해를 숨기지 않았다.

callback은 전체 크기의 `included/weights` 불변 배열을 실제로 보유한다. 뒤에서 나머지를 채우면 Swift COW가 발생하며 small/large focus의 old/new weight buffer가 달라짐을 실행 중 확인했다. callback snapshot은 **focus scope만 완성**됐고 밖의 weights는 0이다. 이를 전체 filtered total이나 조회 가능한 final revision으로 표시해서는 안 된다. final 전체 배열과 focus의 frozen 배열을 각각 검증했다.

`full/fused`의 callback은 전체 완료 뒤에 실행되므로 같은 방식으로 배열을 보유해도 뒤의 배열 쓰기/COW가 없다. root-focus 후보도 이미 전체를 처리했으므로 partial COW가 없지만 DFS/order/skip-pass 비용은 남는다.

## 입력·측정 범위

[probe](../scripts/bench/r05-focus-probe.swift)는 고정 seed·고정 시각의 in-memory metadata fixture를 만든다. 파일 25,000/250,000개, root 아래 small 약1%·large 약50%·other 약49%와 하위 8개 group씩을 둔다. IDs는 parent-before-child이며 파일은 분기 사이에 섞인다. 따라서 focus subtree를 단순 ID 구간으로 가정하지 않는다. 실제 DiskScanner 출력의 모든 배치/깊이를 대표하는 fixture는 아니다.

측정 필터는 empty, `*.bin`, tag/folder/hidden/size 혼합의 세 종류다. 별도 회귀는 tag·hidden·folder·time과 주입한 `now`, logical/allocated 모드를 포함한다. NFC/NFD/한글·LF·대소문자·0바이트 입력도 있다.

[순차 runner](../scripts/bench/r05-measure.py)는 18 case × 5 alternating triples × 3 modes = **270개 fresh process**를 실행했다. 첫 준비 시간은 callback 직전, 총시간은 나머지 계산과 callback 보유 비용까지다. fixture 생성·filter parse·full oracle·최종 checksum/reader 검증은 시간 밖이다. callback에서 수행한 Mach resource sampling은 총시간에 포함한다. UI 렌더링·MainActor 전송·geometry·IPC/MCP·scan I/O는 포함하지 않는다.

[raw/집계](validation/r-backlog-2026-11-09/r05/measurements-v1/report.json), [호스트](validation/r-backlog-2026-11-09/r05/measurements-v1/host.json), [진행 로그](validation/r-backlog-2026-11-09/r05/measurements-v1.log)를 보존했다. 이 runner의 process끼리는 순차다. 같은 호스트의 실제 대형 GUI scan·압축/메모리 압력·다른 작업과 겹칠 수 있으므로 특히 작은 차이를 확정적 개선율로 주장하지 않는다. 다섯 표본의 median/min/max를 보고하며 UI p95/FPS로 바꾸지 않는다.

## 25만 파일 결과

단위 ms, 각 5개 process의 중앙값이다. ready와 total의 순서가 다른 경우가 있으므로 둘을 구분한다.

| focus / 조건 | full ready | focus ready | full total | focus total | fused total |
|---|---:|---:|---:|---:|---:|
| small / empty | 28.490 | 9.194 | 28.517 | 47.597 | 31.647 |
| small / mask | 244.972 | 8.915 | 244.992 | 207.250 | 233.705 |
| small / mixed | 191.567 | 6.593 | 191.603 | 193.970 | 214.071 |
| large / empty | 24.805 | 64.161 | 24.825 | 84.184 | 27.201 |
| large / mask | 245.980 | 218.011 | 246.003 | 372.250 | 257.653 |
| large / mixed | 179.260 | 123.618 | 179.305 | 210.480 | 160.277 |
| root / empty | 24.759 | 138.335 | 24.806 | 154.406 | 26.948 |
| root / mask | 260.772 | 416.320 | 260.823 | 432.716 | 287.451 |
| root / mixed | 181.395 | 343.303 | 181.429 | 359.495 | 205.860 |

25k의 9 case도 raw report에 있다. 예를 들어 small/mask는 ready 25.929→0.635ms이고, root/empty는 total 1.905→15.280ms로 악화됐다. 작은 focus의 빠른 첫 결과와 전체 작업 감소는 같은 결론이 아니다. small/mask의 총시간 감소도 loop-fusion control 및 공유 호스트 변동을 함께 보고 판단해야 한다.

메모리는 실제 Mach RSS/physical footprint를 before/at-focus/after에 기록했다. 주요 peak RSS는 oracle 직전까지의 getrusage 값이며 fixture와 runtime 초기화도 포함한다. `/usr/bin/time -l` whole-process peak는 뒤의 oracle까지 포함하므로 별도 필드다. 예를 들어 250k small/mask의 oracle 전 peak RSS 중앙값은 full 97.30MiB / focus 99.47MiB, large/mixed는 90.22 / 94.70MiB였다. raw의 physical footprint와 RSS를 서로 대체하거나 배열 payload를 deep heap/RSS cap으로 취급하지 않는다.

## 결과 동등성·취소·source 고정

- [검증 출력](validation/r-backlog-2026-11-09/r05/measurements-v1/verification.stdout): 576개 exact Bool/Int64 weights 대조와 pre-cancel/callback-cancel 8개를 통과했다. 270개 측정 process도 각각 final full oracle와 frozen focus scope·외부 미작성 상태를 검증한다.
- 각 case의 모든 mode/pair는 같은 최종 checksum이다. partial reader를 유지한 채 나머지를 계산해도 그 focus 값과 외부 초기 상태가 변하지 않았다.
- arbitrary 시간의 GUI 취소·projection generation·focus 이동 중 partial commit·worker coalescing을 검증한 것은 아니다. callback에서 취소하면 final 결과를 반환하지 않는 prototype 경계를 검사했다.
- source/binary/raw hash는 측정 당시 고정값으로 유지한다. [evidence check](validation/r-backlog-2026-11-09/r05/evidence-check.json)는 현재 소스 차이를 **별도** 기록한다. 검사 시 Scanner.swift의 metadata backend 추가와 NativeDirectoryMetadata.swift 신규 파일, Report.swift/ConfiguredReport.swift adapter 변경이 보였으나, 이 probe가 호출하는 ScanControl 선언과 Filter/FilterProjection/FilterScratch/Model/NodeTable hot-path 입력은 동일했다. DiskScanner와 report adapter는 이 in-memory fixture에서 호출하지 않는다. 비교는 검사 시점의 관측이며 향후 hot path가 바뀌면 숫자를 현재 앱의 수치로 재사용하지 않는다.

재현:

```sh
TMPDIR="$PWD/.build/tmp" python3 scripts/bench/r05-build-probe.py --output <새-build-경로>
python3 scripts/bench/r05-measure.py --build <새-build-경로> --output <새-output-경로>
python3 scripts/check-r05-focus-evaluation.py
```

마지막 checker는 보존한 이번 실행을 검사하며 성능 측정을 새로 실행하지 않는다. source를 먼저 복사하는 단계에서 absolute `__file__` 경로를 잘못 합친 첫 draft build는 SameFileError로 중단됐고 측정에 사용하지 않았다. build-v2는 정상 컴파일된 draft, 최종 측정은 디렉터리 timestamp까지 고정한 build-v3다.

## 채택 판단

이번 R05 prototype·측정 범위는 완료했다. 판정은 `evaluated_not_adopted_in_production`이다. 아래 조건은 이후 실제 UI 통합을 재검토할 때의 요구사항이며, 이번 측정 완료가 production 적용이나 화면 응답성 검증 완료를 뜻하지 않는다.

지금의 production에는 넣지 않는다. root focus에는 기존 bulk pass가 유리하고, empty/큰 focus에는 첫 결과 자체가 늦어지는 경우가 있다. 작은 복잡한 focus에서만 early-ready 효과가 크지만 그 첫 publish를 실제 화면에서 사용할 수 있어야 이득이 된다. flat arrays의 추가 COW·전체 skip pass·scope 메타데이터와 revision 관리도 비용이다.

후속 채택을 검토하려면 root/동일 범위 fallback, 실제 focus 크기·필터별 선택 기준의 실측, partial scope 외 query 차단 또는 final revision 계약, 최신 intent/generation 승인, UI callback 비용·실제 첫 frame 지연과 취소/닫기를 먼저 검증해야 한다. 이번 두 focus 비율만으로 임의 threshold를 production 정책으로 정하지 않는다. 기존 FilterScratch warm reuse나 navigation cache-hit workload, 수백만 노드·장시간/여러 reader의 비용도 이 cold 단일 평가에서 일반화하지 않는다.
