# 빠른 개요 + 상세 스캔 정량 테스트 계획

작성일: 2026-11-16. 상태: 엔진 비교 harness와 11개 물리 입력 설정 엔진 실측 완료. GUI·캐시·증분 시나리오는 미실행. 아래 수치는 사전 합의용 채택 목표이며 측정 성과가 아니다. 결과는 [성과표](PROGRESSIVE_SCAN_RESULTS.md)에 기록한다.

## 1. 비교군과 실험 순서

| 군 | 구성 | 목적 |
|---|---|---|
| A | 현재 release POSIX scanner와 현재 UI | 기준선 |
| B | streaming bulk, 나머지 A와 동일 | 일괄 I/O 효과 분리 |
| C | catalog 요약, worker 1, 캐시 없음 | `searchfs`와 가벼운 모델 효과 |
| D | 채택 I/O + 개요/상세 재사용·공정한 우선순위 | 실제 첫 실행 경험 |
| E | D + 저장 요약·FSEvents 재개 | 두 번째 실행·증분 효과 |

모든 조합을 무조건 구현하지 않는다. 미지원 후보는 사유를 기록한다. D의 worker 1/2/4는 별도 실험이며 같은 물리 장치의 총 실행 수를 제한한다. A는 기존 partial publication까지 포함하고, 최종 완료 시점만 첫 결과로 간주해 불리하게 만들지 않는다. E는 A/D의 재실행 결과와 비교하며 캐시 없는 첫 실행과 섞지 않는다.

## 2. 재현 조건과 oracle

- 같은 컴퓨터·전원 모드·OS·볼륨·권한·release 최적화 조건을 사용한다. 소스/바이너리 hash와 옵션, 시작 free bytes, swap·메모리 압력, 동시 부하를 기록한다.
- fixture는 고정 seed와 manifest로 경로·부모·논리 크기·할당 크기·파일 종류·파일 수를 고정한다. 주입 metadata fixture는 집계/화면 kernel용이고 실제 I/O 성능의 대체 자료로 쓰지 않는다.
- 물리 fixture는 앱의 주 출력 지표인 할당 크기를 독립 POSIX oracle로 읽는다. 논리 크기도 별도 비교한다. sparse 파일은 실제 할당값으로 확인하고 clone/hardlink는 경로별 합산 계약을 유지한다.
- 읽기 전용 실사용 트리는 변경이 감지되면 최종 정확성 시험에서 제외하고 live 수렴 시나리오로 분류한다. 접근 불가 경로는 별도 상태와 오류 수를 비교한다.
- 볼륨 전체 시험은 물리 볼륨별 namespace를 고정한다. `/`의 firmlink와 Data/Volumes 별칭 때문에 같은 경로 집합을 중복 집계하지 않는지 확인한다. 작은 폴더 시험에서 catalog가 볼륨 전체를 읽는 비용도 포함한다.
- 신뢰할 수 있는 정확한 값은 manifest/oracle에서 가져온다. 디스크 전체 사용량이나 `du` 기본 출력은 하드링크/메타데이터 등의 의미가 다를 수 있어 그대로 정답으로 삼지 않는다.
- 첫 실행/재실행은 앱 캐시 상태이고, cold/warm은 OS 파일시스템 캐시 상태다. 서로 구분한다. fresh process는 OS cold cache를 보장하지 않는다. 재부팅 후 첫 접근은 별도 표본으로 남기며 임의 `purge`를 기본 절차로 쓰지 않는다.
- 최소 5개 alternating pairs(A/B, B/A 순서 교대)로 탐색한다. 채택 판정은 핵심 성능 셀마다 최소 20개 valid pairs를 확보한다. p50·p95·paired 개선율·95% bootstrap CI를 보고한다. nearest-rank p95를 사용하고 표본 수를 표기한다. CI가 판정 경계를 걸치면 판정 보류다.
- 오류/timeout/OOM은 결과에서 조용히 제거하지 않는다. 시도 수·실패 수·제외 사유를 보고하고, 실패율 gate에는 모두 포함한다. instrumentation 켠 release끼리 비교하고 overhead를 별도 확인한다.
- GUI는 같은 크기/깊이/필터/보임 상태를 사용한다. in-process monotonic 이벤트로 계측한다. MCP polling만으로 밀리초 UI 지연을 측정하지 않는다. 각 발행에 scope/revision/source를 연결하고 실제 draw 완료를 기록한다.

## 3. 지표 정의

`t0`는 앱이 scan 요청을 수락한 monotonic 시각이다. 앱 실행부터의 시간은 별도 `launch_to_overview_ms`로 보고한다. 화면을 가린 시험은 화면 표시 지표와 분리한다.

