# 이벤트 갱신 큐 최적화 검증 — 2026-11-09

후속: 아래는 최초 큐 단계의 기록이다. 당시 남긴 B08.08은 [수명·취소 후속 검증](REFRESH_LIFECYCLE_VALIDATION.md)에서 검증 범위 완료했다. 이 문서의 성능/source/ZIP 수치는 최초 단계 그대로 보존한다.

대량 독립 경로의 반복 prefix 검색과 배열 앞 삭제를 줄였다. 작은 큐는 기존 배열을 사용하고, 17개부터 압축 경로 인덱스와 별도 FIFO 저장소를 사용한다. UI·스캔 결과·감시 정책은 바꾸지 않았다. B08.01–07을 완료하고 B08.08은 부분 검증으로 남겼다.

## 원본 근거와 Mac 선택

W09 `addRefilterRequest` **0x42e130**, `pickRefilter` **0x42c9e0**, ancestor **0x408260**에서 확인한 계약은 중복·조상 packing과 독립 요청 FIFO다. [보존 원문](validation/windows-optimization-functions/0x42e130.txt), [계약 manifest](engine-contracts.json), [30개 기법 목록](OPTIMIZATION_CHECKLIST.md)을 따른다. 원본은 TList 중첩 비교이며, radix index·COW·slot 재사용은 Mac 자료구조 선택이다. Windows 원본 실행 결과/타이밍 동등성을 새로 검증한 것이 아니다.

## 단일 책임 경계와 의미 보존

- [RefreshQueue](../Sources/SpaceSnifferCore/RefreshQueue.swift): 중복·조상 packing, FIFO, 배열/인덱스 전환, COW, compaction. ScanService의 기존 insert/pop/removeCovered 호출을 그대로 받는다.
- [RefreshPathIndex](../Sources/SpaceSnifferCore/RefreshPathIndex.swift): 압축 Character radix의 exact/prefix/descendant 조회·삭제만 담당한다. 순서·감시·scan 실행을 결정하지 않는다.
- ScanService는 감시 세대·debounce·scan 시작/취소·구독 수명을 계속 소유한다.

`/a/x`, `/b`, `/a`를 넣으면 `/b`, `/a`가 된다. 새 조상을 지워진 후손의 자리로 당기지 않는다. 원래 SnapshotTree.contains와 동일한 lexical 경계를 사용하며 경로를 정규화하거나 빈 component를 제거하지 않는다. 구분자, Windows drive/UNC, trailing separator를 원래 의미대로 처리한다. Swift Character 비교로 NFC/NFD 동등성을 유지한다. UTF-8 bytes와 FIFO를 oracle과 대조하므로 String 동등성만으로 원래 spelling 변경을 숨기지 않는다.

## 메모리 수명

FIFO는 이중 연결 slot 배열과 free list를 사용한다. 두 압축 인덱스는 재귀 ARC 트리 대신 flat slot arena를 사용하며 삭제 시 terminal·자식 dictionary·label을 비운다. 분기 시 내부 prefix는 별도 문자열로 복사해 삭제된 긴 terminal의 backing String을 붙잡지 않는다. 합쳐진 edge도 자체 문자열을 소유한다.

8개 이하가 되면 작은 배열로 돌아가 인덱스 전체를 놓는다. 큰 큐의 총 arena slot이 `max(128, liveCount * 12)`를 넘으면 살아 있는 FIFO만으로 재구성한다. 고정 길이 경로에서 tombstone이 누적되는 구조가 아니다. 이 값은 **slot 수 상한**이며 byte 수나 RSS 상한이 아니다. 메모리 크기는 실제 대기 경로 문자열 길이와 Swift dictionary/array 할당에도 비례한다. 대기 요청 수/경로 길이를 잘라서 이벤트를 누락시키는 전역 byte cap은 추가하지 않았다.

4천 경로 중 3,900개 제거, root 덮기, drain, 반복 removeAll에서 compaction과 idle indexSlots=0을 검사했다. OS allocator가 즉시 프로세스 RSS를 낮춘다는 주장은 하지 않는다. COW 복사본을 concurrent reader가 보유한 상태에서도 writer 변경이 분리되는지 TSAN으로 확인했다.

