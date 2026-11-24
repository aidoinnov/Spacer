# SNS 읽기 임시 메모리 제한

2026-11-09. Foundation UTF16/Base64 변환의 임시 객체를 1,024개 record마다 autoreleasepool에서 정리한다. 이 batch 크기는 Mac 메모리 관리 선택이며 Windows 상수로 주장하지 않는다. 모델·stack·top-level roots는 pool 밖에서 소유한다. 이미 완성한 root의 검증과 malformed/encoding 예외를 그대로 유지한다.

[측정 결과](validation/r-backlog-2026-11-09/reader-pool-memory/report.json)는 같은 25만 파일 Unicode/긴 경로 SNS를 다섯 번 교차 fresh process에서 읽었다. 변경 전 reader와 측정 당시 Core source/probe를 함께 보존했다. 파일은 mappedIfSafe로 열었고, **decode 직후** getrusage RSS high-water와 Mach 현재 physical footprint를 기록했다. 이후 전체 canonical SNS 필드 checksum을 비교했으며 checksum 출력 단계는 decoder timer/RSS 표본에 포함하지 않았다. FNV1a 비교는 실행 중 의미 회귀 탐지이고 암호학적 동등성 증명이 아니다. 입력·소스·probe에는 SHA256을 기록했다.

| 중앙값 | 이전 reader | batch pool |
|---|---:|---:|
| decode | 0.909674초 | 0.804128초 |
| decoder max RSS | 232,030,208B | 210,649,088B |
| decode 직후 footprint | 200,311,504B | 178,586,344B |

모든 쌍에서 node 수·canonical 필드 checksum이 같았다. shared host의 이 fixture 관측이며 전체 볼륨 성능·메모리 상한·Windows runtime 결과가 아니다. 두 reader 모두 전체 Data mapping과 전체 NodeTable을 보유한다. 따라서 이 변경을 완전한 streaming reader나 path 압축이라고 부르지 않는다. 실제709만 노드의 유지 모델 비용은 여전히 남는다.

측정 뒤 별도로 WindowsLegacyText 재사용과 원본 drive capacity wire 수정이 들어갔다. 측정 archive/hash를 현재 소스 것으로 바꾸지 않는다. v4 폴더 fixture에는 해당 코드페이지/drive 분기가 없고 pool body는 동일하지만, 이것을 수정 후 전체 앱의 재측정이라고 표현하지 않는다. 원본 drive/folder 합계 해석의 한계는 [별도 조사](SNS_VOLUME_AGGREGATE_FINDINGS.md)를 따른다.

재현은 `scripts/bench/measure-reader-pool-memory.py`와 보존된 Swift probe/source를 사용하며 새 output 디렉터리에 기록한다.
