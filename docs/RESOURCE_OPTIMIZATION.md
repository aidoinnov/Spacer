# 추가 속도·리소스 최적화

2026-11-08. 직전 메모리 수정 빌드(39 tests)를 기준으로 비교했다. 원본 기능을 바꾸는 대신 계산과 데이터 갱신 비용을 줄였다.

## 변경

- 파일마다 실행하던 `isEmpty` 문자열 정리와 크기/기간 조건 dictionary 순회를 없앴다. 파싱 때 값을 고정하고 조건은 연속 배열로 평가한다. 첫 경계값 우선·포함 경계·단위 규칙은 유지한다.
- 단순 printable ASCII literal 및 suffix 마스크는 UTF8 비교를 사용한다. 비ASCII·제어문자·복잡한 wildcard는 기존 ICU regex를 사용한다. 예를 들어 Unicode case folding과 마지막 줄바꿈 anchor 동작을 새로 추정하지 않는다.
- 폴더 조건은 각 파일에서 조상을 다시 순회하는 대신 폴더당 한 번 계산해 상속한다. tag 4bits·hidden·folder positive/negative 상태를 1byte에 저장한다. 사용하지 않는 조건의 작업 배열은 만들지 않는다.
- navigation/tag 경로를 모두 찾으면 나머지 파일 검색을 중단한다. snapshot 경로 조회도 계층을 따라가며 관계없는 전체 파일을 검색하지 않는다.
- 변경 범위의 topology가 같으면 원본 `deltaSize` 계약처럼 노드 ID/children을 유지하고 변경 값과 조상 합계만 수정한다. 기존 snapshot과 건드리지 않은 페이지는 유지된다. 추가·삭제·이름 변경 등 구조가 다르면 기존 재인덱싱 경로를 사용한다.
- 재검사 경과 시간이 이전 검사 이후의 대기 시간까지 포함하던 표시를 고쳤다. 변경 범위 검사의 시작 시점부터 측정한다.

동작 근거는 기존 [계약표](engine-contracts.json)의 필터 판정·folder ancestor·tag OR·`deltaSize`(`0x405a00`, `0x4667a0`)다. Swift의 packed context·ASCII 단축 경로·page update는 구현 최적화다. Windows와의 동적 전체 동등성을 새로 증명했다고 주장하지 않는다.

## 전후 비교

합성 파일 250,000개. 같은 입력·같은 release 최적화로 3회씩 before/after를 교차 실행했다. 아래 시간은 해당 **metadata 계산 구간의 중앙값**, RSS는 각 프로세스의 입력 생성부터 종료까지 3회 중 최대다. 최종 측정은 빌드와 다른 벤치마크가 끝난 뒤 순차 실행했다. OS background load·cache·scheduling 영향은 통제하지 않았으며 초기 측정과 수치가 달라질 수 있다.

| 작업 | 수정 전 | 수정 후 | 관측 배율 | 최대 RSS 전후 |
|---|---:|---:|---:|---:|
| 파일명 + 크기 조건 | 656.894ms | 184.124ms | 3.57배 | 92.50 → 81.09MiB |
| 폴더 조상 + 파일명 | 1833.306ms | 131.997ms | 13.89배 | 105.25 → 81.33MiB |
| 태그 + 숨김 제외 + 파일명 | 1419.049ms | 166.618ms | 8.52배 | 89.17 → 81.28MiB |
| 기본 화면 projection | 81.522ms | 28.215ms | 2.89배 | 77.89 → 77.88MiB |
| 구조가 같은 파일 하나 갱신 | 256.987ms | 0.596ms | 431.24배 | 137.16 → 70.38MiB |

[필터 raw 결과](validation/resource-filter-comparison.json), [트리 raw 결과](validation/resource-tree-comparison.json). 양쪽 checksum을 검사했으며, 테스트에서는 파일별 결과도 독립 판정과 대조했다.

이 표는 디스크 열거·권한 재시도·FSEvents 지연·UI paint를 포함한 전체 scan 시간의 개선 배율이 아니다. 특히 구조가 같은 파일 갱신은 전체 재구성을 제거한 경우이며, 파일 추가·삭제의 일반 갱신이 같은 시간에 끝난다는 뜻이 아니다.

## 재현

직전 코어를 [보관](validation/resource-baseline-core.tar.gz)하고 [SHA-256](validation/resource-baseline-sha256.json)으로 고정했다. 두 source tree에 같은 [필터 probe](../scripts/bench/filter.swift), [tree probe](../scripts/bench/memory.swift)를 연결한다.

```sh
swiftc -O -whole-module-optimization Sources/SpaceSnifferCore/*.swift scripts/bench/filter.swift -o /tmp/filter-after
swiftc -O -whole-module-optimization Sources/SpaceSnifferCore/*.swift scripts/bench/memory.swift -o /tmp/tree-after
# baseline archive를 별도 디렉터리에 풀어 같은 명령으로 filter-before/tree-before 생성
python3 scripts/bench/compare-resource.py --before-filter /tmp/filter-before --after-filter /tmp/filter-after --before-tree /tmp/tree-before --after-tree /tmp/tree-after
```

## 기능 검증

ThreadSanitizer 44개 통과. 추가 검사는 다음을 포함한다.

- ASCII/Unicode/제어문자·복잡한 wildcard를 ICU oracle과 대조.
- packed 조상 context를 파일별 독립 tag/folder 판정과 비교.
- same-topology의 양수/음수 delta, 기존 ID/형제/원본 snapshot 보존.
- 구조 변경 시 재인덱싱 fallback과 정확한 경로 경계, Windows root lookup.
- 재검사 시작 시각 보존.

최종 코드로 arm64/x86_64 Universal 빌드와 CLI SNS/TXT를 확인했다. 별도 QA 앱에서도 `*.bin` 필터 상태에서 파일을 1MB→4MB로 변경해 FSEvents 뒤 표시 합계 4MB→7MB, 전체 6MB→9MB를 확인했다([화면](validation/resource-live-update.png)). 이 화면은 경과 시간 표시 수정 전 수집했고 시간 표시의 새 기준은 단위 검사로 확인했다.

전체 develop volume의 장시간 scan/변경 폭주에서 최종 최대 메모리와 총 소요 시간은 별도 검증 범위로 남는다. navigation-only weight 재사용과 변경 event queue의 대량 prefix packing은 추가 최적화 후보다.


후속 후보를 다시 조사하고 합성 비용을 측정한 결과는 [추가 최적화 후보 조사](OPTIMIZATION_AUDIT.md)에 정리했습니다. 이 후속 조사는 현재 앱 수정 전의 audit이며 위 전후 개선표와 구별합니다.
