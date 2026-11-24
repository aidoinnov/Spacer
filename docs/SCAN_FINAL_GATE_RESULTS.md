# 최종 채택 검증 — 2026-11-21

후속: [11월23일 성능 재개·환경 gate 기록](SCAN_PERFORMANCE_2026_11_23.md).

**성능 채택·배포는 HOLD다.** 환경 진입 검사에서 CPU·load·swap·memory pressure 조건을 충족하지 못했다. 후속 GUI 검증에서 발견한 삭제 이벤트 누락을 수정했고 관련 테스트·TSAN·GUI/watch 검증을 완료했다. 기본 설치는 유지한다.

[이전 세 결함 수정](SCAN_REVIEW_FIX_RESULTS.md) · [이번 검증 자료](validation/scan-final-gate-2026-11-21/) · [환경 진입 스크립트](../scripts/bench/scan-review/host_preflight.py)

## 환경 진입 조건

실행 전에 보수적인 수집 조건을 고정했다.5회 연속 CPU idle≥70%, load1≤논리 코어 수, swap-out 증가0, memory pressure level1, fixture reserve2GiB다. 이 조건은 A/A 실행을 허용하는 조건이며 성능 통과를 보장하지 않는다. 이후에도 기존 p50/p95·paired CI·CPU·RSS 기준을 그대로 적용한다. 다른 프로젝트나 사용자 프로세스를 임의 종료하지 않는다.

첫5회는10코어에서 CPU idle 전부0%, load1 약58.8…77.5, pressure level 전부2, swap-out 약7.1GiB 증가였다. [원자료](validation/scan-final-gate-2026-11-21/host-initial.json). 기존 `/` 스캔 실행본의 physical footprint는 약9.3GiB였다. 이는 오래 실행된 이전 버전의 관측이며 새 후보의 메모리 결과가 아니다. [관측값](validation/scan-final-gate-2026-11-21/oldapp-resources-initial.json).

이 환경에서 새 A/A와 표준 성능 비교를 실행해 통과 여부를 만들지 않았다. 기존 실패를 지우지 않고 안정된 조건의 재측정을 남긴다.

## GUI에서 추가로 발견한 삭제 이벤트 누락

초기 Universal QA 앱은 실제 스캔·필터·탐색·SNS/TXT·캡처·admission 통합을 통과했다. 이어서48개 branch에서 write/rename/unlink를 반복하자 실제32개/1,536byte가 UI에는48개/1,944byte로 남았고, 모든 worker가 종료된 뒤에도 수렴하지 않았다. 같은 입력을 GUI 없는 `ScanService`에 적용해 두 번째 반복에서 똑같이 실패했다. [수정 전 엔진 재현](validation/scan-final-gate-2026-11-21/service-watch-result.json).

원인은 Foundation의 파일 존재 여부에 따른 경로 alias 변환이었다. `/private/tmp/.../removed.bin`은 파일이 있으면 `/tmp/.../removed.bin`으로 변환됐지만, unlink 뒤에는 `/private/tmp/.../removed.bin`으로 남았다. 캐시 루트의 `/tmp/...` 경계 검사에서 삭제 이벤트만 제외됐다. [직접 재현](validation/scan-final-gate-2026-11-21/path-alias-result.txt).

`DirectoryMonitor`는 스트림이 생성 시 보관한 native root를 `FSEventStreamCopyPathsBeingWatched`로 읽어 캐시 루트 spelling으로 대응시킨다. `DirectoryWatchPath`는 순수 문자열 경계 변환만 한다. 삭제된 항목의 filesystem 조회나 공통 queue/actor의 OS 의존을 추가하지 않았다. 이벤트 항목마다 `realpath`를 실행하지 않으며, 공유 가변 mapping도 없다. 필요한 루트 정보가 없으면 루트 재검사를 요청한다. 최초 수정안의 callback 캡처 문제로 실패한 빌드 로그도 보존했다.

수정 후 동일 엔진 재현은5회 반복 모두 파일 수·용량 일치로 수렴했다. [수정 후 결과](validation/scan-final-gate-2026-11-21/service-watch-after.json). 새 테스트3개와 관련31개 선택 테스트를 통과했다.31개에는 새3개가 포함된다. 기존 전체324개 통과를 이번 변경의 전체 재실행으로 집계하지 않는다.