| 지표 | 정의·계산식 | 용도 |
|---|---|---|
| `first_partial_ms` | t0 → 첫 비어 있지 않은 지도 draw | 숫자만 빨리 나오는 착시 감시 |
| `useful_overview_ms` | t0 → 아래 품질 기준을 만족하는 지도 draw | 주요 체감 성과 |
| `top10_recall_at_2s/5s/10s` | 같은 scope의 oracle 상위 k개 중 표시된 개수 / k, k=min(10, 유효 폴더 수) | 큰 폴더 조기 발견 |
| `top10_byte_error_at_2s/5s/10s` | oracle top-k 폴더의 Σ abs(표시값−정답) / Σ정답; 미표시 항목은 0으로 계산 | 순위만 맞고 크기는 틀린 경우 감시 |
| `confirmed_byte_coverage_at_2s/5s/10s` | 중복 제거한 현재 확인 파일 할당 크기 / 접근 가능한 oracle 전체 크기 | 실제 확인 범위; 캐시·추정은 제외 |
| `rank_stable_ms` | t0 → top-k 집합이 최종 집합과 일치하고 완료까지 유지되는 최초 draw | 큰 폴더 순위 안정 시간 |
| `scan_complete_ms` | t0 → 모든 대상의 상세 처리·집계·오류 확정 | 엔진 총시간 |
| `final_visible_ms` | t0 → 최종 revision의 draw 완료 | UI까지 포함한 총시간 |
| `focus_detail_ms` | 정해진 클릭 입력 → 해당 scope 상세 완료 draw | 선택 폴더 응답 |
| `cancel_settle_ms` | 취소 입력 → worker 종료·늦은 결과 차단 상태 확정 | 취소 응답 |
| `peak_rss_mib` | 프로세스 RSS 최대값 / 2^20, baseline idle도 기록 | 최대 메모리 |
| `cpu_seconds`, `read_bytes`, `write_bytes` | t0~종료의 프로세스 누적 차이, 수집 수단/범위 표기 | 자원 비용 |
| `metadata_requests_per_entry` | metadata 요청 수 / oracle 항목 수 | 중복 I/O; syscall 크기별 카운트도 병기 |
| `revisited_entries` | 개요→상세에서 이미 얻은 필수 정보를 다시 읽은 항목 수 | 재사용 효과 |
| `restart_count`, `fallback_count` | catalog 재시작/legacy fallback 횟수와 읽은 항목 수 | API 실패 비용 |
| `event_convergence_ms` | fixture 마지막 변경 → oracle와 일치하는 결과 draw | 변경 반영 |

첫 유용한 개요는 **top-k recall ≥90%, top-k byte error ≤20%, 현재 관측 byte coverage ≥70%**를 동시에 만족하고 다음 1초간 발행에서도 유지되는 최초 화면으로 정한다. 화면에는 출처/미확인 상태도 표시되어야 한다. 최종 oracle가 있어야 평가 가능한 사후 벤치마크 정의이며 제품의 실시간 완료율로 쓰지 않는다. 전체 크기가 0인 fixture에서는 이 지표 대신 모든 대상의 존재/상태 정확성을 검사한다.

초기 캐시 화면은 `cached_overview_ms`로 별도 측정한다. 현재 관측 coverage가 없으면 `useful_overview_ms`로 인정하지 않는다. 캐시의 byte error와 캐시 생성 이후 경과 시간도 함께 보고한다.

개선율은 작을수록 좋은 지표에 `(A−후보)/A ×100`, 배율은 `A/후보`를 쓴다. A=0 또는 미도달이면 비율은 N/A다. 미도달을 0ms로 바꾸지 않는다. top-k 경계 동률은 byte 내림차순·정규화 경로 오름차순으로 고정한다. k=0 또는 byte 분모=0인 경우 N/A로 표기한다.

## 4. 테스트 시나리오

