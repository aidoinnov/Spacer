# R01–R15 독립 재검토 — 2026-11-09

검토자는 현재 TODO의 R01–R15 원문, production 호출 경로, 후속 문서와 보존 로그를 대조했다. 이전 116/116 완료와 이번 R 백로그는 별개다. **R01–R15 전체 완료로 보고할 근거는 아직 없다.** Windows 동적 실행·실제 SNS 왕복은 미실행이며, Mac 구현·정적 근거·후보 평가·현재 통합 QA를 각각 구분해야 한다.

이 문서는 검토 시점의 근거다. root가 전체 Swift/TSAN/release/native QA를 진행 중이며, 완료 전 로그 꼬리나 과거 테스트 수치를 새로운 최종 결과로 사용하지 않았다. 검토 중 root가 허용한 R15 경합 수정은 별도 항목에 기록했다. TODO/상위 완료 JSON과 과거 raw/source/hash/ZIP은 변경하지 않았다.

## 범위별 판정

| ID | 실제 확보한 산출물 | 아직 남은 요구/판정 경계 |
|---|---|---|
| R01 | [Windows harness](R01_WINDOWS_RUNTIME_HARNESS.md), EXE/manual/embedded-help hash, 입력·실행·수동 GUI 관측 계획 | [verification](validation/r-backlog-2026-11-09/windows-harness/verification.json)은 LOCAL_PREPARATION_CHECKS_PASS이며 Windows runtime 및 PowerShell AST parse는 NOT_RUN. 동일 fixture의 옵션/동시성/CPU/RSS 결과가 없다. |
| R02 | SNS 독립 바이트 fixture·Mac codec 회귀, Windows harness의 MacSnapshot 입력 경로 | 실제 Windows 생성→Mac, Mac 생성→Windows 로드/다시 저장/동작 대조가 없다. Mac old writer와 hash 일치가 원본 왕복을 대체하지 않는다. |
| R03 | 기존 500ms zoom/rect 보간과 Reduce Motion 구현·기존 검증 | 일반 layout 재배치의 원본 영상/시간·옵션별 behavior 대조는 없다. 현재 MapTransition이 움직인다는 사실로 Windows 일반 재배치 동등성을 완료 처리할 수 없다. |
| R04 | DataCache RAM list/path segment 비교, miss 이후 ExpandFileName 정적 경로; 명시 CLI save/autosnapshot과 구분 | 실제 case/trailing separator/caller normalization hit 실험과 종료·재시작 자동 영구 cache 관찰이 없다. inspected config key에 없다는 것은 binary-wide 부재 증명이 아니다. |
| R05 | [focus-first 평가](R05_FOCUS_FIRST_EVALUATION.md), 270 samples/18 cases/5 pairs, 576 comparisons 및 frozen reader/COW/cancel 확인 | manifest는 evaluated_not_adopted_in_production. 작은 복잡 focus 이득과 large/root/empty 회귀가 함께 있어 무조건 도입하지 않은 판단은 합리적이다. production focus-first+skip 또는 GUI 부분 publish는 구현하지 않았다. |
| R06 | [원본 focus-worker 계약](R06_FOCUS_WORKER_CONTRACT.md), 현재 직렬 모델과 차이·안전한 구현 선행 조건 | 별도 focus job/owner/incarnation/overlap/merge 구현 및 AB/BA 동등성·공정성 측정이 없다. 현재 root별 직렬 rescan을 원본 별도 worker 도입이라고 부르면 안 된다. |
| R07 | [recovery 수정](R07_R08_SCAN_FOLLOWUP.md), [회계 정적 근거](R07_SPACE_ACCOUNTING_FINDINGS.md), SpaceAccounting + UI/MCP 표본시점 표시 | Windows 접근 거부/삭제/취소 동적 대조와 free/unknown/missing 실제 왕복은 남음. UI free/unknown 토글·면적 반영은 순수 계산 모듈과 별개다. 오류를 임의 용량 node로 바꾸지 않은 점은 맞다. |
| R08 | 취소 rescan baseline, navigation premature repair, truncated-issue root 승격, Mac recovery/FSEvents 회귀 | Windows elementChange producer action/order/rename/overflow와 직접 mutable mutation 동등성 미실행. Mac 부모 재스캔 수렴과 원본 event-thread 구조를 구분해야 한다. |
| R09 | [filter/navigation 후속](R09_FILTER_FOLLOWUP.md), age 소수초/zero, LF/CRLF glob, 빈 세미콜론, identity guard 수정·선택 41개 기록 | Unicode/ACP·Windows 시간 경계 및 실제 rename/tag/delete 변경 순서 대조는 남음. Mac predicate oracle와 Windows 동적 oracle는 다르다. |
| R10 | SNS v1–4, v2 explicit legacy page, 다중 top-level root decode/write/select, native UI 선택기와 CLI/MCP additive options | 실제 Windows fixture/양방향 runtime은 남음. DU parser 0x4547f0 정적 분석은 있으나 production DU reader·escaping 계약/실제 fixture는 없다. 현재 UI/ArtifactTransfer는 SNS만 읽는다. |
| R11 | [설정/export 근거](R11_CONFIG_EXPORT_FINDINGS.md), XML/file classes/템플릿/정렬/UTF8 LF 모듈, explicit CLI 및 worker/transaction, MCP 연결 | 전체 UI 설정 적용·사용자 class palette/분류·편집/저장 flow는 없다. Windows locale 숫자/날짜/age·malformed TinyXML·builtin menu flags·실제 왕복은 미확인. UI 미연결을 codec 구현 완료와 섞지 않는다. |
| R12 | [실제 develop 관측](validation/r-backlog-2026-11-09/live-volume-baseline/result.json), 6,236,823 files/855,528 folders, ~213s, 오류4, RSS/footprint 구분 | 이전 고정 CLI hash의 단일 live run이다. 현재 최종 엔진의 대규모 장시간 cancel/close/repeated-watch, 최종4개 이슈 상세, 공정한 before/after는 아직 별개다. 용량499.9GB와 경로 합계487.456GB를 같은 지표로 비교하지 않는다. |
| R13 | [30개 records/24함수](R13_INVALIDATION_FINDINGS.md), payload/high byte/filterID 오해 해소 | 정적 결론은 강하다. 모든 indirect alias/callback/UI option/event order 완전성과 runtime invalidate/skip은 남음. DU entry 주소 정정이 DU 기능 구현은 아니다. |
| R14 | [후보 profile](R14_CANDIDATE_PROFILES.md), [adaptive v2](R14_ADAPTIVE_V2.md), actual field oracle·fallback/cancel·24 tests, reader autorelease batch 측정 | default backend는 POSIX. bulk opt-in, path compression/hierarchical hit-test/lookup hint 미채택. wide v2 약19% 회귀·random hint/작은 hit-test 반례를 숨기지 않았다. 대표 실제 분포 end-to-end 실측 후 재선정해야 한다. |
| R15 | [cursor 계약](R15_QUERY_FOLLOWUP.md), bounded DFS/context reuse/explicit cancel/owner reset, 21개 선택+Python7 과거 검증; 아래 epoch 수정 추가 | 최신 production 연결의 native MCP QA·새 경합 회귀 전체 결과는 root 통합 기록 필요. STDIO notifications/cancelled 선점·disconnect cancel·hard deadline은 미지원이다. Windows 기능 이식으로 표현하면 안 된다. |

