# disktree 도입 결과 — 2026-11-21

공개 소스를 대조하고, 기능 계약을 유지하는 변경을 적용했다. 최종 후보는 V9 및 후보 직렬 실행 양쪽에 대해 기존 회귀 기준을 통과했다. Universal 0.2.1 / 20261121.1의 GUI·ARM/Intel 호환 검증을 마쳤다. 배포 상태와 실행본 구분은 [설치 기록](validation/disktree-adoption-2026-11-21/deployment.json)을 따른다.

## 채택한 변경

- 이름 Data 임시 할당을 제거하고 raw UTF-8 검증을 유지했다. 별도 metadata 결과 배열 대신 검증 후 제자리 순열을 사용한다. 잘못된 입력은 수정 전에 거부한다.
- 짧은 이름의 inline bulk 한도를 131,072→262,144개로 늘렸다. 추정 metadata 예산 32MiB와 별도 read-ahead 예산은 유지한다. 이는 프로세스 RSS의 강제 상한이 아니다.
- read-ahead wave 사이에 inline 폴더 하나를 처리해 builder와 reader의 CPU 경합을 줄였다. 기본 병렬도2와 bounded queue/reader 수는 유지한다. 4 고정은 채택하지 않았다.
- 파일마다 수행하던 조상 합산을 디렉터리 단위로 모은다. 모든 publication·디렉터리 종료·취소 전에 flush해 부분 결과의 합계를 보존한다.
- native device/inode를 숫자로 보관하고 String API 경계에서 변환한다. opaque identity, 누락/null JSON, 기존 SNS/TXT 계약을 유지한다. 경로 결합의 임시 문자열도 줄였다.

`ObservedByteBatch`, `FileIdentity`, `SnapshotPath`는 각각 합산 임시값·identity 표현·경로 표기만 담당한다. tree/ID 변경 주체는 기존 builder다. 사용하지 않는 ordered 배열 경로와 eager identity 문자열 생성을 제거했다. 기존 검증·fallback·필터 metadata는 유지했다. disktree 원문을 복사하지 않고 아이디어를 독립 구현했다.

## 정량 판정

[사전 고정 계획](validation/disktree-adoption-2026-11-21/final-plan.json)의 7입력×99쌍×3변형=2,079회다. 일반 파일을 실제로 쓴 내부 APFS 소유 fixture에서 release Core를 비교했다. 순서 교차, warm/unknown cache 조건이며 전용 머신이나 cold-cache 결과가 아니다. 수집 중 우리 기존 root 앱을 일시 정지하고 원상 복귀했다([lease](validation/disktree-adoption-2026-11-21/final-lease.json)). 다른 프로세스의 부하는 통제하지 않았다.

| 입력 | V9 p50 / p95 ms | 현재 p50 / p95 ms | paired 중앙 개선율 |
|---|---:|---:|---:|
| 작은 입력 1,000 | 3.755 / 4.424 | 3.360 / 3.898 | 11.00% |
| 일반 10,000 | 13.841 / 15.345 | 12.989 / 14.978 | 6.73% |
| 단일 폴더 4,100 | 8.237 / 10.458 | 6.752 / 7.468 | 18.57% |
| 단일 폴더 100,000 | 205.361 / 223.780 | 157.903 / 177.138 | 22.97% |
| 기존 상한 초과 131,073 | 322.588 / 336.052 | 208.595 / 222.291 | 35.24% |
| 작은 폴더 1,000 | 14.611 / 15.947 | 14.111 / 15.860 | 3.01% |
| 깊이 200 | 5.501 / 6.205 | 5.488 / 6.264 | 0.10% |

모든 셀에서 정확성, p50/p95 회귀≤10%, paired 95% CI 하한≥−10%, CPU p95 회귀≤20%, RSS p95≤max(기준×1.10, 기준+32MiB)를 V9 및 현재 직렬 양쪽으로 통과했다. 깊은 트리가 유의하게 빨라졌다는 뜻은 아니다. [전체 CI·CPU·RSS 판정](validation/disktree-adoption-2026-11-21/final-scorecard.md), [원시 표본](validation/disktree-adoption-2026-11-21/final-99.json.gz).

상한 초과 입력의 RSS p95는 58.73→73.97MiB로 증가했다. 더 넓은 bulk 허용의 비용이며 기존 +32MiB 기준 안이다. 모든 입력에서 메모리가 감소했다고 주장하지 않는다.

## 메모리와 경쟁 엔진 재비교

같은 metadata를 가진 100만 노드 합성 모델 3쌍에서 footprint는 435.49→389.54MiB(약10.55% 감소)였다. 파일시스템을 읽는 벤치마크가 아니며 단일 슬롯은 오히려184→192bytes다. 문자열 heap 할당 감소가 전체 절감을 만든다. [모델 원시값](validation/disktree-adoption-2026-11-21/model-memory.json).