| ID | 입력·절차 | 핵심 관측·판정 |
|---|---|---|
| S01 작은 입력 | 1,000개 파일/50개 폴더, 앱 캐시 없음 | 총시간·첫 화면; 후보 선택 overhead 확인 |
| S02 작은 파일 다수 | 물리 100,000개 파일/5,000개 폴더; 확장 1,000,000개는 공간 확보 후 | useful overview, CPU/RSS, metadata 요청 수 |
| S03 wide 경계 | 한 폴더 4,095/4,096/4,097/4,100/100,000개 파일 | bulk cap 전후 재읽기·시간·메모리 cliff; 모든 경계별 보고 |
| S04 깊은 트리 | 64단계 이내, 작은 파일들과 마지막 단계의 큰 파일 | 깊은 큰 항목 발견, 조상 합계, path 길이 제한을 manifest에 기록 |
| S05 작은 파일/큰 파일 편향 | 99,990개 ×4KiB와 10개 ×32MiB, 실제 할당 확인 | 시간별 top-k/byte error; 파일 수 비례 추정의 실패 탐지 |
| S06 방문 순서 역전 | 같은 총 파일·폴더 수에서 큰 파일 폴더를 순회 앞/뒤에 배치 | 큰 분기의 순서에 따른 지연과 starvation |
| S07 불균형 분기 | 한 분기에 파일 90%, 나머지 10%를 20분기에 분산 | 분기별 첫 결과·최대 대기시간, 공정한 순회 효과 |
| S08 상세 우선순위 | 고정 시각 t0+2초에 고정 경로 진입, t0+4초에 다른 경로 진입 | focus_detail, 늦은 callback/선택 보존, 전체 완료 회귀 |
| S09 무변경 재실행 | 완결 요약 저장→앱 종료→동일 입력 재실행 | cached overview, 현재 재검증 시간, 읽기/쓰기량; D/E 비교 |
| S10 캐시 이후 변경 | 앱 종료 중 파일 1% 생성/수정/삭제·크기 변경 및 폴더 rename 후 재실행 | 과거 표시 출처, event 재개, 최종 경로/합계 일치 |
| S11 유실·캐시 복구 | event loss/wrap·오래된 checkpoint·손상/truncated cache·다른 볼륨 UUID 주입 | stale 결과의 완료 오표시 0, 재검사 후 수렴; seam 주입은 실제 kernel 유실과 구분 |
| S12 스캔 중 변경 | 알려진 시점에 생성/삭제/rename/크기 변경, 이후 변경 중단 | EBUSY 재시작 상한, 중복 0, 최종 안정 oracle로 수렴 |
| S13 오류·미지원 | 비특권 접근 거부, 삭제된 폴더, 필드 누락, 미지원 searchfs, batch 중간 오류 | 오류 표기·fallback·부분 결과 보존, 실패율 |
| S14 파일 의미 | hardlink/symlink/broken link/sparse/clone/resource fork/숨김/Unicode/0바이트 | 현재 경로별 합산·link 정책과 필드별 최종 대조 |
| S15 namespace | root/Data/firmlink/mount 포함, 재마운트·볼륨 변경은 fixture/주입 환경 | alias 중복, namespace coverage, 다른 볼륨 캐시 재사용 0 |
| S16 취소·수명 | t0+0.1/2/5초 취소, root 교체, 창 닫기, 같은 root 여러 창 | cancel p95, stale revision 0, worker/FD/reader 해제 |
| S17 UI·장시간 | 동일 탐색/hover/resize 20회, 창 가림/복귀, 30회 scan/cancel | 입력 지연·프레임 지연, 최종 최신 화면, idle RSS/FD 증가 추세 |
| S18 실제 사용 범위 | 사용자 홈·프로젝트 폴더·develop 볼륨을 같은 권한으로 읽기 전용 비교 | 규모별 총시간·품질 곡선·RSS, 변경량/오류/부하 병기 |
| S19 저장 공간 부족 | 여유 공간 작은 전용 test volume 또는 ENOSPC 주입, 캐시 저장 실패 | 스캔 유지, 캐시 비활성 fallback, 기존 캐시 손상 0, 쓰기 상한 |
| S20 Spotlight 없음 | 색인 없는 입력에서 같은 절차 실행 | 핵심 기능 정상, optional 경로 대기 없음 |

정적 fixture의 final 비교는 논리/할당 합계뿐 아니라 정규화 경로·종류·파일 ID와 필수 날짜/속성까지 검사한다. oracle와 앱의 접근 범위가 다르면 정확도 수치를 산출하지 않고 원인을 기록한다.

## 5. 사전 채택 gate

