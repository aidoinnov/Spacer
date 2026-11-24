> 후속: [공간 정리·성능 사전검사와 종료 62회 추가 확인](PERFORMANCE_EXIT_RECHECK_RESULTS.md). 정식 수집 조건을 통과하지 못해 후보는 계속 미채택이다.

# 공통 노드 저장 개선 후보 — 2026-11-24

**개발 소스의 DiskNode 저장 간격을 184→168바이트로 줄였다(8.70%).** Mac 합성 100만 파일 모델의 RSS 중앙값은 375.72→359.75MiB, 약 15.97MiB(4.25%) 감소했다. 현재 설치 앱에는 반영하지 않았다. 정식 성능 채택 절차는 호스트 기준 미달로 중단됐다.

## 변경과 책임

`Model.swift`는 경로의 부모 문자열과 기존 `name`을 공유해 파일 이름의 중복 저장을 없앤다. 기존 `NodePathStorage`는 정확한 UTF-8 leaf/name 일치 여부를 확인하는 생성 어댑터로 사용한다. public caller/import의 임의 경로, Windows/UNC, 중복 separator와 Unicode 표기를 그대로 보존한다.

공개 `name` 수정 시 이전 경로를 먼저 literal로 보존하고, `path` 수정 시 이름과의 연결을 해제한다. 두 속성의 기존 독립 변경 의미를 유지한다. Equatable은 표현 방식이 달라도 같은 경로 값을 비교하며, 기존 raw UTF-8 변경 감지는 유지한다. SNS/JSON의 키·필드·파일 ID·native metadata와 부모 ID의 전체 Int 범위는 그대로다. 인덱스를 32비트로 축소하거나 메타데이터를 삭제하지 않았다.

이 모델은 Mac Core와 Windows ExplorerDomain의 canonical 공유 소스다. OS 분기를 추가하지 않았다. 동일한 저장 동작 테스트를 Core/Domain 모듈에서 재사용하며, Windows에서는 같은 테스트 파일을 materialize했다.

## 메모리 측정

Mac arm64의 동일 release 프로필로 수정 전·후를 빌드했다. 긴 동일 경로·파일 ID·native metadata를 가진 모델을 만들고, validation/hash 전에 같은 `proc_pid_rusage` V2 API로 RSS를 읽었다. 1,000분기, 각 크기 3쌍, 순서 교대 총 12개 프로세스다. 자체 빌드·테스트와 수집은 순차 실행했다. 외부 작업이 있는 공유 호스트의 탐색 측정이며 파일시스템/GUI/Windows 앱 RSS나 속도 개선율은 아니다.

| 합성 파일 수 | 전체 노드 수 | 기존 RSS 중앙값 | 168B 후보 RSS 중앙값 | 감소 |
|---|---:|---:|---:|---:|
| 100,000 | 101,001 | 41.53MiB | 40.03MiB | 1.50MiB |
| 1,000,000 | 1,001,001 | 375.72MiB | 359.75MiB | 15.97MiB |

파일·폴더·노드 수, logical/allocated 합계와 pair digest가 모두 일치했다. 노드 1,001,001개의 인라인 저장 간격 차이는 약 15.27MiB다. RSS에는 할당기·런타임·페이지 등도 포함하므로 구조체 크기와 감소율이 같다고 가정하지 않는다. 이 프로필은 합성 모델이며 앞선 실제 파일 순회 207MiB/disktree 114MiB와 직접 비교할 수 없다.

## 제외한 160B 실험

부모 Optional<Int>의 presence를 다른 flag 옆에 저장하면 전체 Int/nil 의미를 유지하면서 160바이트가 됐다. 양쪽 단위 테스트와 별도 TSAN도 통과했지만, 추가 RSS 절감 근거가 없었다. 168B/160B를 같은 데이터·순서 교대로 직접 대조한 결과는 다음과 같다.

| 합성 파일 수 | 168B RSS 중앙값 | 160B RSS 중앙값 |
|---|---:|---:|
| 100,000 | 40.20MiB | 40.05MiB |
| 1,000,000 | 359.81MiB | 361.50MiB |

