# 메모리 사용 조사와 수정

2026-11-08. 조사 시작 시 실행 중인 MacSpaceSniffer 프로세스가 없었고 시스템 swap은 약 21GiB였다. 시스템 swap 전체를 이 앱의 현재 사용량이라고 설명하지 않는다. 이전 턴에서 관찰한 앱 RSS 약 5GB와 이번 통제 벤치마크는 다른 측정이다.

## 원인과 변경

- NavigationState는 선택·방문 경로 몇 개를 위해 모든 노드의 부모/경로 사전을 만들었다. 이제 추적 경로와 그 조상만 찾는다.
- TagPolicy는 전체 이전 DiskNode 사전과 현재 경로 집합을 만들었다. 이제 살아 있는 추적 경로는 바로 반환하고, 사라진 경로의 식별자와 일치하는 후보만 보관한다. 기존 hard-link 별칭을 rename으로 오인하지 않는 계약은 유지한다.
- SnapshotTree는 모든 DiskNode를 dictionary에 넣고 또 경로별 children dictionary를 만든 뒤 새 배열을 구성했다. 이제 두 트리를 직접 순회하면서 ID/children/합계를 새로 구성한다. 기존 값은 변경하지 않는다.
- ScanService는 완료된 scan task와 이전 baseline을 해제한다. LatestWorker도 완료한 operation/completion payload를 동기 함수 범위에서 해제해 idle async iterator가 큰 입력을 붙잡지 않도록 한다.
- NodeTable은 1024개 노드 단위의 Swift copy-on-write 저장이다. 중간 snapshot은 이전 페이지를 공유하고 수정한 페이지만 복사한다. 페이지 크기는 Mac 저장 구현 선택이며 원본 메모리 배치라는 주장이 아니다. 노드 값·순서·ID·snapshot 격리·flat Codable 배열·SNS 바이트 형식은 유지한다.
- 필터 없는 기본 화면은 불필요한 inherited-tag/hidden 작업 배열을 만들지 않는다.

원본 동작 근거는 기존 계약표의 deltaSize·제거/rename·공유 루트 수명이다. 위 저장 자료구조는 macOS/Swift 구현이며 Windows 자료구조를 그대로 복제했다고 주장하지 않는다.

## 동일 입력 비교

합성 파일 250,000개, 같은 이름·크기·계층, 같은 release 최적화와 같은 benchmark program을 수정 전후 코어에 연결했다. 사용자 파일 I/O가 없는 metadata 처리 실험이다. `/usr/bin/time -l`의 maximum resident set size를 MiB(1,048,576 bytes)로 환산했다. 양쪽 checksum도 일치한다.

| 작업 | 수정 전 최대 RSS | 수정 후 최대 RSS | 감소 |
|---|---:|---:|---:|
| projection | 258.19 MiB | 76.94 MiB | 70.2% |
| snapshot | 113.44 MiB | 71.16 MiB | 37.3% |
| merge | 352.0 MiB | 127.98 MiB | 63.6% |

[구조화된 수치](validation/memory-comparison.json), [벤치마크 코드](../scripts/bench/memory.swift). 수정 전 소스는 [보관본](validation/memory-baseline-core.tar.gz), [해시](validation/memory-baseline-sha256.json)로 고정했다. 임시 source tree에 풀어 동일 benchmark를 연결하면 재현할 수 있다.

```sh
swiftc -O -whole-module-optimization Sources/SpaceSnifferCore/*.swift scripts/bench/memory.swift -o /tmp/memory-probe
/usr/bin/time -l /tmp/memory-probe 250000 projection
/usr/bin/time -l /tmp/memory-probe 250000 snapshot
/usr/bin/time -l /tmp/memory-probe 250000 merge
```

숫자는 각 독립 프로세스의 입력 생성부터 종료까지 최대 RSS다. 실제 수백만 파일 전체 디스크 스캔에서 같은 감소율을 보장하는 수치가 아니다.

## 실제 앱 확인

250,000개 파일 / 101개 폴더의 합성 SNS를 새 Universal 앱의 별도 QA 복사본에서 열었다. 트리맵·파일 수와 용량 표시·폴더 확대·⌘↑ 부모 이동을 확인했다. [화면](validation/memory-app-250k.png).

0.5초 간격 40초 RSS 관측에서 최대 206.97MiB였다. 이는 관측 최대치이며 sample 사이의 순간 peak를 보장하지 않는다. 실제 앱 데이터는 offline SNS로, filesystem scan 작업과 FSEvents 변경 폭주를 포함한 최대 메모리는 아니다. [관측값](validation/memory-app-250k.json). 합성 snapshot 생성 코드는 [여기](../scripts/bench/make-memory-snapshot.swift)에 있다.

## 검증과 남은 범위

- ThreadSanitizer 39개 테스트 통과, 데이터 경합 보고 없음.
- 페이지 경계 mutation·append 후 이전 snapshot 불변, 동시 reader/writer 격리, flat JSON 배열 호환을 추가 검사했다.
- idle worker의 operation capture 해제와 새 하위 분기 병합 후 기존 형제 보존을 추가 검사했다.
- 기존 필터·태그·hard-link rename·SNS golden bytes·트리맵·공유 캐시·FSEvents 검사를 유지한다.
- arm64/x86_64 Universal build, ad-hoc signature, 양쪽 CLI SNS/TXT 검증 통과.
- 전체 develop 볼륨 최종 scan의 실제 최대 메모리와 장시간 반복 변경은 아직 별도 검증 전이다. 메모리와 시간 비용이 0이 되거나 무한 파일 수에 고정 메모리로 동작한다고 주장하지 않는다.
