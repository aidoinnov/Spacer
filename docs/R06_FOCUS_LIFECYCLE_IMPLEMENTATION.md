# R06 초기 구현: owner별 focus intent와 직렬 admission

2026-11-09. [원본 계약·gap](R06_FOCUS_WORKER_CONTRACT.md)에 이어 실제 Core 수명 경계를 구현했다. **별도 병렬 master/focus worker 구현은 아니다.** 동일 root의 작업은 계속 하나씩 실행하며, 자동 UI 활성화나 스레드 수 변경은 하지 않았다. 원본 Windows 실행 비교도 미실행이다.

## 추가한 책임과 requester API

[`FocusScanRequests.swift`](../Sources/SpaceSnifferCore/FocusScanRequests.swift)는 owner별 최신 intent, stable FIFO, active ticket의 수명만 관리한다. [`FocusScanTarget.swift`](../Sources/SpaceSnifferCore/FocusScanTarget.swift)는 admitted blocking I/O 안에서 root/scope directory identity와 realpath containment를 짧게 검사한다. [`ScanService.swift`](../Sources/SpaceSnifferCore/ScanService.swift)는 기존 serialized scope worker·publication에 이 정책을 연결한다. Model/DiskNode/NodeTable shape는 바꾸지 않았다.

```swift
if let ticket = await service.requestFocusRescan(subscription: subscription, scope: focusPath) {
    await service.cancelFocusRescan(ticket)
}
await service.cancelFocusRescan(subscription: subscription) // 이 owner의 최신 intent
```

정확한 public 서명은 다음과 같다.

- `requestFocusRescan(subscription: ScanSubscription, scope: String) -> FocusScanRequest?`
- `cancelFocusRescan(_ request: FocusScanRequest)`
- `cancelFocusRescan(subscription: ScanSubscription)`

request는 유효한 구독과 normalized cached-root 내부의 **현재 cached directory**를 요구한다. file/missing/outside path는 nil을 반환한다. ticket은 id/ownerID/rootPath/scope/rootIncarnation과 내부 captured targetIdentity를 가진다. 반환은 intent receipt이며 worker 실행/성공 보장이 아니다. admission 거부는 기존 schedulingError로 노출한다. 새 public 통계 필드는 추가하지 않았다.

앱이 연결할 위치는 Store의 명시적 focus rescan과 nonroot automation scope 요청이다. whole-root explicit rescan은 기존 `rescan`을 사용한다. owner는 구독 ID이고 unsubscribe/shutdown에서 자동 정리한다. Store/Hub는 이 작업에서 수정하지 않았으며 root가 별도로 연결·검증한다. scanning 중 UI action의 기존 disabled 상태도 이 단계에서 변경하지 않았다.

## 원본에서 보존한 의미와 Mac 선택

원본 [0x430270](validation/windows-optimization-functions/0x430270.txt)의 view focus slot·이전 focus 정리, [0x406b10](validation/windows-optimization-functions/0x406b10.txt)의 same-target 중복 진입 억제, [0x459a00](validation/windows-optimization-functions/0x459a00.txt)의 worker/cancel 수명이 근거다. 원본은 pool없는 별도 thread와 mutable tree/busy lock을 쓴다. 아래 직렬 immutable policy는 안전한 Mac 선택이며 원본 병렬 구현과 같다고 하지 않는다.

1. master 실행 중 focus request는 queue에만 들어간다. master나 다른 owner의 active focus를 취소하지 않는다. 같은 owner가 active focus를 교체하면 그 token만 취소하고 실제 완료가 drain될 때까지 다음 작업을 시작하지 않는다.
2. owner별 pending slot은 하나다. pending replacement는 FIFO 위치를 보존한다. active owner가 replacement를 만들면 다른 queued owner 뒤에 들어간다. 오래된 ticket으로 최신 요청을 취소할 수 없다.
3. root Entry lifetime의 incarnation과 per-job generation UUID를 구분한다. Entry 제거/재생성 후 옛 receipt/완료는 새 Entry를 변경하지 않는다. explicit rescan/stop은 focus intents를 reset한다. 원래 master rescan/cancel 흐름은 유지한다.
4. dispatch와 commit에서 current cached target identity를 재검증한다. 실제 admission worker 진입과 I/O 완료 후에도 root/scope directory 및 알려진 dev:ino를 확인한다. realpath가 cached root의 실제 경계 밖이면 scanner를 호출하지 않는다. 이 pre/post 검사도 filesystem 전체 TOCTOU를 제거하는 원자적 snapshot은 아니다.
5. focus가 시작할 때 최신 serialized root snapshot을 baseline으로 잡는다. 부분 whole-tree publication은 focus에서 무시한다. 현재 ticket의 취소되지 않은 terminal만 확정하며 태그는 commit 시 최신 값을 overlay한다. scope가 root이거나 issue retention으로 root fallback되어도 focus의 terminal-only 경계는 유지한다.
6. target 교체·취소·owner unsubscribe로 obsolete된 결과는 complete baseline을 유지하고 tree revision을 만들지 않는다. target이 사라진 경우 이 단계에서 임의의 새 root scan을 만들지 않는다. watch/명시적 rescan이 최신 filesystem 결과를 복구한다. 사용자 cancel과 invalidated target을 위한 별도 outcome API는 아직 없다.
7. focus는 pending watcher 범위를 소비하지 않는다. queued focus가 root 전체를 재읽어도 별도 overflow/root refresh를 남긴다. focus FIFO를 drain한 뒤 watcher scheduling을 재개한다. 지속적인 focus 요청이 watcher를 늦출 수 있으며 공정성·우선순위 튜닝은 별도 측정 과제다.
8. admission 실패로 completion callback이 생기지 않으면 남은 focus intents도 reset하고 schedulingError를 broadcast한다. 무한 대기 slot을 남기지 않으며 재요청은 caller가 한다.

