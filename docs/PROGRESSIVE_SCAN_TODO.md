# 빠른 개요 + 상세 스캔 TODO

2026-11-20 후속 완료: [최종 성과](SCAN_DELIVERY_RESULTS.md). 50ms 이후 수락된 상세 snapshot을 bounded top16/16 개요로 재사용하며 native draw를 계측했다. 최종 GUI20회 p95 299ms, 20만 파일 상세 재검사1.01초. 기본 앱0.2.0 배포 완료. 아래2026-11-16 catalog/streaming 후보 평가는 과거 기록이고, 영속 cache·공정한 resumable 순회는 이번 범위에 포함하지 않는다.

작성일: 2026-11-16. 사용자 요구: 정확도가 완성되기 전에도 큰 폴더와 파일을 먼저 볼 수 있고, 뒤에서 상세 결과로 보정한다. 개선 여부를 정량 테스트로 판단한다.

상태: release 엔진 측정 harness·실험용 streaming bulk 후보 구현 및 엔진 실측 완료. 앱 기본 backend와 UI는 아직 변경하지 않았다. 이 문서의 목표 수치는 실측 성과가 아니다.

관련 문서: [테스트 계획](PROGRESSIVE_SCAN_TEST_PLAN.md), [성과표](PROGRESSIVE_SCAN_RESULTS.md), [기존 bulk 실측](R14_CANDIDATE_PROFILES.md), [adaptive 후속](R14_ADAPTIVE_V2.md), [기존 focus 우선 평가](R05_FOCUS_FIRST_EVALUATION.md).

## 확인한 출발점

- 현재 `DiskScanner` 기본 backend는 `.posix`이며 단일 스캔의 가변 트리는 한 worker가 소유한다. 프로세스 admission 상한 8을 단일 볼륨의 8개 병렬 스캔으로 해석하지 않는다.
- 기존 bulk 후보는 폴더 전체를 bounded 수집한다. 한도를 넘으면 버리고 POSIX로 다시 읽어 wide fixture에서 약 42% 느려졌다. adaptive 후속도 wide 중앙값 약 19% 회귀여서 기본 활성화를 보류했다.
- 2026-11-16 읽기 전용 probe에서 `/`, `/System/Volumes/Data`, `/Volumes/develop`은 `searchfs` capability를 보고했다. Data/develop에서 이름·종류·파일 ID·부모 ID·크기를 요청한 각 1회 호출은 128개 결과를 반환했다. `EAGAIN`은 부분 결과를 뜻한다. record 길이만 확인했으며 필드별 oracle 대조·전체 처리량·전체 정확도는 아직 검증하지 않았다. 이 probe의 원시 로그는 채팅에만 있고 재현 harness는 미작성이다.
- 같은 시점 `mdutil -s /Volumes/develop`은 `No index`였다. Spotlight를 필수 경로로 두지 않는다.
- 기존 디렉터리 자체 크기를 하위 전체 합계로 간주하지 않는다. 얕은 깊이 조회만으로 깊은 파일의 용량이 드러나지는 않는다.

## 2026-11-16 실행에서 추가로 확인한 사실

- [실행 스크립트](../scripts/bench/progressive-scan/README.md), [원시 결과](validation/progressive-scan-2026-11-16/paired-20/report.json), [실행 당시 소스](validation/progressive-scan-2026-11-16/source-manifest.json)를 추가했다. 엔진 callback 준비 시점은 실제 화면 draw 시점과 구분한다.
- `NativeDirectoryMetadata.stream`과 internal `.streaming` backend를 추가했다. 폴더 전체 cap 대신 각 배치를 검증·소비하고, 후속 batch 오류 때 이미 소비한 이름을 중복 합산하지 않는다. `.posix` 기본값은 유지한다.
- 초기 focused Swift 14개와 Python 성과 계산 5개 테스트는 실패 0이었다. 최종 확대 회귀 결과는 실행 로그로 별도 확정한다.
- catalog의 일반 파일 fixture 합계가 맞아도 모든 종류의 정확성을 보장하지 않는다. [실제 APFS 필드 oracle](validation/progressive-scan-2026-11-16/catalog-fields.json)에서 symlink/FIFO가 일반 파일 종류로 반환됐고 link 논리 크기도 기존 규칙과 달랐다. [실제 develop 볼륨](validation/progressive-scan-2026-11-16/catalog-live.json)에서는 동일 alias/동일 record의 반복 반환을 감지했다. 현재 catalog 후보는 정확한 상세 backend로 채택하지 않는다. 해당 시험의 실패도 원시 결과로 보존한다.
- 반복 측정은 별도 APFS sparse image를 사용하며 호스트는 다른 개발 작업이 실행 중이다. warm/unknown OS cache 결과이고 장비 전체나 사용자 볼륨 성능을 대표하지 않는다.

