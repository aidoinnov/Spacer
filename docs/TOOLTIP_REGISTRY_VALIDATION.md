# B05 툴팁 등록 수명 분리 — 2026-11-09

draw마다 모든 툴팁을 제거/재등록하던 작업을 현재 presentation의 id/path/rect·대상 view가 바뀔 때만 실행한다. hover outline처럼 같은 위치를 다시 그리는 경우 native 등록은 유지한다. B05.04를 구현했으며 text/font/전체 frame·VoiceOver 종합 검사까지 완료한 것은 아니다.

## 원본 근거와 플랫폼 경계

원본 W14는 지속 TTooltip 객체와 dirty rebuild를 사용한다. `TTooltip.rebuild` **0x450590**은 dirty가 없으면 즉시 반환한다. [보존 원문](validation/windows-optimization-functions/0x450590.txt), [view tooltip 경로](validation/windows-optimization-functions/0x429aa0.txt), [체크리스트](OPTIMIZATION_CHECKLIST.md). 원본 setRows는 같은 rows인지 비교하지 않고 dirty를 켜며, 일부 paint TextExtent도 남는다. 모든 텍스트 측정을 생략한다는 근거로 확대하지 않는다.

이번 구현은 AppKit native tooltip **등록 영역**의 수명과 무효화를 관리하는 Mac 대체다. 원본의 bitmap/text extent cache를 복제한 것은 아니다. W14는 핵심 미적용에서 플랫폼 대체로 분류하며 원본 동일 구현 완료로 체크하지 않는다.

## 책임과 상태

[MapTooltipRegistry](../Sources/MacSpaceSniffer/MapTooltipRegistry.swift)가 현재 등록된 영역·native tag·userdata token·약한 NSView 참조만 소유한다. snapshot, DiskNode, MapItem, tooltip 내용 문자열을 보관하지 않는다. 대상 id/path/rect 배열과 tag 배열은 현재 presentation 범위만큼 유지하고 이전 세대 목록을 축적하지 않는다.

MapCanvas는 표시 항목과 현재 node 검증을 제공한다. content callback은 유효한 현재 노드를 확인한 뒤 기존 path/크기/수정일/오류 문자열을 그대로 계산한다. 동일 geometry의 metadata 변경도 현재 값으로 조회하며 content cache 때문에 이전 크기·날짜가 남는 구조가 아니다.

등록 순서와 `interactive && opacity>0.5 && width>15 && height>15` 조건은 유지한다. 추가로 geometry가 교체 중이거나 id/path가 현재 snapshot과 일치하지 않으면 등록을 비활성화한다. 이전 geometry가 새 node table의 같은 숫자 ID를 잘못 가리키는 상황을 차단한다.

영역이 바뀌면 기존 native 등록을 제거하고 새로 등록한다. userdata는 lifetime 동안 재사용하지 않는 양의 정수 token이다. 현재 연속 token 범위에서 index를 계산하고 native tag와 id/path를 다시 확인한다. 이전 세대 callback은 tag가 재사용되더라도 기존 token이 범위 밖이므로 새 노드를 읽지 못한다. token은 포인터로 역참조하지 않는다. hash dictionary 대신 현재 tag 배열을 사용한다.

전환 중에는 실제 draw에 사용한 `presentation()` 항목의 rect로 갱신하므로 보간 중 위치를 따라간다. opacity 경계 진입/이탈, outgoing의 noninteractive, resize, 대상 view 변경도 key에 반영된다. geometry 무효화·snapshot 부재·canvas detach에서 registry를 비운다. 고정 presentation의 hover redraw에서는 native 재등록을 생략한다.

## 테스트와 실패 보존

[MapTooltipTests](../Tests/MacSpaceSnifferTests/MapTooltipTests.swift)는 다음을 검사한다.

- 같은 presentation 60회에서 rebuild=1, 등록=현재 항목 수. callback metadata는 현재 크기·issue를 읽는다.
- 동일 숫자 ID의 path 교체, 이전 userdata token과 새 tag 조합, 현재 path 불일치, invalidate 이후 요청을 거부한다.
- 원래 eligibility/순서 및 geometry pending/current snapshot 검증을 유지한다.
- 실제 MapTransition의 시작/중간/완료와 중단 후 새 전환의 현재 rect를 등록한다.
- 현재 영역 축소·중복 invalidate·targets 정리와 autorelease pool 배출 후 view 해제를 확인한다.

첫 수명 검사는 AppKit autorelease pool이 남은 상태에서 즉시 view 해제를 요구해 실패했다. [실패 로그](validation/tooltip-registry-2026-11-09/first-attempt-tsan.log)와 [당시 테스트](validation/tooltip-registry-2026-11-09/first-attempt-tests.swift)를 보존했다. native 호출을 명시적 autorelease pool 안에 두고 배출 후 weak 해제를 확인하도록 수정했으며 해제 assertion을 제거하지 않았다.