## R10 / R11 / R15 실제 연결 검토

### R10: SNS root와 인코딩

SNSSnapshot.decodeAll은 독립된 원본 절대 경로를 보존하고, decode(rootIndex:nil)는 복수 root일 때 선택 오류를 낸다. 가상 Mac root를 만들어 Windows 경로를 변환하지 않는다. UI는 코드페이지 선택 후 root 선택으로 재시도하며, CLI는 --list-roots/--snapshot-root-index, MCP는 snapshot_load inspect_only/root_index/legacy_code_page를 사용한다. SNS v2의 비ASCII 이름은 원본 code page 없이 추측하지 않는다. WindowsLegacyText를 XML과 공유하는 단일 utility로 추출했다.

현재 RootInfo inspection은 SNSSnapshot.decodeAll 전체를 호출한다. 큰 다중-root 파일을 metadata만 조회할 때도 모든 tree/문자열을 materialize한다. 잘못된 결과라는 뜻은 아니지만, 실제 memory budget/취소/선택 root만 decode하는 개선 기회다. ArtifactWorker가 blocking I/O를 분리한다고 메모리 상한이나 강제 취소가 생기지는 않는다. R14 stream-reader 검토에 연결할 수 있다.

확인한 production DU loader는 없다. DU missing 회계의 KiB 크기/상세 부족분 처리 정적 근거는 유용하지만, 문법과 escaping을 추측해 지원했다고 표시해서는 안 된다.

### R11: explicit 설정과 report job

ConfigurationFile은 4MiB/regular-file/DTD entity 제한을 가진 명시적 입력이다. full config는 normalized inspected index가 필수이며, standalone exportConfig는0을 선택한다. ArtifactWorker는 bounded 기존 executor에서 inspect/export를 수행한다. ConfiguredExportOptions는 frozen snapshot에 맞는 filter/root/mode/clock/formatter/budget/control을 전달하고, ArtifactFileTransaction이 성공한 rename을 commit으로 삼는다. final flush 도중 cancellation에도 publish 전 check가 있어 기존 destination을 보존한다.

검토 초기에 발견한 다음 두 MCP 문제는 root가 검토 중 수정했다.

