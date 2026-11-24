# 다섯 개선 구현·채택 체크 — 2026-11-21

[최종 결과](SCAN_ALL_FIVE_RESULTS.md) · [V5 측정표](validation/scan-all-five-2026-11-21/v5/MEASUREMENTS.md). 구현 완료와 채택·배포 완료를 구분한다.

## 재검토에서 추가된 우선 작업

[수정 실행 결과](SCAN_REVIEW_FIX_RESULTS.md) · [재검토 근거](SCAN_ALL_FIVE_REVIEW.md) · [정석 수정 절차·회귀 테스트·완료 기준](SCAN_ALL_FIVE_FIX_TODO.md).

- [x] P1: sparse metadata fallback의 취소 검사 누락 수정. 취소가 stat 직전 검사에서 관찰되면 새 호출0회, 진행 중 호출과 구분한 worker drain 회귀 테스트.
- [x] P2: ENTRYCOUNT query를 별도 계측하고 재표본 비용을 tiny-folder 회귀와 분리 비교.
- [x] P2: compact 경로 표현이 달라도 공개 path가 같으면 Equatable 일치. trailing slash 경계 테스트.

- [x] 후속 GUI: native watch 삭제 이벤트의 root alias 누락 수정. 관련31개(신규3 포함)·TSAN7개·20만 파일 GUI·watch218회·ARM/Intel 검증. [최신 결과](SCAN_FINAL_GATE_RESULTS.md).

## 기존 구현·검증 기록

- [x] bounded sibling 재표본: 첫 후보 실패가 부모 전체를 영구 차단하지 않음.
- [x] worker에서 bounded metadata/fallback stat 완료, mount·오류·FD·취소 보존.
- [x] optional packing 및 파일 경로 공유/지연 생성. 공개 필드·기존 JSON/SNS·CoW 유지, 임시 migration setter 제거.
- [x] 단일 bulk collection + 독립 streaming namespace census. sparse 후보는 검증 후 사용, 일반 read/stream EOF 계약 유지.
- [x] pthread64KiB scratch take/return, 재진입 분리·thread-exit 해제.
- [x] Mac 최대4 작업은64 sibling frontier와 적합한 표본에만 적용.32-frontier 및 전부 tiny는2/4 설정 모두 inline임을 검증.
- [x] 최종 root309개(4skip), shared debug/release각19개 실패0. TSAN Mac27·공통19개 통과.
- [x] ARM/Intel scan/TXT/SNS·consumer API·source/evidence/플랫폼 경계 검사.
- [x] 전후21쌍 표준7입력·worker4입력×7변형·A/A·V4→V5 ablation 및 모든 raw/oracle/정리 조건 기록.
- [x] V1 실제10만/100만·최종 V5 실제10만 paired memory 비교. 최종 memory 첫 reserve 중단과 외부 backing 재시도 분리 보존.
- [x] 모든 후보/실패를 보존하고 현재 source와 최종 probe 일치·설치 앱 유지·실행 프로세스 재개 확인.
- [ ] A/A 수집 신뢰도 및 tinyfolders1000 p95 gate. 이전 V5/C3 비교6/7, 재검토 수정/V5 비교2/7 통과로 비교 대상을 구분함. 전체 채택 HOLD.
- [ ] 경로 소비가 많은 validation/filter/TXT/SNS의 CPU 개선. GUI/watch 기능·참고 시간 측정은 최신 결과에 기록했으며 paired 성능 개선으로 집계하지 않음.
- [ ] 최종 채택·배포 gate 통과. GUI/watch 기능 및 별도 Universal QA 서명·패키징 검증은 완료. 안정된 환경의 성능 판정과 기본 배포는 HOLD.
- [ ] 별도 후속: 거대한 한 폴더의 중간 선점, Windows native backend 실행 검증.
