# 대규모 스캔 진행 정체 조사

2026-11-08. 실행 중인 기존 앱을 읽기 전용으로 관찰했다. 종료하거나 사용자 파일을 수정하지 않았다.

## 관찰

- 화면은 develop 168.95GB, 파일 2,176,602 / 폴더 310,819에서 여전히 **스캔 중**이었다. 전체 볼륨 용량은 약 499.9GB이며 시스템 사용량은 당시 약 459GB였다. 스캔 도중 파일 합계는 전체·사용 용량 어느 쪽과도 같다고 기대할 수 없다.
- 기존 프로세스 실행 시간 약 32분, CPU 약 92%, RSS 약 5GB였다. 실행 시간 전체가 해당 스캔 시간이라는 뜻은 아니다.
- 2초 sample에서 scanner worker의 160 sample 중 87이 Scanner 진행 갱신의 ArrayBuffer 확장·swift_arrayInitWithCopy 아래에 있었다. 별도 projection worker에서도 membership·weights 전체 계산이 보였다. 이는 그 짧은 샘플 구간의 관찰이며 전체 실행 시간의 정확한 비율은 아니다.
- 원본 파일 크기 delta 계약은 `TFileSystemNode::deltaSize` `0x405a00`로 이미 보관돼 있다. 기존 Mac 구현은 진행 스냅샷마다 전체 트리를 복사해 다시 합산했다.

## 수정

- 원본 deltaSize 계약대로 파일의 크기 기여분을 발견 시 조상에 전파한다. 최종·부분 결과를 다시 전체 합산하지 않는다.
- hot loop에서 파일명과 경로를 얻기 위한 반복 Foundation URL 생성을 제거한다. 파일 이름·경로·순회 대상은 유지한다.
- 가벼운 ScanProgress는 현재 경로, 발견 파일/폴더 수, 검사한 폴더/대기 폴더 수, 합계와 오류 수만 전달한다. 노드 배열을 보관하지 않는다.
- 무거운 중간 트리는 마지막 발행 이후 노드 수가 두 배 이상 늘었을 때 발행한다. 이는 Mac UI 발행 정책이며 Windows 엔진의 큐·주기와 같다는 주장이 아니다. 중간 트리의 누적 노드 발행량은 최종 N에 대해 2N 미만, 별도 최종 결과까지 포함하면 3N 미만이다. 따라서 시간 tick 횟수에 비례해 N 크기 배열을 반복 복사하지 않는다.
- heartbeat는 tree revision을 바꾸지 않는다. ScanStore는 같은 revision을 다시 accept/refilter하지 않는다. 세대와 heartbeat sequence로 늦은 상태를 차단한다.
- 거대한 단일 폴더에서도 256개 항목마다 진행 시점을 확인하고 취소를 검사한다. 전체 목록을 읽는 OS 호출 자체가 막히는 경우까지 이 주기가 보장되는 것은 아니다.
- UI에 현재 경로·대기 폴더·일부 결과 여부를 표시하고 시스템 사용량을 별도로 표시한다. 접근 오류가 있으면 성공처럼 단순 완료로 표시하지 않는다. 미래의 파일 수를 알지 못하므로 임의 완료율은 표시하지 않는다.

## 검증

ThreadSanitizer 34개 테스트 통과. 새 회귀 검사는 200만 번의 진행 후보에서도 발행 노드량이 선형임을 확인하고, 부분·최종 delta 합계 일치, 큰 단일 폴더 내부 취소 시 부분 합계 일관성을 검사한다.

`scripts/bench/main.swift`는 이전 발행 트리를 유지하는 구독자를 모사한 release scanner 벤치마크다. UI 렌더링·필터·실제 Windows 실행을 벤치마크하는 것은 아니다.

```sh
swiftc -O -whole-module-optimization Sources/SpaceSnifferCore/*.swift scripts/bench/main.swift -o /tmp/macspacesniffer-scan-benchmark
/tmp/macspacesniffer-scan-benchmark /absolute/folder
```

저장소 .build 스캔: 파일 3,055 / 폴더 1,134 / 노드 4,189, 0.485초, 중간 트리 발행 2회·발행 노드량 4,190, 오류 0. [원시 결과](validation/scan-progress-benchmark.json). 이 작은 표본으로 전체 볼륨의 개선 배율을 주장하지 않는다.

추가 sample에서 Foundation 디렉터리 열거의 항목별 URL·속성 조회 비용도 관찰해 `opendir/readdir`로 대체했다. 열기 재시도와 제외 규칙을 유지한다. 전체 develop 볼륨의 최종 합계 검증은 미완료다. 추가 전체 볼륨 벤치마크는 시스템 부하를 줄이기 위해 중단했으며, 종료 성능 수치로 사용하지 않는다.

관찰 후반 시스템 swap 사용량은 28GB였다. 기존 앱만의 사용량이라고 단정하지 않는다. 기존 앱은 이후 실행 목록에서 사라졌으며, 이 조사에서 main 앱에 종료 명령을 보낸 것은 아니다. 종료 원인은 확인하지 못했다.
