# V00 볼륨 범위 검증 성과

2026-11-19. 후보V3, 입력별100 pairs ×3변형. 동일 범위 회귀 gate: **미달/보류**.

같은 파일을 더 빨리 읽는 엔진 성과와, 선택 범위 밖의 볼륨을 읽지 않아 줄어든 작업량을 구분한다. 공유 호스트·warm/unknown cache·릴리스 엔진 완료 시간이다. GUI draw 시간이나 전체 실제 볼륨 속도를 의미하지 않는다.

| 입력·변형 | 파일 / 폴더 | p50 / p95 ms | CPU p95 ms | RSS p95 MiB |
|---|---:|---:|---:|---:|
| mounted · before_all | 6100 / 37 | 15.99 / 29.98 | 24.57 | 8.02 |
| mounted · after_all | 6100 / 37 | 16.05 / 30.23 | 25.35 | 7.97 |
| mounted · after_selected | 100 / 5 | 1.88 / 5.69 | 3.01 | 5.94 |
| control10000 · before_all | 10000 / 101 | 49.04 / 107.54 | 49.16 | 10.22 |
| control10000 · after_all | 10000 / 101 | 49.71 / 124.33 | 50.18 | 10.25 |
| control10000 · after_selected | 10000 / 101 | 50.77 / 99.03 | 49.26 | 10.38 |

## 동일 범위 판정

| 입력·후보 | paired 감소율 [95% CI] | 판정·미달 항목 |
|---|---|---|
| mounted · after_all | 0.22% [-2.13, 2.86] | 통과 |
| control10000 · after_all | 0.63% [-8.27, 13.04] | 보류: latency |
| control10000 · after_selected | 2.68% [-9.56, 11.33] | 통과 |

기준: 동일 scope 파일·필드 digest 정확성, p50/p95 회귀≤10%, paired CI하한≥−10%, CPU p95회귀≤20%, RSS p95≤max(이전×1.10, 이전+32MiB). 모든 시도와 pair를 분모에 포함한다.

## 범위·정확성

- 기본은 선택 볼륨만. `--include-mounted-volumes` 또는 GUI의 다른 볼륨 포함 옵션으로 범위를 확장한다. 옵션 변경 시 새 검사로 시작하며 mode별 root cache는 분리하고 전역 scan admission은 공유한다.
- 실제 중첩 HFS+ 이미지 두 개에서 기본100개/300 logical bytes/5폴더, 포함6100개/30300 bytes/37폴더를 확인했다. 기본은 경계1곳을 기록하고 외부 트리의 폴더를 열지 않는다. 이는 범위 축소 효과다.
- 이미 아는 mount는 target lstat 이전에 제외한다. getfsstat MNT_NOWAIT와 초기4096개 미만의 mount count 및16개 여유 슬롯을 사용하며 실패/초과는 검사 오류로 표시한다. mount 이름 정규화로 remote 파일시스템을 조회하지 않는다.
- `/`에서는 APFS System/Data 연결의 Users/private를 유지하고 `/System/Volumes/Data` 직접 별칭은 두 모드 모두 제외한다. 임의의 symlink/hardlink를 물리 공간으로 deduplicate한다는 뜻은 아니다.
- 부분 재검사는 원래 root를 anchor로 사용한다. 제외 경계의 일반 watch 이벤트와 focus 요청을 차단하며, mount/loss 이벤트는 기존 full-refresh 복구 규칙을 따른다. 다른 볼륨의 free/total을 root의 용량으로 덮어쓰지 않는다.
- 제외 정보는 오류와 별도이며 최대500개 경로와 전체 count를 보유한다. truncated provenance는 다음 작업에서 root refresh로 승격한다. snapshot merge는 scope 안의 제외 정보만 교체하고 mode 혼합을 거부한다.
- 기존 SNS 형식에는 이 Mac-only provenance를 추가하지 않았다. 오래된 JSON/SNS를 읽을 때 scope는 unknown이며 현재 volume 정책을 소급해 붙이지 않는다.
- mount inventory와 파일 트리는 atomic snapshot이 아니다. 실행 중 새 mount/동일 device alias 변경은 관측 및 다음 watcher refresh로 수렴한다. 동적 remount 전체 조합의 원자적 보장을 주장하지 않는다.

## 근거

- [원시100-pair 측정](validation/scan-scope-2026-11-19/comparison-v3-100.json), [사전 계획·소스 hash](validation/scan-scope-2026-11-19/v3-plan.json)
- [테스트·패키지·cleanup 기록](validation/scan-scope-2026-11-19/README.md), [실행 방법](../scripts/bench/scan-scope/README.md)
- V2의 추가 scope 검사 비용과 미달 gate는 comparison20.json으로 보존했다. V3은 scalar DeviceRule과 boundary 없는 폴더 fast path로 수정했다. 표본 수100은 수집 전에 고정했고 같은 후보를 통과할 때까지 반복하지 않는다.
