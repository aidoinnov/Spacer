# R06: focus worker의 원본 계약과 안전한 Mac 적용 경계

2026-11-09. frozen SpaceSniffer 2.2.0.27 x64, SHA256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`. 기존 REA 정적 원문을 독립 재검토했다. Windows 실행은 하지 않았고 production concurrency 코드는 수정하지 않았다. **현재 Mac의 root별 직렬 scope rescan은 원본의 별도 focus worker와 동일하지 않다.**

## 관측된 원본

| 원문·Evidence ID | 직접 관측 | 해석의 한계 |
|---|---|---|
| [rescanCurrentFocus 0x430270](validation/windows-optimization-functions/0x430270.txt), `ev_36f8a538a6a5256fa9ffee3a9b4a60be5a13b0796ddbc5ec34f204e4f9bd8e0d` | view critical section 획득 → terminateRescanSnifThread 호출 → focus FS node로 TSnifThread 생성 → view+0x7b8에 보관 → Start. pool 인자는 0 | view별 별도 slot이라는 근거. terminate helper의 join/timeout/예외 본문은 확보하지 못함 |
| [root rescan 0x43e4c0](validation/windows-optimization-functions/0x43e4c0.txt), `ev_92c4d974627c8677bbc1ec4e922be8a40095f09b8b0a34d17b699dba62c63b9d` | root critical + write 획득 → terminateSnifThread → pool reset → root에 newThreadOn(...,0,0,1) → write/critical 해제 | focus slot을 이 함수가 직접 정리한다는 호출은 이 본문에 없음. 간접 호출까지 없다는 뜻은 아님 |
| [TSnifThread Execute 0x459a00](validation/windows-optimization-functions/0x459a00.txt), `ev_bb8f9153ddb74c4edd6f6708d358954c7441019000426b85247f622a65cfb24c` | root read lock, FS node addBusy, snifChildrenPaths, removeBusy, read 해제. cancel 확인. pool없음이면 Terminate, pool있으면 returnToPool 후 event 대기 | addBusy는 수명 보호이지 범위 중복 배제 증명 아님. callback flag+0x98의 생성자 설정 의미는 별도 확인 필요 |
| [node scan guard 0x406b10](validation/windows-optimization-functions/0x406b10.txt), `ev_fca4c5988706237015101927b74fb4af1d28da1d7371ebcc2daab8cf167762d5` | 대상 node+0x6a bit `0x02`가 이미 있으면 root read 해제→Sleep(10)→read 재획득→cancel/detached 확인. 진입하면 대상 bit2, 조상 bit1 설정. agent 호출 후 취소·detached 결과를 검사하고 해당 bit 정리 | 동일 target node guard. 이 코드만으로 모든 ancestor/descendant overlap을 완전히 배제한다고 말할 수 없음. 조상 bit1은 여기의 진입 조건으로 검사하지 않음 |
| [pool newThreadOn 0x45a7c0](validation/windows-optimization-functions/0x45a7c0.txt), `ev_472c33e96ae7d779feca421b4927a9248646059d585e5918c5a1ca0eec5cac56` | maxConcurrency 확인, pooled thread 재사용/신규 생성, root pool 경로 전달 | focus worker pool=0 경로와 별개. OS thread 수가 실제 실행 시 항상 특정 값이라는 뜻은 아님 |
| [start sniffing 0x42d7a0](validation/windows-optimization-functions/0x42d7a0.txt), `ev_75078f38a36a51a14cd404e722270154fa8ccaf33aafaaf54be51317d92d27d9` | filter/focus worker 정리 후 이전 TM pointer를 비우고 cache root를 연결, focus 설정 | root/view 교체 전에 focus 작업 수명을 닫는 호출 순서가 관측됨 |
| [direct elementChange 0x406d30](validation/windows-optimization-functions/0x406d30.txt), `ev_0261955c96dd41d366b16dd99d82ddb93d6095e970b18bada004c3a605e160ac` | path segment/child 조회, create helper. remove case는 nodeRemoved 통지·child 제거·조상 logical/physical 차감·노드 release. modify는 updateInfo+nodeModified. rename은 segment 변경+modified-attributes | 원본 직접 mutable tree 변경이다. Mac FSEvents 부모 스캔/immutable merge와 같은 실행 방식으로 표현하면 안 됨. Windows event producer 순서·overflow 회복 전체는 이 함수 하나로 증명되지 않음 |

원본은 shared mutable FS tree, read/write synchronization, busy/recycle lifetime, listener 통지를 함께 사용한다. focus worker가 존재한다고 해서 arbitrary concurrent immutable tree replacement를 허용하는 계약이 되지는 않는다. 이 정적 구조는 master/focus 동시 작업이 가능한 경로를 보여주지만 실제 scheduling·사용자 지연·공정성을 관측한 것은 아니다.

## 현재 Mac과 차이

[`ScanService.swift`](../Sources/SpaceSnifferCore/ScanService.swift)는 Entry에 단일 `control/job/generation/scanning/scope`를 둔다. 실행 중 rescan은 `restartScope`를 기록하고 기존 작업을 cancel한다. watcher pending은 작업 종료 후 진행한다. [`ScanWork.swift`](../Sources/SpaceSnifferCore/ScanWork.swift)는 하나의 baseline으로 scope를 스캔/병합하고 [`SnapshotTree.swift`](../Sources/SpaceSnifferCore/SnapshotTree.swift)가 변경 결과를 합친다. 기존 generation은 이 **단일 작업** 모델의 늦은 callback을 차단한다.

동일 root의 두 작업을 지금 그대로 병렬 실행하면 한 작업의 baseline으로 다른 작업의 최신 결과를 덮을 수 있다. 단일 `entry.generation`만으로는 서로 유효해야 하는 두 job과 root 교체 세대를 동시에 표현할 수 없다. 태그·identity·navigation repair·issue retention·watch overflow도 함께 처리해야 한다. 따라서 worker 하나를 추가하고 현재 receive를 재사용하는 변경은 안전한 이식이 아니다.

## 안전한 구현 계약 제안 — Mac 선택이며 원본 관측과 구분

이 절은 원본의 수명/중복 억제 의미를 immutable 모델로 옮기기 위한 설계 제안이다. 원본이 같은 알고리즘을 쓴다는 주장이 아니다.

1. root incarnation과 개별 job ID를 분리한다. job은 owner(view/subscription), request kind(master/focus/watch), normalized scope, root incarnation, 시작 baseline revision/target identity, cancellation token을 보유한다. node pointer나 오래된 numeric ID를 작업 수명 밖에서 사용하지 않는다.
2. focus request는 view당 이전 focus job을 취소·정리한 뒤 교체한다. view 교체/구독 해제/root disconnect에서 해당 owner를 닫는다. 다른 view의 master/focus를 무조건 취소하는 공유 token은 사용하지 않는다.
3. 동일/조상/자손 범위는 첫 구현에서 직렬화한다. 원본 bit2를 모든 범위 exclusion으로 과장하지 않는다. 독립 scope 병렬화는 측정과 merge oracle가 마련된 뒤 제한된 admission 안에서만 허용한다. Sleep busy loop 대신 명시적인 비동기 의존 관계를 사용한다.
4. worker는 자기 subtree만 수집하고 완결 candidate를 반환한다. 부분 subtree publish를 전체 root의 authoritative deletion으로 사용하지 않는다. 기존 완료 baseline 유지·초기 partial·cancel semantics를 보존한다.
5. 완료 시 현재 root incarnation/target identity/해당 scope 변경 revision을 재확인한다. overlapping 작업·watch 사건이 baseline 이후 변경됐다면 stale candidate를 버리고 재큐잉한다. disjoint 결과를 현재 snapshot에 병합하는 경우도 경계/issue/tag oracle가 필요하다. 각각의 오래된 전체 baseline을 번갈아 publish하지 않는다.
6. root full replacement는 진행 중 focus/watch 결과의 수명을 명시적으로 종료하거나 drain한다. cancel-before-start, cancel-during-enumeration, late heartbeat/terminal 중복을 멱등 처리한다. root 삭제/rename/replacement에서 identity 기반 repair와 태그 최신 변경 보존을 수행한다.
7. FSEvents overflow/ambiguous rename은 root rescan으로 승격한다. 직접 mutable event 처리로 바꿀지는 별도 과제이며 worker 추가와 묶어 정책을 발명하지 않는다. issue가 retention 한도를 넘으면 기존 whole-root fallback을 유지한다.
8. 사용자가 본 complete tree의 변경은 단일 직렬 publication 지점에서 확정한다. query reader/artifact snapshot은 frozen revision을 유지하고 오래된 worker 완료가 최신 UI/태그를 복원하지 않도록 한다.

이 계약은 구조적으로 root별 직렬 실행을 유지한 상태에서도 구현 가능한 선행 모델이다. 병렬화 자체가 acceptance가 아니며 실제 사용자 latency/메모리/공정성 이득이 있어야 채택한다.

## 구현 전 acceptance와 미확인 사항

| 검사 | 필수 관측/회귀 | 현재 상태 |
|---|---|---|
| master + 같은 focus / ancestor + child | 범위 충돌 admission, 결과 누락/중복/합계 없음 | 별도 focus 경로 미구현 |
| 서로 다른 두 focus owner | 한 view 취소가 다른 view 작업을 취소하지 않음 | 설계 필요 |
| disjoint scan 완료 순서 AB/BA | baseline overwrite 없이 최종 fields/issues/tags 동일 | 독립 merge oracle 필요 |
| scan 도중 delete/rename/replacement | terminal identity repair, stale scope 재실행 | 직렬 회귀와 병렬 acceptance 별개 |
| watch 변경/overflow + focus 완료 | 최신 변경 유실 없음, root 승격 우선순위 | producer-order Windows 비교 미실행 |
| close/unsubscribe/root 교체/취소 | 모든 수명 정리, 늦은 callback 무효, frozen reader 안정 | 현재 직렬 경계는 존재하나 별도 job 모델 필요 |
| 자원/공정성 | UI queue 지연, focus latency, syscall/CPU/peak footprint, starvation 측정 | Windows/Mac 동시 workload 미측정 |

추가 원본 조사 대상은 `terminateRescanSnifThread`의 실제 join/exception 경로, TSnifThread ctor의 callback/lifetime flag, root 종료와 focus worker의 연결, 직접 변경 worker의 producer/락 순서와 overflow 복구다. 확보된 원문만으로 이 gap을 완료 처리하지 않는다. Windows GUI 취소·동시성 관찰은 [R01 harness 문서](R01_WINDOWS_RUNTIME_HARNESS.md)의 수동 계획으로 연결하며 CLI에 존재하지 않는 focus/cancel 명령은 만들지 않는다.
