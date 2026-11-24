# GPUI 볼륨 범위·미리보기 후속 검증

2026-11-23. Mac 볼륨 범위 연결과 SNS 재로드 결함을 수정했다. Windows preview는
구현·교차 빌드까지만 검증했다. 132 PC가 SSH/ping에 응답하지 않아 Windows의
실제 preview 표시 및 최종 배포는 미완료다. 전체 GPUI 이식 완료를 뜻하지 않는다.

## 책임과 수정

- 공통 UI는 platform capability로 메뉴를 활성화하고 backend에 scope를 전달한다.
  Mac은 기존 ScanService의 selectedVolume/allVolumes 정책을 재사용한다.
  Windows는 지원하지 않는 allVolumes 요청을 명시적으로 거부한다.
- snapshot의 실제 volumeTraversal을 inspector에 표시한다. progress가 제외 경계
  수를 제공하지 않으면 0으로 단정하지 않고 완료 후 확인으로 표시한다.
- Windows preview는 Rust platform adapter와 별도 C++ helper로 분리했다.
  GPUI 화면은 공통이며 native API·readiness·Job 수명은 port가 소유한다.
  [빌드·제한·실제 실행 시나리오](../gpui-app/native/windows-preview/README.md).
- SNS native drive record는 파일 합계가 아니라 volume capacity를 저장한다.
  파일별 할당량 합계가 capacity를 넘는 정상 문서를 decoder가 거부하던 문제를
  회귀 테스트로 재현하고 수정했다. 일반 폴더의 잘못된 합계와 transitive leaf
  Int64 overflow는 계속 거부한다. 공유 Model 원본을 수정했으며 OS 분기를 추가하지 않았다.

## 정량 결과

증거: [followup](validation/gpui-2026-11-23/followup).

| 시나리오 | 결과 | 판정 |
|---|---|---|
| 실제 중첩 mount native selected → all → selected | 파일 100 → 6100 → 100, 경계 제외 1 → 0 → 1 | 통과 |
| 같은 fixture GPUI 공통 메뉴 command | 파일 100 → 6100 → 100, root 재시작 확인 | 통과 |
| GPUI scan+IPC+projection 소요 표본 | 207 / 1597 / 152ms | 각 1회, 성능 향상 비교 근거 아님 |
| SNS capacity 회귀 | 수정 전 invalid 오류 재현 → 수정 후 roundtrip 통과 | 통과 |
| Swift Core release | 285 tests, 실패 0, skip 0, 약 53초 | 통과 |
| 공유 ExplorerDomain | 4 tests, 실패 0 | 통과 |
| Rust | 16 tests, 실패 0 | 통과 |
| Rust clippy -D warnings | Mac all-targets 및 Windows adapter target | 통과 |
| Windows C++ helper | MinGW C++20 -Wall -Wextra -Werror 빌드 | 통과, MSVC·runtime 별도 |
| 최신 Mac 후보 bundle 문서·Quick Look·SNS acceptance | 1,711ms, passed=true | 통과, 작은 fixture |
| Windows 실제 preview | 132 PC 연결 불가 | 미완료 |

중첩 mount는 테스트 소유 sparse image 2개이며 검사 후 detach·삭제를 완료했다.
GUI 캡처는 allVolumes 상태의 6,100파일 트리맵과 분석 범위 문구를 확인한 것이다.
공통 메뉴 command를 호출한 앱 내부 acceptance이며 OS 메뉴 클릭 전체 검증은 아니다.

기존 사용자의 `/Volumes/develop` 창에서 약 659만 파일·533.8GB 결과와 트리맵을
확인했다. 시작 볼륨 capacity는 499.9GB로 표시됐다. 이 관찰은 합계와 capacity의
차이를 보여주지만, 전체 대형 SNS 왕복·전체 스캔 속도·메모리 gate 통과를 뜻하지
않는다. UI의 마지막 7.22초를 전체 659만 파일 검사 시간으로 해석하지 않는다.

## 적용 상태와 남은 일

실행 중인 사용자 preview 창과 native scan process는 종료하거나 교체하지 않았다.
후속 소스와 테스트 후보는 별개다. [별도 Mac 후보 앱](<../dist/Space Sniffer GPUI Followup.app>)을 ad-hoc 서명하고 strict 검증했다. 해당 bundle 자체를 작은 fixture에서 실행해 문서·태그·필터·Quick Look·SNS acceptance를 통과했다. debug/QA 후보이며 release 배포본은 아니다. production 설치 앱/Windows 기본 배포물은 유지한다.

- [x] Mac scope 실제 mount·GPUI, SNS regression, shared source/OS 경계 검사.
- [x] Windows preview 구현, C++ 빌드와 Rust Windows target 검사.
- [ ] 132 PC에서 MSVC 빌드, 실제 Space·창 표시·resize·닫기·부모 종료 검증.
- [ ] Windows mount opt-in, mount 목록 실시간 갱신.
- [ ] 전체 큰 SNS 왕복·연속 필터/작업 교체·메모리/최종 시각 동등성 gate.
- [ ] 기존 자동화/MCP·다중 창과 나머지 [기능 동등성](GPUI_FEATURE_PARITY.md).
- [ ] 두 플랫폼 최종 서명·패키징·배포 및 설치본 실행 검증.

재현은 `scripts/gpui-app/check-volume-bridge.py --help`, `gpui-app`의
`--features qa --qa-volumes-only REPORT.json`,
`swift test --filter SpaceSnifferCoreTests`, 공유 package `swift test`,
`cargo +1.97.0 test --features qa`를 사용한다. 실제 mount Core 검증에는
`SNIFFER_SCOPE_MANIFEST`로 fixture manifest를 전달한다.