- settings_keys/template byte count만 반환해 실제 설정 값·template을 관측할 수 없던 inspection: 현재 typed settings + raw extensions_text + configuration_index로 선택한 header/detail/footer를 제공한다.
- default report/snapshot_save가 report-only config/page/budget 옵션을 조용히 무시하던 경로: 현재 report_export와 configuration_path 조합을 검증해 거부한다.

schema 타입 검사는 Python bridge, bounded integer 검사는 Swift adapter에 있다. full config index 누락은 비동기 job failed로 보고되며, default report에 template이 자동 적용되지 않는다. inspection은 applied_to_window=false를 명시한다. 실제 최신 MCP inspection/indexed export/invalid option/native job 결과 검증은 root QA에서 확인해야 한다. CLI의 9-case 성공만 MCP의 native 연결 성공이라고 보고하지 않는다.

### R15: 발견한 stale-start race와 수정

기존 경로: MainActor가 QueryContext를 캡처 → detached page 대기 → owner가 revision publish/reset → 이전 context의 detached 작업이 새 cursor 생성. reset은 이미 있던 entries만 취소하므로 이 순서에서 stale snapshot이 다시 session에 들어갈 수 있었다.

수정: session이 lock 소유 UUID epoch를 둔다. Hub는 context와 같은 MainActor 구간에서 epoch를 캡처해 query에 전달한다. create/checkout의 같은 lock 안에서 epoch를 재검사한다. reset이 먼저 발생했으면 stale_revision으로 거부하며 cursor/lease를 만들지 않는다. 이미 running인 page는 기존 cooperative cancellation과 slot 수명을 유지한다. shutdown은 terminal closed 상태를 설정하므로 늦게 시작한 요청, 새로운 epoch로 온 요청, 기본 synchronous query도 cancelled로 거부한다. Store shutdown은 terminal shutdown을 호출한다. UI/store closure를 session에 장기 캡처하지 않았다.

AsyncStream gate로 detached cursor creation보다 reset/shutdown이 반드시 먼저 오도록 한 두 회귀와 Store shutdown 후 재개 거부 검사를 추가했다. child는 root의 build 소유권 때문에 이 수정 뒤 Swift를 실행하지 않았다. **이 수정은 root 최종 TSAN/release 검증 전까지 source-fixed/pending-validation이다.** 기존 21개 통과 기록이 이 새 회귀의 통과 증거는 아니다. 공개 epoch는 automation adapter 내부의 async-dispatch fence이며 원본 SpaceSniffer 설정/프로토콜 필드가 아니다.

## Parser/report 모듈 책임과 구체적 후속

설정 Data codec, 불변 template atom/evaluation, 필터된 report traversal, file transaction, I/O executor, UI/MCP adapter의 주된 변경 이유가 분리되어 있다. WindowsLegacyText 중복도 제거했다. 파일 개수 자체가 SRP를 증명하지는 않지만 현재 Core가 Automation/UI를 역참조하거나 UI model을 cursor에 보유하지 않는다.

다음 두 실제 개선은 검토 중 root가 수정하도록 승인했고, QA release 빌드 완료 신호 후 source와 회귀를 추가했다. child는 Swift 빌드를 실행하지 않았으며 root 통합 검증을 기다린다.

1. NativeConfiguration.encodedXML: caller가 만든 큰 settings/file class 문자열을 escape한 뒤4MiB를 검사하며, 최종 closing tags는 검사에서 빠진다. near-cap 출력이 decoder input cap을 넘고, 큰 문자열이 거절 전에 중간 복사를 만들 수 있다. full/standalone writer에 공유 bounded XMLBuilder를 적용했다. Unicode scalar별 실제 escaped UTF8 길이를 복사 전에 검사하고 선언·최종 closing tags까지 포함한다. export field 합계1MiB UTF16 조건도 bounded prefix로 보존했다. exact4MiB/one-over, escaped metadata, Unicode roundtrip 회귀3개를 추가했다.
2. NativeExportTemplate generic fallback: append마다 result.utf16.count를 다시 계산한다. 많은 작은 atom에서 반복 전체 길이 측정으로 비용이 커진다. incremental UTF16 counter로 변경해 기존 outputLimit/workLimit, Unicode code-unit 경계를 보존했다. 2,048개 Unicode atom과 output/work limit 회귀1개를 추가했다. 이 문제는 Eager evaluation을 lazy로 바꾸는 제안과 별개다. 원본의 eager 조건 branch 의미를 보존해야 한다.

남은 non-blocking 구조 기회: ConfiguredExportOptions.swift에는 job option 값, Mac formatter ownership, cancellation-aware file I/O wrapper가 함께 있다. 향후 변경이 커지면 formatter와 commit guard를 각 파일로 옮길 수 있으나 단순 파일 분리 자체를 성능 최적화나 원본 근거로 주장할 필요는 없다.