실제 10만 파일의 별도3쌍에서는 scan 후 RSS 중앙값이 V9 41.69→현재37.05MiB였다. pinned disktree는1 worker14.33MiB,4 workers15.16MiB여서 여전히 차이가 크다. 검증/digest 전에 같은 API로 측정했으며 RSS·footprint·프로세스 peak는 별도 필드다. 실제100만 파일은 V9 대 disktree 측정만 있고, 최종 후보의 실제100만 파일 검증은 하지 않았다. [현재10만](validation/disktree-adoption-2026-11-21/memory-current-100k.json), [기존100만](validation/disktree-adoption-2026-11-21/memory-v9.json).

고정 disktree Core `9b18b272ca3c5a145f6ff58eaf89dc4d311eeaea`와 최종 후보를 다시 비교했다. 2입력×15쌍×7변형=210회에서 아래 p50을 얻었다.

| 입력 | V9 기본2 | 현재 기본2 | 현재4(실험) | disktree1 | disktree2 | disktree4 |
|---|---:|---:|---:|---:|---:|---:|
| 단일 폴더2만(ms) | 44.186 | 34.025 | 33.988 | 21.451 | 21.321 | 21.035 |
| 200폴더×100(ms) | 29.751 | 27.328 | 21.371 | 20.442 | 12.392 | 8.480 |

현재 기본2는 disktree4보다 각각 약1.62배·3.22배 시간이 걸린다. 우리 기능·metadata·snapshot 비용이 더 있고 작업량이 같지 않으므로 Swift/GPUI 언어·GUI 우열로 해석하지 않는다. 전체 볼륨에서 항상 상대가 빠르다는 근거도 아니다. [전체 worker matrix](validation/disktree-adoption-2026-11-21/final-disktree-matrix.json).

## 정확성·통합 검증

- Swift 전체301개: 실패0, 환경 skip4. 중첩 볼륨 fixture를 준비한 후 해당3개를 별도로 실행해 모두 통과했다. 나머지1개는 명시적 render 성능 테스트다.
- TSAN22개 실패0. 기본 SwiftPM helper의 dylib 로딩이 플랫폼 정책으로 거부되어, 기존 disposable ad-hoc signed xctest host로 실행했다. 시스템 정책은 변경하지 않았다. 판정/merge 도구 각각7개 통과.
- 실제 GUI20만 파일: 조기 개요, 취소, 상세 재검사, create/rename 감시, 빈 root 교체 통과. 20회 native draw 확인 p50 93.619ms/p95 99.354ms, 마지막 상세 재검사1,280.311ms. MCP 전송·poll을 포함한 상한이며 이전 GUI와 통제된 전후 비교는 아니다. [GUI 기록·이미지](validation/disktree-adoption-2026-11-21/gui/gui-delivery.json).
- ARM/Intel Universal CLI, SNS 저장/로드, TXT byte 동일성, 선택 볼륨/전체 볼륨, 실제 중첩 볼륨 GUI·watch·캐시를 검증했다. [CLI](validation/disktree-adoption-2026-11-21/cli/universal-cli.json), [볼륨](validation/disktree-adoption-2026-11-21/scope-gui/packaging.json). 소유 fixture와 두 디스크 이미지는 정리했다.

## 기각·보류와 다음 과제

초기 bulk-first는 namespace 계약을 생략하고 상한 초과 입력도 느려 기각했다. safe-decode100쌍 및 cadence51쌍/quiet51쌍은 당시 CPU/p95 기준을 통과하지 못해 보류했다. 실패 표본과 고정 소스를 보존하며 최종 후보의99쌍과 합치지 않았다. phase probe는 중첩 wall 시간으로 CPU 기여도를 단정하지 않는다. allocation probe는 일부 malloc 경로의 누적 요청이며 live heap 전체가 아니다.

다음은 미완료다: 별도 readdir를 완전히 없애는 안전한 namespace 설계, scratch 재사용의 독립 평가, metadata 축소 소비자 조사, 경로 미보유 compact store, 불균형 분기의 작은 sibling 지연 정량화, resumable directory cursor. **disktree도 폴더 중간 양보를 제공한다고 확인되지 않았다.** worker4 고정이나 전체 파일 필드 삭제로 격차를 숨기지 않았다.

실제 root 앱에서는 반복 scan/watch 작업과 큰 전체 footprint가 관측된다. 이번 Core 모델 절감이 GUI 앱 전체 메모리를 해결했다는 증거는 없다. root refresh의 발생 사유·빈도, issue 누락 시 escalation, 스레드 우선순위와 live snapshot 보유를 별도 계측해야 한다. 현재 sample만으로 원인을 확정하지 않는다.

[실행 TODO와 항목별 처분](DISKTREE_ADOPTION_TODO.md), [재현·실패 기록](validation/disktree-adoption-2026-11-21/README.md), [측정 도구](../scripts/bench/disktree-adoption/README.md).
