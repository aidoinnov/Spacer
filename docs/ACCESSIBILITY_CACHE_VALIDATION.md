# B05 접근성 요소 재사용 — 2026-11-09

매 redraw에서 접근성 객체를 새로 만들던 경로를 경로 identity 기준으로 재사용한다. B05.05/06의 접근성 부분을 구현했으며 B05 전체 완료는 아니다. UI 레이아웃/애니메이션·엔진 필터/scan 동작은 바꾸지 않았다.

## 근거와 단일 책임 경계

B05의 원본 근거는 W13 `TTextBox.setText/getSize`의 dirty/치수 cache와 W14의 지속 tooltip/dirty rebuild다. [W13 원문](validation/windows-optimization-functions/0x435340.txt), [W14 원문](validation/windows-optimization-functions/0x450590.txt), [통합 목록](OPTIMIZATION_CHECKLIST.md). **AX element 재사용은 Mac 플랫폼 확장**이다. 원본 Windows가 VoiceOver 요소를 경로 cache로 관리했다는 주장은 하지 않으며, 이번 작업으로 원본 tooltip 최적화를 구현했다고 체크하지 않는다.

[MapAccessibilityCache](../Sources/MacSpaceSniffer/MapAccessibilityCache.swift)는 후보 제한·현재 path→ID·AX 요소 identity/label/frame·정리만 소유한다. snapshot, DiskNode, MapItem을 cache에 저장하지 않는다. [MapCanvas](../Sources/MacSpaceSniffer/TreemapView.swift)는 화면 좌표 변환과 현재 노드 확인·최종 selection을 소유한다. geometry/transition/tooltip/timer는 기존 소유 경계에 남겼다. M15 AccessibilityPresenter를 실제 파일로 분리했으며 전체 MapRenderer/TooltipRegistry 추출 완료를 뜻하지 않는다.

## 동작과 수명

즉시 하위 항목, interactive, opacity>0.5, 현재 id/path 일치라는 기존 조건과 순서를 그대로 적용한다. 500개를 찾으면 루프를 중단한다. 500개를 찾기 전까지 invalid 항목은 계속 건너뛰며, 첫 500개 raw 항목만 무조건 잘라 유효한 후보를 누락시키지 않는다. 기존 전체 filter 중간 배열은 만들지 않는다.

현재 후보 path의 요소를 재사용하고 ID mapping은 매번 갱신한다. 이름/크기가 바뀌면 label, screen rect가 바뀌면 frame을 갱신한다. 이름은 UTF-8로 비교하므로 Swift String의 NFC/NFD 동등성 때문에 현재 metadata의 정확한 표기를 놓치지 않는다. role/enabled는 생성 시 설정한다.

native activation은 path 하나만 전달하고 weak canvas를 통해 MainActor 작업을 예약한다. 실행 시 acceptsHits와 현재 cache의 ID 및 현재 store node의 path를 다시 확인한다. 과거 MapItem/tile/snapshot을 action closure에 보관하지 않는다. geometry 교체 시작 시 targets와 부모 연결을 무효화해 이전 요소가 새 node ID를 잘못 선택하지 못하게 한다. 새 presentation에서는 같은 path의 object identity를 이어 사용할 수 있다.

cache는 최대 500개다. 탈락한 요소는 dictionary와 부모 연결을 제거한다. canvas detach와 snapshot 부재에서도 cache/AX children을 비운다. 외부 접근성 클라이언트가 이전 요소를 보관해도 action은 weak owner와 현재 target 검사를 사용한다. 이 검증이 앱 전체 RSS 반환량이나 tooltip/timer 해제를 증명하는 것은 아니다.

## 독립 비교와 테스트

[기존 TreemapView](validation/accessibility-cache-2026-11-09/TreemapView-before.swift)를 이전 lifecycle 단계 hash와 일치하는 상태로 보존했다. [MapAccessibilityTests](../Tests/MacSpaceSnifferTests/MapAccessibilityTests.swift)의 expected 후보는 이전 filter→prefix(500) 경로를 사용한다.

- 1만 개 후보 및 앞쪽 invalid 항목에서 순서/label이 같고, 500개를 찾은 503회 방문 뒤 중단하는지 검사한다.
- 같은 path의 ID 1→70 이동, 크기/이름/좌표 및 NFC→NFD 표기 변경에도 object identity를 유지하면서 label/frame을 갱신하는지 검사한다.
- 이전 element의 activation이 현재 ID 12를 사용하고, path 교체/무효화 뒤 잘못된 selection을 하지 못하는지 확인한다.
- 외부에 남긴 element가 owner를 붙잡지 않는지, pruning/clear 후 요소와 parent 연결이 해제되는지 검사한다.

최종 Swift ThreadSanitizer **94개**, 실패 0·경합 보고 0. 새 executable target import 테스트 4개를 추가했으며 기존 실제 FSEvents/취소 검사도 포함한다. [TSAN 로그](validation/accessibility-cache-2026-11-09/tsan.log).

