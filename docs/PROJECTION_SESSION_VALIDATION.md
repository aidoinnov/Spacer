# ProjectionSession 구현·검증 — 2026-11-09

이번 범위는 A00의 최소 책임 추출, B01의 핵심 same-input 탐색 재사용, B02의 동일 값/복합 요청 축소다. 전체 TODO·모듈 설계·Windows 동등성 완료가 아니다.

## 바뀐 책임과 동작

- [LatestWorker](../Sources/SpaceSnifferCore/LatestWorker.swift)는 latest-only 실행·취소·shutdown만 맡는다. 필터 계산은 [FilterProjection](../Sources/SpaceSnifferCore/FilterProjection.swift)으로 옮겼으며 기존 전체 평가 생성자를 reference로 유지했다.
- [ProjectionSession](../Sources/SpaceSnifferCore/ProjectionSession.swift)은 창별 cache·요청 세대·worker를 소유한다. 완료 승인과 cache commit은 MainActor, membership/weights/navigation 계산은 worker다. worker는 캡처한 immutable 값만 읽으며 UI를 수정하지 않는다.
- ProjectionSource는 snapshot을 읽기 전용으로 보관하고 새 생성마다 외부에서 지정할 수 없는 identity를 갖는다. 탐색은 source를 복사해 identity를 유지하고 새 snapshot·offline tag 변경은 새 source를 만든다. 공개 projection UUID와 내부 identity를 분리했다.
- key는 source identity + 실제 적용 filter 문자열 + mode + hidden이다. cache는 한 세트의 leaf membership와 weights만 유지한다. 시간 조건은 cache를 쓰지 않는다. 유효하지 않은 filter는 기존 accepted filter로 fallback하며 오류를 유지한다.
- 새 source/설정, reset/종료·root/load 전환, 늦은 worker 결과를 검사한다. 0바이트 파일의 selection은 membership으로 판단한다. navigation/history·정렬 알고리즘 자체는 기존 경로다.
- [ScanStore](../Sources/MacSpaceSniffer/ScanStore.swift)는 요청 구성과 결과 반영을 맡는다. 동일 mode/hidden setter는 계산 요청을 생략한다. updateView는 복합 intent의 projection 요청만 한 번으로 묶으며 UI 전체의 원자성/롤백을 제공하지 않는다.
- [ScanService](../Sources/SpaceSnifferCore/ScanService.swift)는 같은 underlying tag mask·실제 지워질 tag가 없는 clear의 revision/broadcast를 생략한다. UI/MCP에서 같은 색을 다시 누르면 해제되는 toggle는 유지한다. 실제 tag 변화의 paint-only 경로는 아직 없다.

원본 근거는 W02 `setNewFocus(0x428bb0)`와 W06 `setTag(0x408300)`다. Swift source identity/cache/MainActor 경계는 플랫폼 설계로 분류했다. [contract](engine-contracts.json)와 [30개 체크리스트](OPTIMIZATION_CHECKLIST.md)를 새 소스에 맞춰 재검토했다.

## 비용 비교

[원시 표본·source/fixture script/compiler/OS/probe hash](validation/projection-session-2026-11-09.json). 25만 파일 metadata fixture, 초기 평가 1회 뒤 서로 다른 폴더로 10회 이동. release `swiftc -O`, 5쌍을 순차 교차 실행했다. 두 경로 모두 LatestWorker와 MainActor completion을 사용한다. full 경로는 기존 전체 평가 생성자, session 경로는 실제 새 production 구현이다.

| 지표 | 전체 평가 | 새 session |
|---|---:|---:|
| 탐색 10회 중앙값 | 766.27 ms | 34.06 ms |
| 초기 평가 중앙값, 별도 | 115.38 ms | 84.90 ms |
| process peak RSS 중앙값, fixture 포함 | 80.42 MiB | 72.81 MiB |

탐색 표본 범위는 full 662.23~869.64ms, session 27.10~41.67ms다. 새 경로는 10회 모두 재사용하며 checksum이 같다. 초기 평가 분포는 겹치므로 초기 계산 가속을 주장하지 않는다. 빌드와 겹쳤던 중간 실행은 최종 결과에서 제외하고 빌드 종료 후 다시 실행했다.

RSS는 각 process의 peak이며 cache의 retained bytes·실제 전체 앱 사용량·최대 메모리 상한을 뜻하지 않는다. 디스크 I/O, geometry/paint, 사용자 전체 develop, 장시간 반복 변경과 UI p95는 포함하지 않았다. UI 전체가 이 배율만큼 빨라졌다고 해석하지 않는다.

재현:

```sh
swiftc -O -parse-as-library Sources/SpaceSnifferCore/*.swift scripts/bench/projection-session.swift -o /tmp/sniffer-projection-session
python3 scripts/bench/measure-projection-session.py --probe /tmp/sniffer-projection-session --output /tmp/sniffer-projection-result.json
```

## 결과 동등성·수명·실제 앱 확인

- 수정 전 Swift 51개 TSAN 통과: [로그](validation/projection-2026-11-09/baseline-tsan.log).
- 수정 후 Swift **59개 TSAN 통과**: [로그](validation/projection-2026-11-09/final-tsan.log). 새 7개 session 회귀는 filter/mode/hidden 조합·navigation/full oracle, 0바이트 selection, 같은 크기/경로의 새 source·tag, temporal fallback·parse 오류, reset/shutdown stale publish, rename/삭제 복구를 다룬다. 추가 1개는 same-tag/empty-clear revision 계약이다. 기존 COW/동시 reader/worker payload 검사도 유지했다.
- Python bridge **6개 통과**: [로그](validation/projection-2026-11-09/python-tests.log).
- 별도 QA 앱 `local.macspacesniffer.projectionqa1109` 실제 STDIO **95요청**: [결과](validation/projection-2026-11-09/mcp-results.json), [캡처](validation/projection-2026-11-09/mcp-capture.png). full scan 합계 3,145,728 bytes/2파일, 탐색/태그 toggle, pagination/stale revision, SNS/TXT job, existing-output 거부, 실제 PNG 확인.
- 실제 앱의 탐색 3회에서 filter.projection 시작은 **2→5**, filter.membership 시작은 **2→2**였다. root/filter/mode 복합 변경은 각각 **5→6 / 2→3**, 동일 mode/hidden 설정은 **6→6 / 3→3**이었다. 이 카운터는 시작 수이고 완료/CPU 시간/동시 작업 수는 아니다.
- Universal arm64/x86_64 build 및 strict signature 검증: [빌드 로그](validation/projection-2026-11-09/universal-build.log), [packaged CLI/SNS→TXT 바이트 비교·hash](validation/projection-2026-11-09/package-cli-check.json). 실제 실행 QA는 Apple Silicon이며 Intel 하드웨어 검증은 아니다.

기존 smoke의 scoped rescan/stop은 명령 접수 경로 확인에 한정한다. 새 cycle 완료와 실행 중 취소를 이 smoke만으로 증명하지 않는다. 사용자 메인 앱을 재시작하지 않았으며 별도 QA 앱을 사용했다. `dist/Mac Space Sniffer.app`와 ZIP은 새 코드로 갱신했다.

## 남은 일

B01.06 history path lookup, 실제 앱 탐색 지연의 충분한 before/after 표본과 장시간 memory lifetime은 남아 있다. B02의 tag 의존성별 paint-only 경로·완전한 change matrix도 남아 있다. E01 node/page/scratch pool과 E02 bounded I/O executor/admission은 아직 평가·도입하지 않았다. 나머지 B03~B08 및 16개 목표 책임 전체 추출도 계속 TODO에서 추적한다.