## 검증을 해석하는 기준

- R11 독립 Core 선택39/0과 app-facing38/0, 실제 --cli9건은 각각 [독립 로그](validation/r-backlog-2026-11-09/r11/focused-tests-final.log), [integration 결과](validation/r-backlog-2026-11-09/r11/integration/validation-result.json)의 source 시점이다. 숫자를 합쳐 unique test 수로 보고하지 않는다.
- R15 기존21/0과 Python7은 과거 source 시점이다. 이번 epoch/terminal-shutdown 수정이 포함된 root log를 별도로 연결해야 한다.
- 현재 docs/validation/r-backlog-2026-11-09/tsan-final.log의 중간 빌드 실패는 동시 source 수정으로 발생한 input-modified 오류였다. 이를 race sanitizer 발견이나 최종 통과로 오인하지 않는다. root의 재실행 결과가 최종 판정이다.
- 실제 Windows runtime NOT_RUN, PowerShell AST NOT_RUN, native GUI/IPC 아직 미관측인 항목을 명시해야 한다. 원본 함수 이름·문자열·pseudocode는 실행 결과가 아니다.
- 새 source의 성능 개선을 주장하려면 고정한 동일 입력/빌드·원시 표본·memory lifetime·동등성을 함께 봐야 한다. 7백만-node live run 한 번이나 다른 host 작업과 겹친 kernel ratio를 전체 앱 개선율로 확대하지 않는다.

최종 완료 보고는 R별로 `구현`, `평가 후 미채택`, `플랫폼 대체`, `정적 근거 확보`, `Windows runtime 필요`, `추가 기능 미구현`을 구분하는 것이 정확하다. 사용자에게 R01–R15를 전부 구현·동적 검증했다고 답할 단계는 아니다.

## 최신 source 재대조 정정 — 2026-11-09, frozen Core44파일 시점

위 표의 R06/R10 및 초반 연결 검토는 이 문서를 처음 작성한 source 시점의 기록이다. 그 뒤 production이 추가되어 다음 사항을 정정한다. 현재 [124-file source review](optimization-checklist.json)의 source_review와 [갱신 전/후 checklist 검증](validation/r-backlog-2026-11-09/checklist-review/)이 이 보충의 기준이다.

- **R06:** FocusScanRequests/FocusScanTarget과 ScanService.requestFocusRescan/cancelFocusRescan이 구현됐다. Store.rescanFocus와 async automationRescan의 nonroot 경로도 requester API에 연결됐다. latest ticket/owner/root incarnation/FIFO, target identity/realpath pre/post 검사, partial/obsolete terminal suppression, master/다른 owner 보존, watcher overflow 수명 회귀가 있다. 모든 작업은 기존 root별 직렬 admission에 남는다. 따라서 'owner 모델 없음'은 현재 source에 맞지 않으며, **owner-scoped intent 구현, 별도 병렬 master/focus worker는 미구현**이 정확하다. [현재 구현 계약](R06_FOCUS_LIFECYCLE_IMPLEMENTATION.md)을 따른다.
- **R10:** DUSnapshot.swift strict partial adapter와 ArtifactTransfer의 .DU dispatch, UI codepage/root 선택, CLI/MCP load 경로가 연결됐다. canonical0x4547f0의 space/dot/KiB/backslash/missing 회계를 구현한다. Windows ACP는 명시적으로 요구하며 unsupported UNC/escaping/모호 residual은 실패한다. 실제 원본 생산 fixture/CRT locale/왕복은 미검증이다. 따라서 'production DU loader 없음'은 현재 source에서 정정한다. [DU 근거와 제한](DU_SNAPSHOT_READER_FINDINGS.md)을 따른다. root는 CRLF를 단일 Character로 취급하는 Swift split 차이를 고쳤고 이전 실패 raw를 보존했다고 보고했다. 이 문서는 child가 재실행한 것으로 세지 않는다.
- **R15:** owner epoch fence와 terminal shutdown source 및 deterministic gate 회귀가 추가됐다. 최종 검증 판정은 이 수정이 포함된 root 로그를 따른다.
- **R11:** XML writer가 shared bounded UTF8 builder로 변경되어 escaped 확장·declaration·closing tags를 포함한 exact4MiB 경계를 검사한다. template fallback도 incremental UTF16 counter로 변경됐다. 이 문서 위의 '수정 예정'은 구현 전 기록이며 현재는 source에 반영된 상태다.

root가 전달한 중간 전체 TSAN244 tests/성능1skip/0fail은 마지막 Model cancellation helper 및 LocalizedError 변경 이전 시점이다. 이후 targeted TSAN이 OS dylib policy에 막힌 사실을 전체 코드 통과/코드 sanitizer 결함 어느 쪽으로도 왜곡하지 않는다. 최종 release/current tests/native QA는 root의 새 보고서를 사용한다.
