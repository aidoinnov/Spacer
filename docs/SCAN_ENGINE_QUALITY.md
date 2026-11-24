# 공통 스캔 엔진 품질 검토 — 2026-11-21

등급을 선언하는 대신 재현·수정·회귀 검증을 완료 조건으로 사용한다. shared C2를 검토해 실제 종료 순서와 작업 상한 문제2개를 재현했고 shared C3에서 수정했다. Windows 실제 실행과 신뢰 가능한 전체 성능 gate가 끝나지 않았으므로 전체 플랫폼·배포를 A++ 완료로 표시하지 않는다.

## 재현한 결함과 수정

| 항목 | 변경 전 재현 | 변경 후 계약 |
|---|---|---|
| 취소 결과 전달과 종료 | native reader가 모두 종료하면 `cancelQueued`의 결과 factory가 막혀 있어도 shutdown 호출자2개가 먼저 반환 | 취소 결과 전달 중인 수를 lock 아래 추적. ticket 완료 전에는 shutdown과 isTerminated가 종료를 알리지 않음 |
| 실패한 작업 제출 시 계획 탐색 | 결과 용량2인데 제출이 모두 실패하면 lazy plan10,000개를 모두 검사 | 보유 결과와 검사할 계획 수를 각각 제한. 기본 검사 상한2에서 실제 검사2개. Mac은 기존과 같은 명시적2/4개 budget 사용 |

수정 전 테스트2개가 **실제로 실패**한 로그와 같은 테스트의 통과 로그를 보존했다. 첫 테스트 코드의 async semaphore 컴파일 오류도 별도 기록했으며, 이를 결함 재현으로 세지 않는다. [계획·red/green 증거](validation/scan-quality-2026-11-21/README.md).

## 함께 강화한 API·수명 계약

- ticket은 소비자가 `wait`만 한다. 생성과 `finish`는 producer 모듈 내부로 제한했다. 일반 import의 읽기 코드는 컴파일되고 생성/완료 코드는 거부되는지 실제 compiler로 검증했다. 보안 sandbox나 binary ABI 경계를 주장하는 검사는 아니다.
- `DirectoryIOBudget.withPermit`은 stack scope의 `defer`로 Swift 오류가 발생해도 permit을 반환한다. per-entry 객체를 추가하지 않았다. 취소 시 body가 실행되지 않고, 정상 결과가 optional nil이어도 취소와 혼동하지 않는 테스트를 추가했다.
- `requestShutdown`은 nonblocking이며 worker에서도 호출할 수 있다. 이미 수락한 작업은 끝내고 새 작업은 거절한다. blocking `shutdown`은 coordinator에서만 호출한다. 자신의 operation/configuration/cancellation callback에서 자기 pool의 shutdown을 기다려서는 안 된다.
- `isTerminated`는 stop 요청·reader 종료·결과 전달 종료를 함께 확인한다. 기존 active/queued/live 관측값이0인 것만으로 drain 완료를 판단하지 않는다. 소비자가 보유한 output의 메모리 해제를 뜻하지도 않는다.
- 결과 생성과 client callback은 pool condition 밖에서 실행한다. 취소 결과의 참조도 condition을 잡은 상태에서 해제하지 않게 수명을 유지한다.
- window key는 builder가 구분하는 pending directory occurrence ID를 사용한다. 이미 소비한 계획을 provider가 다시 제시하지 않아야 한다. inode나 정규화된 표시 이름으로 다른 경로를 합치지 않는다. 중복 억제는 현재 outstanding 결과에 대한 것이며, 무한한 완료 이력을 저장하지 않는다.
- 계획 budget은 검사 개수의 상한이다. native call의 deadline이나 RSS 강제 상한이 아니다. batch의 record/name/byte 검증과 handle 정리는 OS adapter 책임이다.

## 책임 경계

공통 package는 queue/ticket, 취소, permit, window·발행·합산 정책만 소유한다. Mac의 native query, QoS, 임계값은 Mac composition에 남는다. worker는 tree를 변경하지 않는다. Core는 alias와 작은 adapter로 이 구현을 사용하며 중복 queue를 유지하지 않는다.

새 protocol은 폴더 batch에만 사용하고 metadata는 typed value로 전달한다. private producer 권한을 만들기 위해 파일별 객체·가상 dispatch를 추가하지 않았다. 다음 최적화는 이번 검토에 섞지 않았다: cap24인 queue를 대형 ring buffer로 바꾸기, domain model 전체 이동, 검증 없는 worker4 기본 적용.

## 검증과 남은 완료 조건

- shared18개 Debug·Release, Mac 프로젝트302개(환경 skip4) 실패0.
- shared TSAN18개: 취소 결과 전달 지연, 동시 shutdown2개, worker의 종료 요청, throw/취소/nil 결과, 검사 budget·중복을 포함한다.
- ordinary consumer3개 compiler 검사: wait 허용, 생성/완료 거부.
- Mac 연동 TSAN과 cross-architecture/CLI 결과는 [최종 검증 기록](validation/scan-quality-2026-11-21/verification.json)을 따른다. 최종 기록 전인 항목을 통과로 추정하지 않는다.

Windows reader·실제 Windows build/test, A/A 수집 신뢰도와 전체 입력 성능 gate, 최종 GUI/watch·패키징·배포는 별도 남아 있다. 이전 HOLD와 실패 표본을 지우거나 기준을 완화하지 않는다. 기존 설치0.2.1은 유지한다. [플랫폼 설계와 후속 범위](SCAN_PLATFORM_ARCHITECTURE.md), [남은 TODO](SCAN_PLATFORM_TODO.md).