3쌍의 탐색 결과가 모든 환경에서 160B가 불리하다는 증거는 아니다. 이번에는 추가 표현 변경을 유지할 실측 근거가 부족해 부모 ID를 기존 Optional<Int>로 되돌렸다. 추가 RSS 차이의 원인을 heap trace로 확정하지 않았다. 두 후보와 수정 전을 포함한 36개 메모리 측정 원문·각 소스·바이너리를 모두 보존했다. 원문 파일명 `model-final`은 중간 160B 실험이며 선택본은 `chosen-model-168`이다.

## 정확성·동시성·플랫폼 검증

- 선택본 Core/자동화 313개: 실패 0, nested-volume fixture가 없어 3개 skip.
- Mac ExplorerDomain 11개, Windows 132 release ExplorerDomain 11개: 실패 0. 양쪽 실제 MemoryLayout stride 168 확인.
- 선택본 TSAN 17개(공유 저장 5, 기존 회귀 7, resource 5): 실패·race 경고 0. 실행한 경우에 대한 판정이며 모든 race 부재 증명은 아니다.
- 같은 release probe의 7입력×2쌍×4변형, 총 56회: 파일/폴더/바이트 oracle·digest 일치, 자체 fixture 정리 통과. 작은 입력·대형 단일 폴더·깊은 트리를 포함한다. 2쌍 정확성 smoke이므로 시간 값과 raw gate flag를 성능 채택에 사용하지 않는다.
- canonical 43개 링크/복사 및 GPUI 경계 검사 통과. Windows의 실제 compiler package 대상 32개 hash와 선택본 3개 source hash를 대조했다. Mac 전용 target을 Windows 검증으로 주장하지 않는다.

TSAN의 SwiftPM discovery helper는 OS의 sanitizer 로드 정책에 막혔다. 자체 test bundle의 디버그 서명만으로는 해결되지 않았고, 자체 복사한 xctest 실행기에 디버그 서명과 개발 library 경로를 적용해 17개를 실제 실행했다. 최초 실패·missing library 오류와 성공 원문을 모두 보존했다. 시스템/toolchain이나 설치 앱의 서명은 수정하지 않았다.

## 성능 채택과 남은 일

선택본으로 기존 `run_acceptance.py`를 실행했다. CPU 유휴율 33.84–40.69%(최소 70%), load1 12.51–13.25(한도 10), pressure 2(필수 1)로 `host_not_admitted`였다. swapout/disk 조건은 통과했다. **A/A 100쌍과 정식 7입력 21쌍은 실행하지 않았다.** 다른 작업을 중지하거나 기준을 완화·재시도하지 않았다.

- [x] 중복 이름 저장 제거, public mutation/equality/codec 호환과 공통 모듈 검증.
- [x] 동일 모델의 수정 전·후 메모리 및 160B 대조 원문 보존.
- [x] 7입력 정확성 smoke·TSAN·양쪽 공유 엔진 검증.
- [ ] 안정된 호스트에서 기존 A/A·7입력 속도/CPU/RSS gate 통과.
- [x] 실제 파일 10만 개·양쪽 GUI/native의 SNS 100만 파일 RSS 추가 비교. [양쪽 후속 결과](BOTH_PLATFORM_FINISH_RESULTS.md).
- [x] 양쪽 후보 패키지 구성·서명/manifest 검증. 설치 교체는 성능 gate 뒤 진행.
- [ ] gate 통과 후 양쪽 패키지·설치 반영. 현재 Mac/Windows 설치본은 이전 GPUI 검증본을 유지한다.

[원문·소스·해시](validation/node-storage-2026-11-24/README.md) · [전체 남은 작업](GPUI_MIGRATION_TODO.md).

후속: [Quick Look/접근성 UI 패치](GPUI_PREVIEW_REENTRY_RESULTS.md)는 양쪽 설치했다. 설치 엔진은 SHA가 같은 기존 184B로 유지하며 168B 후보는 미채택이다. 승인된 VM 정지 중에도 다른 부하로 정식 host admission은 실패했다.
