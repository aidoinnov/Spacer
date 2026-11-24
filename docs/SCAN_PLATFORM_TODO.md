# 플랫폼 분리와 p95 후속 TODO — 2026-11-21

[설계·원인 관측](SCAN_PLATFORM_ARCHITECTURE.md). 목표는 플랫폼별 파일 조회만 adapter로 바꾸고 성능 기능을 공유하는 것이다. Windows 앱 전체 포트와 기존 원본의 동적 동등성은 별도 범위다.

- [x] 공통 worker·ticket·취소·permit을 독립 Swift package로 이동하고 macOS에서 실제 사용.
- [x] 결과 window의 용량·소비·중복 방지·재보충 loop를 공통화.
- [x] scalar 합산 batch·발행 정책 이동, per-entry inline 및 기존 entry layout 보존.
- [x] 폴더 단위 generic adapter 계약·다른 metadata 타입과128-bit identity fixture 검증.
- [x] Mac QoS·자원 한도·admission 수치를 Mac composition으로 격리. unknown-count admission은 명시적 policy 입력.
- [x] 독립 package 테스트와 macOS Core 전체 테스트, import/원본 근거 경계 검사.
- [x] 동일 binary A/A891회 +별도 warmup27회, rusage·process I/O 수집. 같은 코드도 gate 미달하는 조건 확인; 이전 HOLD 보존.
- [x] shared 경계 변경의 TSAN23개·release 통합135회·ARM/Intel CLI/SNS 검증 및 결과 기록. 최종 배포 gate와 구분.
- [ ] 완전한 off-CPU/OS stack 수집과 A/A 수집 신뢰도 조건을 사전 고정. 현재 counters만으로 원인을 확정하지 않음.
- [x] Windows Swift host에서 독립 package build/test 실행.132번 Windows10 x64에서 debug/release 각22개(기존19+실제 파일3) 통과. [실측 결과](WINDOWS_132_PHASE1_RESULTS.md). 검증 adapter는 Foundation 기반이며 production Win32 reader 검증은 아님.
- [ ] Windows reader의 filesystem별 검증 확장. Win32 batch/fallback·handle 수명·UTF-16·file ID·allocated·junction 제외와 native UI 구현은 [Windows v0.1](WINDOWS_APP_RESULTS.md)에서 완료. ReFS/네트워크/클라우드 등 폭넓은 실기기 인증은 남음.
- [ ] DiskNode/NodeTable·ScanOverview·filter/SNS의 dependency graph를 따로 정리해 공유 범위를 확장. 현재 전체 builder까지 이 package로 옮기지 않았음.
- [ ] Windows adapter의 실측 admission·IO/worker budget·cancellation/rename-watch 정량 검증.
- [ ] 신뢰 가능한 전체 회귀 gate를 통과한 뒤 GUI/watch·ARM/Intel·배포. 현재 기본 설치0.2.1 유지.


2026-11-21 C3 [품질 검토](SCAN_ENGINE_QUALITY.md): 종료/취소 전달 race와 실패 시 무제한 plan 탐색을 red/green으로 재현·수정했다. producer API 제한·scoped permit·nonblocking stop·termination 관측과 release/TSAN 검증을 추가했다. 위 C2 결과와 native Windows·최종 배포 미완료 상태는 구분한다.
