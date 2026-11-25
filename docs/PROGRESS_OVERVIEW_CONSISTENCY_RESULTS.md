# 진행 중 상위 폴더 집계 수정 — 2026-11-25

아래 수치는 설치 전 **168B 소스 후보 검증 이력**이다. 이후 정상 빌드의 모델을
184B로 복원하고 수정 사항을 **Spacer 0.3.2**로 양쪽에 설치했다.
최신 상태는 [0.3.2 설치·검수 기록](SPACER_0_3_2_INSTALL.md)을 따른다.
아래 과거 원문과 해시는 다시 쓰지 않는다.

## 바뀐 동작

- Mac은 기존 heartbeat 경계에서 전체 합계와 같은 시점의 상위 폴더 누계를 생성한다.
  전체 snapshot의 배수 증가 전송 제한은 유지한다.
- 새 노드는 한 번씩만 큰 파일 후보에 반영한다. builder가 탐색 스택에 상위 분기 ID를
  전달하고, 누계 변경 시 해당 ID만 dirty 집합에 기록한다. heartbeat는 변경 분기만 읽는다.
  이전 root 전체 목록을 매번 순회하거나 파일마다 조상을 다시 걷지 않는다.
  후보 탈락·값 불변 검사를 먼저 수행해 순위 밖 파일의 경로 문자열 생성도 피한다.
  추가 상태는 스택의 분기 ID·다음 이벤트까지의 변경 집합·bounded 후보이며,
  per-file dictionary나 새 filesystem 조회는 없다.
- Mac bridge의 폴더 4개 절단을 제거했다. Windows에서도 직속 파일이 폴더 후보를 밀어내지 않도록
  폴더/파일 후보를 분리하고, 마지막 배치를 반영한 진행 이벤트를 종료 집계 전에 발행한다.
- 양쪽 native는 `ScanOverviewPolicy`의 후보 상한·wire 버전을 공유한다.
  논리/할당 크기의 독립 후보를 유지해 sparse 항목과 순위 역전을 처리한다.
- Rust 공통 UI는 선택한 크기 기준으로 후보를 정렬한 뒤 최대 16개를 표시한다.
  폴더가 있으면 중첩 큰 파일 순위는 합산하지 않는다.
- ‘분석 중’이라는 차액 명칭을 제거했다. 새 계약의 실제 생략분은 ‘기타 항목’,
  구형 개요의 차액은 ‘기타 집계’, 개요 없는 초기 합계는 ‘폴더 집계 대기 중’으로 구별한다.
- 신형 개요의 중복 경로·후보 수 초과·폴더 수 모순·합계 초과/overflow는 transport에서 검출한다.
  오류를 stderr에 기록하고 잘못된 개요를 버리되, 전체 진행과 최종 문서 수신은 계속한다.

## Wire v1

기존 `roots` 배열을 유지하며 두 optional 필드를 추가했다.

| 필드 | 의미 |
|---|---|
| `overviewVersion: 1` | 현재 이벤트의 total과 후보 누계가 같은 관측 시점을 사용 |
| `rootFolderCount` | 현재까지 발견한 직계 폴더 수. 크기 0인 폴더도 포함 |
| `roots` | 크기 모드 2개 × 종류 2개 × 상한 16의 중복 제거 후보. 최대 64개 |

UI 표시 상한은 16개다. `total − 선택된 항목 합계`는 같은 관측 시점에 이미 집계한 생략분이며,
미탐색 공간 추정치가 아니다. 큰 파일 순위는 폴더와 중첩될 수 있어 두 종류의 합계를 별도로 검증한다.
구형 입력에 새 optional 필드가 없어도 역직렬화가 가능하다.
Mac의 큰 파일은 전체 트리 순위, Windows는 직계 파일 후보다. 폴더가 있는 지도에서는
둘 다 숨겨 중복 합산을 피하므로, 전역 순위의 의미까지 동일해졌다고 설명하지 않는다.

