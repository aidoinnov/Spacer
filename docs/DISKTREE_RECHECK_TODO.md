# disktree 재확인 후속 상태 — 2026-11-21

다섯 개선의 현재 구현·측정·미완료 항목은 [최종 TODO](SCAN_ALL_FIVE_TODO.md), 근거는 [결과 보고서](SCAN_ALL_FIVE_RESULTS.md)를 따른다.

- [x] bounded 재표본, worker metadata, node/path 저장, 검증된 bulk/census, scratch 재사용 반영.
- [x] 전체 테스트·TSAN·ARM/Intel CLI 및 정량 비교 수행.
- [ ] 전체 성능 채택 및 GUI/watch·배포 gate. A/A 편차와 tiny-folder p95가 남아 있다.

재확인 당시의 상세 제안 목록은 [이전 목록](validation/scan-all-five-2026-11-21/recheck-todo-before.md.gz)에 보존했다.

## 2026-11-24 최신 소스 재확인

[현재 측정과 한계](GPUI_REMAINING_RESULTS.md#최신-disktree-메모리-비교). 이전 속도 HOLD를 이번 메모리 측정으로 해제하지 않는다.

- [x] 원격 disktree HEAD와 보관 소스의 동일 커밋 확인.
- [x] 현재 Core를 새로 빌드해 10만/100만 파일, worker 1/4 대조 총 18회 측정. 파일/폴더/할당량 oracle·자체 fixture 정리 통과.
- [x] 컴파일된 노드 stride 확인: 우리 184바이트, disktree 88바이트. 100만 파일 RSS 중앙값 207.17MiB 대 113.94–114.44MiB.
- [ ] hot node·추가 metadata의 책임 분리, 경로/이름/ID 중복 비용을 분리 계측한 뒤 저장 어댑터 개선. native/SNS 필드, logical/allocated, 하드 링크와 불변 snapshot/watch 의미 보존.
- [ ] 후보의 node stride와 동일 100만 파일 RSS 감소, 작은 입력 비회귀 및 기존 7입력 성능/정확성 gate 확인 후 채택. 호스트 기준을 완화하거나 유리한 표본만 선택하지 않음.
- [ ] 안정된 호스트의 A/A·최신 disktree 처리량 재대결. 이번 공유 호스트의 메모리 실험은 속도 채택 증거가 아님.

## 2026-11-24 저장 개선 후보 후속

[공통 저장 개선 결과](NODE_STORAGE_RESULTS.md). 이전 184B/disktree 대조는 그 당시의 고정 기록이다.

- [x] name/path 중복 제거로 공통 노드 184→168B. 양쪽 동일 원본·동일 저장 동작 테스트 재사용.
- [x] public name/path 독립 변경, Unicode raw spelling·equality·JSON/SNS·전체 Int 부모 ID 호환 검증.
- [x] 168B/160B 실측 비교 후 추가 이득이 입증되지 않은 부모 표현 변경 제외. 모든 시도 보존.
- [x] Core 313개(3 skip), 양쪽 Domain 각11개, TSAN17개, 7입력 정확성56회 확인.
- [x] 실제 파일 10만 개·Mac/Windows GUI/native의 100만 SNS RSS 비교와 후보 패키지 준비. [양쪽 정량 결과](BOTH_PLATFORM_FINISH_RESULTS.md).
- [ ] 기존 정식 성능 gate·설치 채택. 호스트 환경 검사 실패로 A/A·7입력 미실행.