## 설계 계약

빠른 개요와 상세 결과는 같은 발견 데이터를 재사용한다. 요약을 위해 모든 파일을 읽은 뒤 상세를 위해 무조건 전체를 다시 읽는 구조는 피한다. `searchfs`가 필요한 상세 필드를 충분히 제공하면 별도 재순회 없이 상세를 채우는 후보도 비교한다.

개요는 폴더 집계와 제한된 큰 파일 목록을 우선 보유한다. 전체 파일 트리·날짜·속성은 필요에 따라 채운다. 메모리 절약과 상세 재사용 사이의 교환관계는 실제 재조회량까지 측정한다. 디스크 캐시를 쓴다면 읽기/쓰기량과 용량 상한을 포함한다.

표시 값마다 `이전 결과 / 현재 발견량 / 추정값 / 상세 완료 / 접근 제한`의 출처와 상태를 구분한다. 미확인 영역을 0바이트로 확정하거나, 과거 캐시에 현재 발견량을 중복 합산하지 않는다. 개요에서 상세로 전환할 때 추정 기여분을 해당 scope의 관측값으로 교체한다.

첫 실행의 균형 잡힌 수집에는 폴더별 처리 예산과 공정한 순회를 평가한다. 열린 폴더를 우선하되 나머지가 영구 대기하지 않도록 한다. 파일 수나 직접 자식 수만으로 하위 용량을 비례 추정하지 않는다.

APFS의 경로별 할당 크기 합계와 삭제 시 회수 가능한 공간을 구분한다. 하드링크·clone·스냅샷·접근 불가 영역이 있으므로 최종 파일 합계를 시스템 사용량과 강제로 일치시키지 않는다.

## 실행 순서

| ID | 작업 | 선행 조건 | 산출물·완료 기준 |
|---|---|---|---|
| P00 | 기준선·oracle·계측 | 없음 | 동일 release 입력/빌드 manifest, 현재 앱 raw 결과, 지표 이벤트 정의 |
| P01 | 요약 상태와 병합 계약 | P00 | 출처·scope·revision·완성도 모델, 중복 합산/과거 값 역전/늦은 callback 방지 |
| P02 | `searchfs` 재현 probe | P00 | capability/요청 필드 대조, 재개·EBUSY·취소·미지원 처리, 기존 scanner와 비교 |
| P03 | streaming bulk 후보 | P00 | 배치별 처리·메모리 상한, 4,096 경계/초대형 폴더 재읽기 비용 검증 |
| P04 | 개요 집계와 작업 스케줄링 | P01~P03 평가 | top-K/폴더 합계, 공정한 순회, 선택 scope 우선, worker 1/2/4 비교 |
| P05 | 상세 보정과 UI 통합 | P04 | 실제 화면의 첫 유용한 개요 계측, 출처 표시, 선택·탐색·취소·조회 일관성 |
| P06 | 재실행용 요약 캐시 | P01, P05 | 볼륨/루트 identity, 시각, schema, event checkpoint, 용량 상한·손상 복구 |
| P07 | FSEvents 재개·증분 검증 | P06 | 체크포인트 이후 변경 반영, loss/wrap/remount 시 재검사, stale 상태 노출 |
| P08 | 정량 비교·채택 결정 | P02~P07 | 테스트 계획의 raw/성과표, 필수 gate 모두 통과 또는 명시적 미채택 |
| P09 | 통합 회귀·패키징 | P08에서 채택 | 관련 기존 테스트, 동시성 변경 TSAN, release 앱 실제 실행·UI 검증 |