## AppKit 구성 요소 측정

[probe](../scripts/bench/map-accessibility.swift), [driver](../scripts/bench/measure-map-accessibility.py), [20개 raw 표본](validation/accessibility-cache-2026-11-09.json). 같은 native NSAccessibilityElement 기반 old filter/create 경로와 실제 MapAccessibilityCache를 `-O -whole-module-optimization`으로 컴파일했다. old 경로는 기존 draw 블록에서 parent/rect/무동작 selection callback을 주입한 구성 요소 비교이며, 이전 앱 전체를 실행한 frame benchmark가 아니다.

각 조건 5쌍을 프로세스별 교차 순서로 순차 실행한다. 32개 또는 1만 개의 고정 presentation을 offscreen NSView에 60회 갱신한다. 부모 children 연결, label/frame 구성·setter, 후보 순회 및 native 객체 생성이 포함된다. fixture 생성은 duration에서 제외하고 process peak RSS에 포함한다. AppKit autorelease pool은 update마다 정리하며 마지막 clear 이후 cache가 0개인지 검사한다. label/frame checksum이 모든 쌍에서 일치한다.

| 후보 입력/60회 | 기존 중앙값 ms | 새 중앙값 ms | 기존/새 peak RSS 중앙값 MiB |
|---|---:|---:|---:|
| 32 | 7.414 | 3.797 | 9.11 / 8.77 |
| 10000 | 197.345 | 17.077 | 100.72 / 13.95 |

1만 후보에서는 요소 생성 **30,000→500개**, 후보 방문 **600,000→30,000회**였다. 새 cache는 500개를 보유하다 clear 후 0개가 된다. 32개 조건은 1,920→32개 생성이며 방문 수는 양쪽 1,920회다.

객체 생성 수는 실제 element initializer 호출 횟수이며 전체 malloc 할당 수/bytes와 다르다. peak RSS는 프로세스 전체 최대값으로 cache retained byte 수가 아니다. 실제 draw·text/font 측정·tooltip·애니메이션 full frame 시간은 이 측정에 포함하지 않는다.

## 실제 앱·패키징

별도 AX QA 앱에서 20개 도구·projection 재사용·admission·SNS/TXT·PNG·scoped scan/stop 등 MCP **175회** 요청을 통과했다. [MCP 결과](validation/accessibility-cache-2026-11-09/mcp-results.json). native AX tree에서 `b, 2.1 MB`, `a, 1 MB` 버튼을 확인하고 `a` 버튼을 눌렀다. sidebar의 선택 항목이 a로 바뀌고 read-only MCP selected_path가 현재 fixture/a인 것을 확인했다. [UI 확인](validation/accessibility-cache-2026-11-09/ui-check.json), [실제 선택 상태](validation/accessibility-cache-2026-11-09/qa-after-ax-press.json). VoiceOver 앱 전체 사용성 검사를 대신하는 결과는 아니다.

Universal **arm64/x86_64**·ad-hoc 서명 검사·packaged MCP 동일성을 확인했다. [빌드](validation/accessibility-cache-2026-11-09/build.log), [패키지](validation/accessibility-cache-2026-11-09/package.json). ZIP SHA-256 `519ab2e50135495fb24c8cbe623e2d8ea04791f62edb48bf088de1e1fff42759`. 버전 ZIP `dist/releases/accessibility-cache-2026-11-09-519ab2e50135.zip`을 보존했다. Python **6개**도 통과했다([로그](validation/accessibility-cache-2026-11-09/python-tests.log)).

## 남은 B05

B05.01은 AX 구성 요소 기준선만 보강했으며 text/font/tooltip/rect index의 분리된 시간·할당 계측은 남아 있다. B05.02/03의 전체 text cache, B05.04 tooltip 등록 수명, B05.07의 중단 전환·Reduce Motion·VoiceOver 종합 검사, B05.08의 실제 frame/전체 cache·마지막 창 수명 검증은 미완료다. 이 작업의 단위/앱 검사만으로 전체 B05를 체크하지 않는다.

이전 lifecycle 단계 raw/source/ZIP은 바꾸지 않고 `check-refresh-lifecycle-validation.py --historical`로 검사한다. 현재 결과는 별도 source archive·버전 ZIP과 연결한다.


QA 앱을 종료하고 메인 앱 idle/jobs=[]를 확인한 뒤 새 Universal 빌드로 재실행했다. [이전 상태](validation/accessibility-cache-2026-11-09/main-before.json), [새 PID/idle 확인](validation/accessibility-cache-2026-11-09/main-after.json).


후속 tooltip 단계부터 현재 source/ZIP은 변경됐다. 이 문서의 당시 AX 측정/94개 테스트/source/버전 ZIP은 `check-accessibility-cache-validation.py --historical`로 검사한다. [현재 tooltip 검증](TOOLTIP_REGISTRY_VALIDATION.md)과 혼합하지 않는다.