## 수정 후 GUI·TSAN·호환성 결과

| 검증 | 결과 | 범위 |
|---|---|---|
| 관련 선택 테스트 |31개 실패0 | 신규3개 포함; 전체327개 재실행을 의미하지 않음 |
| TSAN |7개 실패0 | 실제 native FSEvents·루트 mapping·monitor 세대/취소 포함 |
| GUI 상세 |200,000파일·201폴더 일치 | logical10,100,000B·allocated819,200,000B |
| 개요·취소 |20회 관측·취소 및 재시작 통과 | 현재 스캔 개요, 새 session·빈 root 교체 |
| native watch |218회·24,416작업 통과 |60.8초, 매회 file/byte oracle; 장시간/강제 overflow 보장 아님 |
| ARM/Intel CLI |9,600파일 oracle·TXT byte·SNS 상호 로드 통과 | 새 source의 두 release binary |
| 최종 시각 확인 |현재 root200개 타일·geometry/transition 종료 |PNG 직접 확인, 이전 root가 섞이지 않음 |

20회 개요 native draw 관측 상한은 p50 127.3ms·p95 248.6ms,20만 파일 상세 재검사 settle은662.8ms였다. MCP transport/polling을 포함하는 같은 실행 앱의 warm 관측이다. 부하가 있는 환경의 기능 검증 수치이며 paired speedup·배포용 latency 통과로 쓰지 않는다. 개요/상세 캡처에는0.5초 애니메이션 도중 프레임이 포함된다. 최종 시각 확인은 transition 종료 후 별도 캡처로 했다.

TSAN의 SwiftPM discovery helper는 테스트 실행 전 sanitizer dylib 로딩 정책으로 종료됐다. 기존 저장소의 `run-tsan-host.sh`로 동일 계측 XCTest bundle을 disposable ad-hoc host에서 실행해7개 통과했다. 시스템/Xcode/security는 변경하지 않았다. 최초 loader 실패 로그와 실제7개 실행 로그를 모두 보존한다. 추가 정적 캡처 스크립트의 최초 응답 형식 오류도 보존하고, 수정된 스크립트의 재실행·PNG를 별도로 기록했다.

[수치·SHA·판정](validation/scan-final-gate-2026-11-21/summary.json) · [수정 후 candidate](validation/scan-final-gate-2026-11-21/candidate-after.json) · [GUI 증거](validation/scan-final-gate-2026-11-21/after/gui/gui-delivery.json) · [감시 반복](validation/scan-final-gate-2026-11-21/after/watch/report.json) · [정적 PNG](validation/scan-final-gate-2026-11-21/after/visual-retry/settled-current.png)

## 대규모 입력의 초기 중단과 남은 조건

처음20만 파일 GUI 검증은150개 branch 준비 중 free space가2GiB 이하로 내려가 중단됐다. 개요 draw 표본은0개이며 이를 GUI 통과로 집계하지 않는다. [중단 로그](validation/scan-final-gate-2026-11-21/gui-delivery.log) · [정리 결과](validation/scan-final-gate-2026-11-21/gui-setup-reserve-abort.json). 전용 fixture를 삭제하고 이전 검증의 root/TSAN scratch 약610MiB도 정리했다. 사용자 파일과 기본 설치 앱은 건드리지 않았다.

- [x] 환경 진입 조건·측정 실패 원자료 기록.
- [x] native watch 삭제 누락 red→green, 새3개·관련31개 통과.
- [x] 수정 후 TSAN7개 통과. SwiftPM discovery 실패와 실제 실행을 구분.
- [x] 수정 후 GUI/watch 재검증,20만 파일 개요·취소·상세·root 교체 및 steady-state PNG 확인.
- [ ] 안정된 환경에서 동일 binary A/A와 표준7입력 성능 gate.
- [ ] 채택 조건 통과 후 기본 설치·배포.

검증 작업을 마친 뒤 환경을 다시5회 확인했지만 CPU idle0.18…5.27%, load1 약18.1…22.0, memory pressure level2로 진입 조건을 재차 충족하지 못했다. [최종 환경 원자료](validation/scan-final-gate-2026-11-21/host-final.json). 새 A/A·표준7입력 성능 판정은 실행하지 않았다. 안정된 수집 조건과 그 gate를 통과한 뒤 기본 배포를 진행해야 한다.