각 항목은 독립 비교 뒤 채택한다. `searchfs`, bulk, 병렬화, 캐시를 한 번에 켜서 원인을 알 수 없게 만들지 않는다. 작은 폴더는 POSIX, 볼륨 개요는 catalog처럼 범위별 backend 선택도 허용하되 선택 비용을 측정한다.

## 체크리스트

- [x] 사용자 요구와 구현 순서 문서화
- [x] 정량 시나리오·계산식·판정 기준·성과표 양식 작성
- [x] 실제 release scanner의 독립 oracle·반복 실행·p50/p95/CI·성과 계산 harness 구현
- [x] 실험용 batch streaming과 wide/후속 오류/취소 회귀 추가
- [ ] P00 전체 기준선 확정: 엔진 실측과 별도로 실제 GUI 계측·누락 지표 보강
- [ ] P01 상태·병합 계약 검증
- [x] P02 탐색 평가: catalog 실제 호출·regular 합계·비정규 파일 oracle의 실패 근거 확보, 상세 backend 채택 보류 결정
- [ ] P02 후속: 개요 힌트로 사용할 경우 종류/alias 보정·오류/재시작·메모리 예산 계약 추가
- [x] P03 실험 범위: batch streaming과 wide 4,095/4,096/4,097/4,100/100,000 비교, fallback 중복 방지 확인
- [ ] P03 통합 범위: sibling/ID 순서에 따른 treemap·SNS/TXT tie 동등성 및 볼륨별 fallback 비용 검증
- [ ] P04 후보별 개요·스케줄링 성능 비교
- [ ] P05 앱 화면 통합과 첫 유용한 개요 실측
- [ ] P06~P07 캐시·증분 재실행 검증
- [x] P08 엔진 비교 범위: 11개 물리 입력 설정 525회 raw·독립 oracle·p50/p95/CI·성과표 작성
- [x] 전체 Swift 회귀 248개 중 1개 명시적 release-only skip, 실패 0; Python 성과·gate·공간 guard 9개 통과
- [ ] P08 전체 채택: GUI·캐시·수명·보류된 gate 검증 후 결정
- [ ] P09 회귀·패키징·사용 앱 검증

## API 근거

- [Apple searchfs](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/searchfs.2): 볼륨 범위, 부분 반환, 지원 검사, 재시작 조건. 실제 지원 필드·동작은 볼륨별로 검증한다.
- [Apple getattrlistbulk](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/getattrlistbulk.2): 여러 항목 속성 일괄 반환, returned attributes와 개별 오류 처리.
- [Apple getattrlist](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/getattrlist.2): 필요한 필드만 요청하며 directory entry count의 조회 비용도 고려한다.
- [Apple FSEvents](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html): 영속 이벤트·변경 감지·유실 시 재검사.

## 1차 실측 뒤의 다음 구현 범위

현재 성과는 기존 상세 scanner의 일괄 I/O 개선이다. 별도의 개요 UI나 두 단계 스캔이 완성된 상태가 아니다. S05 총시간 p95 점 추정이 10% 회귀 기준을 초과했고, 나머지도 GUI 목표는 측정하지 않았으므로 기본 backend는 변경하지 않는다.

다음 후보는 catalog의 불확실한 종류 정보를 그대로 확정하지 않고, streaming discovery가 반환한 검증된 metadata를 공유하는 개요/상세 pipeline이다. 개요에는 폴더 집계와 bounded top-K만 유지하고, 같은 batch를 상세 builder에 넘긴다. batch 큐 상한·backpressure·취소 세대·source revision을 명시하고, 별도 전체 재읽기 없이 초기 지도와 상세 트리가 수렴하는지 먼저 확인한다. 보관 batch와 상세 트리의 동시 보유 메모리도 gate에 포함한다. 사용자 선택 scope 우선 처리와 공정한 분기 순회는 이 상태 계약 뒤에 붙인다.