진행 이벤트는 비동기 전달 중 합쳐질 수 있다. 마지막 progress의 파일 수가 최종 파일 수와
반드시 같아야 하는 계약은 없다. **각 이벤트 내부 일관성**과 **최종 문서 oracle**을 각각 검증한다.

## 검증

| 항목 | 결과 |
|---|---|
| 수정 전 Swift 재현 | 실패 확인: 동일 노드 수의 폴더 100→500 변경을 반영하지 못함 |
| Mac 개요·진행·볼륨·집계 테스트 | 27개, 실패 0, 환경 조건에 따른 제외 3개 |
| Windows132 실제 Swift 테스트 | 13개 통과. 실제 8개 폴더 진행 합계·native I/O·취소/오류·링크/마운트·직렬화 포함 |
| 공통 UI/scan 플랫폼 경계 검사 | 통과 |
| Rust 단위 테스트 | QA feature 포함 37개 통과. 실제 native JSON 3개를 decode→검증→배치하는 회귀 포함 |
| clippy | QA feature·all-targets·`-D warnings` 통과 |
| Mac 숨김 GPUI 렌더 | 1340×861, snapshot 없이 폴더 타일 8개, 전부 탐색 가능 상태 |
| Mac 실제 native 진행 oracle | 65,536파일·폴더 8개, 진행 41개, 두 크기 기준의 최대 차액 0바이트 |

수정 전 설치된 backend의 8개 폴더·65,536파일 재현은 256MiB 중 128MiB가 폴더 전송에서
빠졌다. 수정 후 최종 정책 파일을 포함한 빌드에서는 41개 신형 진행 이벤트 모두 논리/할당 합계 차액
0바이트를 확인했다. 최종 문서도 폴더 8개·논리 65,536바이트·할당 268,435,456바이트로
독립 oracle과 일치했다. 실제 progress 한 줄은 최대 4,687바이트였다.
소유 native 프로세스 정상 종료, reader 종료, 임시 fixture 제거를 모두 확인했다.
호스트 부하와 debug 빌드의 실행 시간은 참고 원문에만 남기고 속도 개선 수치로 사용하지 않는다.

분기 갱신 비용의 결정적 테스트: 상위 폴더 1,000개 등록 후 한 분기의 변경 신호를
100번 보내도 갱신은 1개, 다음 무변경 이벤트에서는 0개였다. 이는 처리 항목 수의 검증이며
전체 스캔 시간/RSS 개선률을 측정한 것은 아니다.

원문: [검증 요약](validation/progress-overview-2026-11-25/summary.json),
[숨김 렌더 캡처](validation/progress-overview-2026-11-25/mac-render.png),
[검증 디렉터리](validation/progress-overview-2026-11-25/).
수정 전/후의 엔진 모델과 최적화 설정이 달라, 이 데이터로 속도 배수를 계산하지 않는다.

재실행:

```sh
swift test --scratch-path /private/tmp/spacer-overview-fix-build --jobs 2 \
  --filter 'ScanOverviewTests|ScanProgressTests|SpaceSnifferCoreTests.ScanVolume|SpaceSnifferCoreTests.SpaceAccounting'
python3 scripts/gpui-app/check-progress-overview.py \
  --backend /private/tmp/spacer-overview-fix-build/arm64-apple-macosx/debug/MacScanBridge \
  --output /private/tmp/spacer-overview-native-verification
cargo +1.97.0 test --locked --manifest-path gpui-app/Cargo.toml --jobs 2
python3 scripts/check-gpui-boundary.py
python3 scripts/check-scan-platform-boundary.py
```

Windows는 VS x64 Developer PowerShell에서 다음을 실행한다:

```powershell
swift test --package-path Packages\SpaceSnifferWindows --scratch-path Build-overview --jobs 2
```

## 후속 범위

184B 모델의 패키지 제작·설치와 양쪽 실제 화면/명령 기반 탐색 검수는 0.3.2에서 완료했다.
정식 동일 조건의 시간/RSS 판정과 과거 종료 지연 조사는 여전히 후속이다.
물리적 드래그·단축키·휴지통 입력 전수 검수는 이번 설치에서 반복하지 않았다.