## 독립 oracle와 테스트

[LegacyRefreshQueue](../Tests/SpaceSnifferCoreTests/LegacyRefreshQueue.swift)는 직전 artifact 단계 소스의 이름/import만 바꾼 배열 구현이다. checker가 [보존 소스](validation/artifact-2026-11-09/source-archive/Sources/SpaceSnifferCore/RefreshQueue.swift)와 본문을 비교한다.

[RefreshIndexTests](../Tests/SpaceSnifferCoreTests/RefreshIndexTests.swift)는 31×31 lexical 경계 조합, seed `0x1a2b3c4d`의 20,000 연산을 매 단계 대조한다. root·빈 값·혼합 구분자·NFC/NFD·combining mark·emoji·CRLF·Prepend·regional indicator·NUL, index 직접 조회/삭제, 복사 격리, 긴 경로의 flat arena 해제도 검사한다.

최종 Swift ThreadSanitizer **88개**, 실패 0·경합 보고 0. 기존 81개에서 index 6개와 실제 FSEvents burst 1개를 추가했다. Python **6개** 통과. [TSAN 로그](validation/refresh-queue-2026-11-09/tsan.log), [Python 로그](validation/refresh-queue-2026-11-09/python-tests.log).

## 성능 측정

[probe](../scripts/bench/refresh-queue.swift), [driver](../scripts/bench/measure-refresh-queue.py), [100개 raw 표본](validation/refresh-queue-2026-11-09.json). `swiftc -O -whole-module-optimization`, 동일 바이너리에 독립 old/new queue를 컴파일했다. 각 조건 5쌍을 프로세스별 교차 순서로 **순차** 실행했다. 측정 중 build/test/다른 probe를 실행하지 않았다.

fixture 경로 준비는 duration에서 제외하고 프로세스 peak RSS에는 포함한다. 삽입·상태 변화·drain을 포함하므로 기존 audit의 **삽입만** 측정한 1.94초와 직접 비교하지 않는다. 작은 큐는 2천 번 반복한 합계다. 중복은 전체 4회 재삽입, ancestor는 각 부모 삽입, root는 전체 덮기, churn은 live 1천 개를 유지하며 4천 번 pop/insert한다. 모든 쌍의 FIFO checksum/pop 수가 같고 최종 indexSlots=0이다. 실제 디스크 스캔/UI 전체 속도 배율이 아니다.

| 조건 | 기존 중앙값 ms | 새 중앙값 ms | 기존/새 peak RSS 중앙값 MiB |
|---|---:|---:|---:|
| small-1 | 0.152 | 0.255 | 6.12 / 6.20 |
| small-4 | 6.519 | 6.575 | 6.17 / 6.41 |
| small-16 | 99.583 | 115.284 | 6.20 / 6.08 |
| independent-1000 | 292.841 | 12.658 | 6.34 / 7.12 |
| independent-2000 | 1002.710 | 25.446 | 6.45 / 8.09 |
| independent-4000 | 5930.888 | 44.989 | 6.50 / 9.61 |
| duplicates-1000 | 1286.758 | 17.794 | 6.14 / 7.27 |
| ancestors-1000 | 965.730 | 25.406 | 6.27 / 7.48 |
| root-1000 | 278.749 | 7.682 | 6.38 / 7.03 |
| churn-1000 | 2236.254 | 54.636 | 6.08 / 7.66 |

작은 큐의 추가 분기/COW 상태 비용도 표에 포함한다. 작은 입력의 빠른 실행을 보장하는 최적화가 아니며, 적용 이득은 대량 독립 경로에 집중된다. 추가 index 메모리가 필요하므로 메모리 절감 최적화로 표시하지 않는다.

## 실제 감시 및 앱 검증 범위

EngineTests의 실제 FSEvents 테스트는 서로 다른 32개 폴더에 파일을 쓰고 전체 재스캔의 logical/allocated 합계와 대조한다. 기존 hard link 분기 보존, 감시 off/stop/on 뒤 새 파일 반영, 마지막 구독 해제를 검사한다.

