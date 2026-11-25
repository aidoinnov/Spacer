# 스캔 중 트리맵이 비어 있던 문제

2026-11-25 추가: 타일이 보이는 것과 폴더 누계가 최신인 것은 별개였다.
배수 갱신 제한 재사용·Mac 폴더 4개 절단을 확인했고,
[별도 소스 수정·검증 기록](PROGRESS_OVERVIEW_CONSISTENCY_RESULTS.md)에 정리했다.
아래 내용은 11월 23일 당시의 렌더 검증 이력이며 새 설치 완료를 뜻하지 않는다.

2026-11-23 수정. 기존 GPUI canvas는 `Projection`만 읽었다. `Projection`은 최종 snapshot 수신 후 만들어지므로 진행 중 `Progress.roots`가 도착해도 개요 표와 용량만 갱신되고 사각형은 없었다.

현재 canvas는 진행 중에는 bounded 개요 타일을, 상세 분석 준비 후에는 기존 중첩 타일을 그린다. 폴더 순위와 파일 순위는 서로 포함될 수 있으므로 한 지도에서 중복 합산하지 않는다. 폴더가 있으면 폴더를, 없으면 파일을 사용하고, 이미 집계된 나머지만 별도 타일에 넣는다. 아직 읽지 않은 용량을 추정하지 않는다. 개요 타일에는 상세 node ID를 부여하지 않아 잘못된 경로 탐색을 막는다. 완료 직후 상세 projection이 준비될 때까지 개요를 유지한다.

- [Mac 렌더 캡처](validation/gpui-2026-11-23/mac/progress-map.png)
- [렌더 검증 원문](validation/gpui-2026-11-23/mac/progress-map.json): `scanning=true`, `hasSnapshot=false`, 사각형 4개, 1340×861. 실제 대용량 스캔이 아니라 scripted IPC progress 입력을 사용한 숨김 GPUI 렌더 검증이다.
- [11개 테스트](validation/gpui-2026-11-23/progress-tests.log): 진행 중 사각형, 폴더/파일 중복 방지, 논리 크기, aggregate-only 개요와 기존 모션/배치/가중치 재사용 회귀.
- [clippy](validation/gpui-2026-11-23/progress-clippy.log), [공통 UI 경계](validation/gpui-2026-11-23/platform-boundary.log).

Windows 공통 코드 빌드는 통과했으나 숨김 창 readback이 1×1로 반환됐다. [이전 probe 원문](validation/gpui-2026-11-23/windows/progress-map-raw.json)의 `passed=true`는 시각 검증 통과로 사용하지 않는다. 이후 probe는 최소 캡처 크기도 검사하도록 강화했다. Windows 화면의 최종 시각 검증은 미완료다.

현재 실행 중인 Mac GUI/스캔 프로세스는 유지했다. 수정 executable은 기존 파일을 덮어 쓰지 않고 새 inode로 원자 교체했으며, 실행 중인 이전 코드에는 즉시 적용되지 않는다. **다음 앱 실행부터 적용된다.** 기존 파일은 `space-sniffer-gpui.before-progress-map`으로 보관했다. [교체 기록](validation/gpui-2026-11-23/progress-fix-staged.json).

## 후속 실제 적용

사용자의 재실행 요청으로 이전 결과 2,560,731,320바이트를 복구 폴더에 APFS clone으로 보존한 뒤 수정본에서 `/Volumes/develop`를 다시 검사했다. CUA 실제 창에서 스캔 중 4.3GB·폴더 3,651·대기 61 상태와 사각형을 확인했다. 이전 결과를 새 스캔에 주입한 것은 아니다. [재실행·보존·관측 기록](validation/gpui-2026-11-23/progress-fix-relaunch.json).

## 중복 개요 표 제거

사용자 요청으로 큰 폴더/큰 파일 순위 표와 중복 안내 문구를 제거했다. 개요 데이터는 진행 중 트리맵에 계속 사용하며, 상태·검사 수·현재 경로·오류만 텍스트로 유지한다. [표 없는 렌더 검증](validation/gpui-2026-11-23/mac/progress-map-no-table.json)과 [캡처](validation/gpui-2026-11-23/mac/progress-map-no-table.png)를 보관했다. 앱을 재실행한 실제 `/Volumes/develop` 검사에서도 5.7GB·폴더 5,463 상태에서 표 없이 트리맵이 표시되는 것을 CUA로 확인했다.