## 회귀 검증

[최종 focus/scan 로그](validation/r-backlog-2026-11-09/r06-lifecycle/selected-final-watch.log): **26 tests, 0 skipped, 0 failures**. focus 13개(10 integration + 3 policy), 기존 Recovery/Progress/Scheduling 13개다.

- queued owner replacement/exact old-token cancel/FIFO, master를 focus가 취소하지 않음.
- active owner replacement, root-only partial suppression, 다른 owner 유지, ancestor/child scope의 peak active=1과 최신 baseline 합계 병합.
- running owner unsubscribe, global stop, explicit master reset, root Entry 재생성과 old receipt/late result 무효화.
- 외부·파일·미관측 scope 거부, queued target이 outside symlink로 바뀌면 injected scanner I/O 전 거부.
- I/O 후 target identity 교체 시 old candidate commit 금지, revision/baseline 유지.
- queued focus가 watch overflow를 잃지 않고 root refresh로 independent full-scan oracle에 수렴.
- concurrent tag overlay와 frozen reader aggregate 보존.

통합 테스트는 owned filesystem fixture와 semaphore gates로 순서를 제어한다. root recreation의 늦은 callback 검사는 bounded settling wait도 사용하므로 임의 OS scheduling 전체의 증명으로 확대하지 않는다. 첫 실행은 `/private/tmp`와 Foundation canonical `/tmp` 기대치 차이로 실패했고 fixture를 service와 같은 canonical 경로로 고쳤다. [첫 실패 로그](validation/r-backlog-2026-11-09/r06-lifecycle/selected-initial.log)는 보존했다.

root 요청 [config/export/headless/query/SNS 회귀](validation/r-backlog-2026-11-09/r06-lifecycle/root-config-query-sns-tests.log)도 **43 tests, 0 failures**다. filters: NativeConfigurationTests, NativeExportTemplateTests, ConfiguredExportIntegrationTests, HeadlessConfigurationTests, SubtreeQueryTests, QueryCursorLifetimeTests, SNSVolumeWireContractTests. 전체 release/TSAN/packaging과 앱 requester hookup 회귀는 root 후속 검증 범위다.

## 작은 idle latency probe

[`r06-focus-latency.swift`](../scripts/bench/r06-focus-latency.swift), [raw JSON](validation/r-backlog-2026-11-09/r06-lifecycle/latency.json). 실제 ScanService에 owned fixture 256 files, watch off, 한 process에서 10 alternating pairs를 실행했다. optimized probe가 debug Core object를 링크했으며 GUI/다른 host 활동이 함께 있었다. 요청→terminal elapsed median은 다음과 같다.

| 경로 | median | range |
|---|---:|---:|
| 기존 explicit scope rescan | 1.257ms | 1.200–1.352ms |
| 새 focus intent | 1.309ms | 1.256–1.369ms |

이 작은 idle 입력에서는 latency 이득을 입증하지 못했다. busy master 뒤의 focus는 직렬 대기하므로 원본의 별도 worker 같은 반응성 향상을 주장하지 않는다. 이번 이득은 owner 취소/교체·stale publication 방지라는 의미 경계이며 속도 최적화 결과가 아니다. 따라서 자동 활성화하지 않는다. 실제 큰 root의 master/focus latency·watch 공정성·메모리/CPU 및 native Windows scheduling 관찰은 남아 있다.

## 보관과 handoff

[source archive/manifest](validation/r-backlog-2026-11-09/r06-lifecycle/)에 Core/tests/probe/로그와 해시를 보관했다. 테스트 완료 후 root에게 source-ready와 `.build` 소유권 반환을 알렸으며 이후 production source는 변경하지 않는다. TODO/global backlog 완료 JSON은 수정하지 않았다. 원본 true parallel focus worker, 직접 mutable change 처리, Windows runtime 동등성의 남은 gap을 이 초기 admission 구현으로 닫지 않는다.