[별도 QA burst driver](../scripts/mcp/refresh_burst_smoke.py)는 실제 앱에서 48개 독립 폴더 변경 후 파일 49개/정확한 합계로 수렴하는지 확인한다. 감시 교체 후 파일 50개로 수렴하고, 독립 stable 파일이 남는지 확인한다. 다른 root로 전환한 뒤 cached_roots=1로 이전 root의 공유 캐시 해제를 관측한다. app_status 요청 지연은 아래 raw에 남긴다.

별도 QA 앱 MCP **106회**, 도구 20개·projection 재사용·admission·artifact·PNG 검사를 통과했다. 추가 실제 burst는 **25회** 요청으로 통과했다. app_status 15회 중앙값 **308.8ms**, 최대 **930.1ms**이며, bridge 왕복을 포함한 이번 관측값이다. 전후 latency 개선을 비교한 값은 아니다. [통합 raw](validation/refresh-queue-2026-11-09/mcp-results.json), [burst raw](validation/refresh-queue-2026-11-09/burst-results.json).

첫 burst 시도는 watch 전환 명령 응답을 감시 재연결 완료로 간주해 새 파일을 놓쳤다. [실패 로그](validation/refresh-queue-2026-11-09/burst-attempt1.log)를 보존하고, driver에서 `watch_active=false/true`를 각각 확인한 뒤 파일을 쓰도록 수정했다. 이 재실행은 엔진 변경 없이 통과했다.

Universal **arm64/x86_64**, ad-hoc 서명 검사와 packaged MCP 동일성 확인. [빌드](validation/refresh-queue-2026-11-09/build.log), [패키지 기록](validation/refresh-queue-2026-11-09/package.json). ZIP SHA-256: `e7b7caaf16677a7f765ed784cdee75e2c17e4650de5680ccf2a18907454a379e`. 버전 ZIP은 `dist/releases/refresh-queue-2026-11-09-e7b7caaf1667.zip`에 보존했다.

FSEvents는 root 범위로 병합할 수 있으므로 이 실제 burst가 반드시 17개 이상 큐/index 경로를 거쳤다고 주장하지 않는다. 실제 burst 중 active scan 취소·오래된 monitor callback의 결정적 주입·live queue retained bytes 직접 관측은 **B08.08 미완료**다. 일반 queued/running 취소 및 세대 격리 테스트의 통과를 해당 항목 전체 완료로 바꾸지 않는다. 장시간 수백만 이벤트·실제 Intel 하드웨어·전체 develop 볼륨 스캔도 미검증이다.

## 재현 및 보존

```sh
swift test --sanitize=thread
python3 -m unittest discover -s scripts/mcp -p 'test_*.py'
sed '/@testable import SpaceSnifferCore/d' Tests/SpaceSnifferCoreTests/LegacyRefreshQueue.swift > dist/refresh-queue-2026-11-09/LegacyRefreshQueue.swift
swiftc -O -whole-module-optimization Sources/SpaceSnifferCore/*.swift dist/refresh-queue-2026-11-09/LegacyRefreshQueue.swift scripts/bench/refresh-queue.swift -o dist/refresh-queue-2026-11-09/refresh-queue
python3 scripts/bench/measure-refresh-queue.py --probe dist/refresh-queue-2026-11-09/refresh-queue --output docs/validation/refresh-queue-2026-11-09.json
python3 scripts/check-refresh-validation.py --historical
python3 scripts/check-artifact-validation.py --historical
python3 scripts/check-scan-resource-validation.py --historical
```

측정은 build/test 종료 뒤 별도 실행한다. QA 앱은 별도 bundle ID로 실행하며 기존 사용자 창을 테스트 fixture로 대체하지 않는다. 과거 artifact/scan raw hash와 소스 archive는 수정하지 않았다. artifact checker에 명시적 historical 모드를 추가해 이전 source/ZIP을 검증하고 현재 변경을 과거 기록에 섞지 않는다.


메인 앱은 재시작 직전 idle·jobs=[]를 확인했다. 이전 프로세스 종료를 UI inventory에서 확인한 뒤 최종 Universal 앱을 열고 새 PID·idle·admission 설정을 read-only MCP로 확인했다. [재시작 전](validation/refresh-queue-2026-11-09/main-before.json), [재시작 후](validation/refresh-queue-2026-11-09/main-after.json). QA 앱은 종료했다.