| 영역 | 채택 기준 |
|---|---|
| 최초 실행 체감 | S02/S05/S06/S07 각각 useful_overview p50이 A 대비 ≥50% 감소, p95 ≥30% 감소; S05/S06/S07에서 5초 top-k recall ≥90%, byte error ≤20% |
| 시간 예산 | 핵심 중간 규모 fixture에서 useful overview p95 ≤5초를 제품 목표로 추적. 초과 시 절대 목표 미달을 별도 표시; 상대 개선만으로 달성 선언 금지 |
| 총시간 | S02~S07 각각 final_visible p50/p95가 A 대비 10% 넘게 악화되지 않음. S01은 각 분위에서 증가분 ≤max(A의 10%, 50ms) |
| 메모리·중복 작업 | 각 핵심 셀 peak RSS p95 ≤max(A×1.10, A+32MiB). metadata 요청/항목이 A 대비 10% 넘게 증가하지 않음; 개요/상세 중복 재조회 원인 보고 |
| 최종 정확성 | 정적 fixture에서 필수 필드·경로·합계·counts의 차이 0, 중복 0. live fixture는 변경 정지 이후 일치. 접근 제한은 별도 불완전 상태 |
| 선택·취소 | S08 focus_detail p95 ≤2초 및 A 대비 10% 초과 회귀 없음. S16 cancel_settle p95 ≤1초; OS 호출이 막힌 실패도 기록 |
| 재실행 | S09 cached overview p95 ≤500ms, S10은 10만 파일/1% 변경 fixture에서 convergence p95 ≤5초. 과거 캐시의 현재 완료 오표시 0 |
| 자원·실패 | CPU seconds/read bytes p95가 각각 A 대비 20% 넘게 증가하지 않음. 캐시 초기 용량 상한 64MiB·갱신 쓰기량 기록, ENOSPC 정상 복구. timeout/OOM/crash/stale overwrite 0 |
| 수명·UI | S17 종료 10초 뒤 idle RSS가 첫 안정 cycle 대비 max(10%,32MiB) 넘게 증가하지 않고 FD/worker 활성 수가 baseline으로 복귀. 입력→반응 p95 ≤100ms이며 A 대비 max(10%,16ms) 초과 회귀 없음 |

위 기준은 이 작업의 초기 목표다. 구현 전에 변경할 수 있으나 이유와 버전을 남긴다. 결과를 본 뒤 기준을 조용히 완화하지 않는다. 후보 전체를 평균내서 wide/깊은 트리의 회귀를 숨기지 않는다. CI가 gate를 가로지르면 추가 표본 또는 판정 보류로 남긴다. 필수 fixture 미실행·실패·미지원 대체 경로 미검증이 있으면 전체 채택 완료로 표시하지 않는다.

## 6. 실행 산출물과 자동 보고 요구

[`scripts/bench/progressive-scan/`](../scripts/bench/progressive-scan/README.md)에 실제 release 비교·물리 fixture 생성·독립 oracle·raw 수집·통계 보고 도구를 구현했다. `run.py --help`와 README의 실제 실행 명령을 따른다. GUI draw, cache 복원과 FSEvents 재개 계측은 아직 미구현이다. instrumented profile에는 stat/bulk API 호출 수와 `proc_pid_rusage` V2의 프로세스 물리 read/write bytes를 추가했다. `readdir` 호출 수는 kernel syscall 수가 아니며, cached read의 물리 bytes가 0일 수 있다. 현재 runner의 `useful_callback_proxy_ms`는 사후 품질을 만족하는 엔진 callback 시점이며, 1초 유지와 실제 화면 draw를 관측한 `useful_overview_ms`가 아니다. 채택 상태는 전체 gate 미완료로 유지한다.

각 raw run은 `run_id, pair_id, variant, scenario, seed, source_hash, binary_hash, os, volume_id, fs_type, permission_scope, app_cache_state, os_cache_state, worker_limit, t0, exit_status, timeout, issue_count`와 위 지표를 저장한다. publication별 monotonic timestamp/scope/revision/source/top-k/관측 bytes를 JSONL로 남긴다. 미측정은 null, 실패는 명시 상태로 보존한다.

성과표 생성기는 셀별 n·실패 수·p50·p95·paired 변화율·95% CI·gate 통과/실패/보류를 출력한다. 2/5/10초 품질 곡선, 후보별 latency/RSS 비교 차트, 관련 raw/manifest 링크를 함께 만든다. 엔진-only 결과와 GUI 결과를 별도 표로 출력한다.

저장소가 있는 develop 볼륨의 공간이 부족해 물리 fixture·빌드는 `/private/tmp`에 생성했다. 별도 APFS image 시험 도중 백킹 시스템 여유가 1.2GiB로 줄어 중단·정리했고, 공간 회복 뒤 남은 입력은 시스템 임시 폴더에서 별도 기준선으로 측정했다. 실행 harness는 시나리오마다 가상 볼륨과 실제 백킹 공간을 확인하고, 생성 중에도 1GiB 백킹 reserve를 검사한다. 부족하면 명시적으로 중단/skip한다. skip을 통과로 계산하지 않는다. 사용자 실파일 삭제나 Spotlight 재색인을 성능 시험의 준비 단계로 수행하지 않는다.