최종 Swift ThreadSanitizer **99개**, 실패 0·경합 보고 0. tooltip 테스트 5개를 추가했다. [전체 로그](validation/tooltip-registry-2026-11-09/tsan.log).

## AppKit 구성 요소 전후 측정

[probe](../scripts/bench/map-tooltips.swift), [driver](../scripts/bench/measure-map-tooltips.py), [raw](validation/tooltip-registry-2026-11-09.json). [직전 실제 소스](validation/tooltip-registry-2026-11-09/TreemapView-before.swift)는 AX 단계의 보존 source hash와 대조한다.

같은 offscreen NSView에서 native `removeAllToolTips/addToolTip` 경로와 실제 registry를 각각 실행한다. 32개/1천 개의 고정 영역을 60회 갱신하고, 1천 개가 매번 이동하는 조건도 별도로 측정한다. 각 조건 5쌍, 프로세스별 교차 순서의 순차 측정이다. fixture 생성은 duration에서 제외하고 process peak RSS에 포함한다. 이동 fixture와 checksum 계산은 양쪽에 동일하게 포함한다.

| 영역/60회 조건 | 기존 중앙값 ms | 새 중앙값 ms | 기존/새 peak RSS 중앙값 MiB |
|---|---:|---:|---:|
| stationary-32 | 1.881 | 0.225 | 7.45 / 7.19 |
| stationary-1000 | 206.250 | 4.683 | 9.08 / 8.89 |
| moving-1000 | 216.569 | 203.434 | 12.55 / 14.19 |

고정 1천 영역은 rebuild **60→1회**, native 등록 **60,000→1,000회**다. 이동 조건은 두 경로 모두 rebuild 60회/등록 60,000회다. 이동 조건의 새 peak RSS는 약 1.6MiB 늘어 메모리 절감으로 주장하지 않는다. 모든 쌍의 rect checksum이 같고 clear 후 registry count=0이다.

native 등록 호출 수와 registry rebuild 수이며 전체 malloc 할당량/retained bytes가 아니다. process peak RSS도 cache 크기나 OS 반환량을 직접 나타내지 않는다. 실제 hover 지연·draw 전체·애니메이션 full frame을 측정한 결과가 아니다. 이동 조건에서 필요한 재등록은 생략하지 않는다.

## 앱·패키징 및 보존

별도 tooltip QA 앱에서 20개 도구·projection 재사용·admission·SNS/TXT·PNG·scoped scan/stop 등 MCP **92회** 요청을 통과했다. [결과](validation/tooltip-registry-2026-11-09/mcp-results.json). native AX tree에서 fixture의 `b, 2.1 MB`, `a, 1 MB`와 완료 상태를 확인했다. native popup의 실제 hover 지연/내용 배치 전체를 시각 검증한 결과는 아니다.

Universal **arm64/x86_64**·ad-hoc 서명 검사·packaged MCP 동일성을 확인했다. [빌드](validation/tooltip-registry-2026-11-09/build.log), [패키지](validation/tooltip-registry-2026-11-09/package.json). ZIP SHA-256 `f0b0861505f019119deba6aa4fddfada70d180f18d9d9611b6f8dfb282d7ee4c`. 버전 ZIP `dist/releases/tooltip-registry-2026-11-09-f0b0861505f0.zip`을 보존했다. Python **6개** 통과([로그](validation/tooltip-registry-2026-11-09/python-tests.log)).

이전 AX 측정의 raw/source/ZIP은 변경하지 않았다. `check-accessibility-cache-validation.py --historical`로 이전 기록을 검사한다. 현재 tooltip 결과는 별도 source archive·버전 ZIP에 연결한다.

루트 디스크 공간 부족으로 첫 shell heredoc 쓰기가 실패해 registry 파일이 비어 있었던 시도가 있었다. 파일 내용을 정상 작성한 뒤 빌드 임시 경로를 `.build/tmp`로 지정했다. 원본 REA 자료·기존 검증 archive는 삭제하지 않았다.

## 남은 범위

B05 text/font 측정 cache, text 속성 수명, 전체 frame·마지막 창 timer/AX/tooltip 종합 메모리 계측과 Reduce Motion·VoiceOver 종합 검증은 남는다. 개별 tooltip view 해제와 전환 rect 검사로 B05.07/08 전체를 체크하지 않는다. Windows 원본과의 동적 결과/성능 동등성도 미검증이다.


QA 앱을 종료하고 메인 앱 idle/jobs=[]를 확인한 뒤 새 Universal 빌드로 재실행했다. [이전 상태](validation/tooltip-registry-2026-11-09/main-before.json), [새 PID/idle](validation/tooltip-registry-2026-11-09/main-after.json). [최종 근거 검사](validation/tooltip-registry-2026-11-09/evidence-checks.json)도 모두 통과했다.
