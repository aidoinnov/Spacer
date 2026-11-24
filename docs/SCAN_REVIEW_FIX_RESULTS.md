# 재검토 세 결함 수정 결과 — 2026-11-21

후속 GUI 검증에서 별도 native watch 삭제 이벤트 누락을 발견·수정했다. [최신 채택 검증](SCAN_FINAL_GATE_RESULTS.md)을 함께 확인한다. 아래는 세 결함 수정 당시의 기록이다.

**취소·경로 값 동등성·ENTRYCOUNT 계측을 수정했다. 성능 채택과 배포는 HOLD다.** 기본 정책은4후보/64기회, 최대 동시 작업4를 유지했다. 설치0.2.1을 바꾸지 않았다.

[완료 TODO](SCAN_ALL_FIVE_FIX_TODO.md) · [정량 측정표](validation/scan-review-fix-2026-11-21/MEASUREMENTS.md) · [수치·gate·SHA](validation/scan-review-fix-2026-11-21/summary.json) · [수정 전 검토](SCAN_ALL_FIVE_REVIEW.md)

## 코드와 책임

| 수정 | 구현 | 검증 |
|---|---|---|
| sparse fallback 취소 | Mac reader의 전체 index 주기 검사와 각 stat 직전 검사를 분리. 검사→counter→stat 순서. metadata 완성 helper와 내부 stat seam만 추가 | 누락1·65·129·193에서 취소 전0회, 진행 중1회 후 추가0회. 실제 native reader→pool→ticket 취소·permit 반환 |
| 경로 동등성 | 동일 compact components fast path 유지, 나머지는 공개 wrappedValue 비교 | compact `/foo`·`/foo/`+bar와 literal 동등. 대칭·추이·반사성, Unicode/raw spelling·Windows literal·CoW·JSON 보존 |
| ENTRYCOUNT 관측 | native adapter가 실제 call 횟수·단조 시간·즉시 보존한 errno를 observer로 전달. scan-local scalar metrics로 합산 | root·sibling 호출, hint hit,0-entry·실패·누락 속성·취소 전후·legacy JSON·merge 검증 |

공통 admission에는 OS API·clock·전역 counter를 추가하지 않았다. `EntryCountMetrics`는 고정 크기 값으로 관측을 모으고, 이전 JSON의 필드 부재는 nil(미측정)로 남긴다. stat/bulk 수와 count 수를 별도로 보고하며 모든 syscall 합계라고 부르지 않는다. SNS/public node schema와184byte node layout은 유지했다.

취소 검사가 관찰한 시점이 보장의 기준이다. 이미 승인되어 진행 중인 동기 syscall1회는 완료될 수 있으며 다음 호출은 중단한다. sparse 통합 테스트는 reader/pool/ticket까지 실제 native 경로를 사용했다. builder는 기존 통합 테스트로 검증했고, 새 sparse 주입이 builder까지 직접 연결됐다고 집계하지 않았다. 경로 계약 위반은 재현했지만 정규화된 scanner 입력에서 실제 UI 오동작이 발생했다는 증거는 없다. 독립 equality probe는 각100만 번 일치를 확인했고 동일 components 중앙값17.5ns/회, 다른 compact 표현 fallback466.5ns/회였다. 이 수치는 scanner/GUI 속도나 채택 성능 기준을 뜻하지 않는다.

## 테스트 결과와 한계

수정 전 새 제품 테스트4개에서 assertion14건 실패를 보존했고, 수정 후 통과했다. 전체 root323개(4skip) 실패0 이후 ENTRYCOUNT8개(기존7개와 중복), 수정된 기존 permit 테스트1개를 추가 검증했다. **서로 다른 root 테스트는324개, 공통 패키지는 debug/release 각각19개 실패0**이다. 마지막 추가 테스트 후 전체를 다시 실행한 결과라고 표현하지 않는다.

Mac TSAN 최종35개 실패0. 최초 TSAN에서는 기존8-master 대용량 fixture가12초 timeout에 실패했다. 실패 로그를 보존하고 테스트를 결정적 gate 방식으로 바꿨다.8개 root와8개 inline I/O를 각각 barrier에 정지해 permit8개 점유 상태를 직접 확인한 뒤 해제·종료를 검증한다. 입력은64×1파일과 stale hint64를 사용한다. 성능 기준을 완화하거나 최초 timeout을 통과로 바꾸지 않았다.

ARM·Intel release CLI의9,600파일 oracle/TXT byte 일치·SNS 상호 로드, consumer의 wait 허용/생성·완료 거부, 플랫폼 경계와 원본 근거 검사를 확인했다. Windows native 실행·GUI/watch·최종 패키징은 이번 완료 범위에 포함하지 않는다.

## 정량 실험과 정책 판단

V5 frozen probe 대비 수정 버전은 표준7입력×21쌍×3변형=441회와 warmup63회를 수집했다. correctness oracle·Swift 전체 노드 digest는 일치했다. 기본 정책 후보는 **성능 gate2/7 통과**다. 이전 V5 대 C3의6/7과 비교 대상이 다르다. 작은 표본·시간 기준 실패를 CPU/RSS 통과로 덮지 않았다.

정책 실험은 tiny1000을100쌍, 나머지6입력을21쌍씩 측정했다. 같은 binary·같은 mode의 중복 대조군을 포함해904회+warmup84회다. 최초 실행은 순서 편중을 발견해 원자료를 보존했다. 수정된 실행은100쌍에서 각 변형을 네 실행 위치에25번씩 배치했다. 두 실험 모두 공개한다. 균등 순서는 watchdog 한도 전에 완료5입력을 보존하고 의도적으로 중단한 뒤 나머지2입력을 별도 lease로 수집했다. 첫 구간의 미완료 oversized 표본은904회에서 제외했다. 두 구간 모두 앱 정지 조건을 유지했으며 원본 중단·정리·재개와 합산 규칙을 보존했다.

| tiny1000 정책 | 실제 count 호출 | native query 중앙값 ms | scan p50/p95 ms |
|---|---:|---:|---:|
| 현재4후보/64기회 |60|0.265|30.863/45.983|
| 같은 binary·같은 mode 대조군 |60|0.260|32.617/53.453|
|1후보/64기회 |15|0.099|31.148/58.668|
| 재표본 비활성 실험 |4|0.025|32.743/51.639|

query 중앙값은 전체 scan 중앙값의 약0.9%다. 이는 native call 구간이며 allocation/parser/전체 scheduling 비용을 포함하지 않는다. 조회 수를 줄였다는 사실만으로 p95 원인을 확정할 수 없다. 동일 binary A/A는7입력 중1개만 전체 gate를 통과했다. 편차가 남아 단일 후보의 개선을 채택할 근거가 부족하다.

재표본 비활성은 작은 폴더 뒤에 큰 폴더가 몰린 입력에서 `prefetchUsed`가69→0으로 줄었다.1후보는 첫 oversized/교대 혼합 입력에서199→134로 작업 수락이 늦어졌다. 정확성은 유지하지만 기본 정책 변경 근거가 되지 않는다. 소멸 입력은 결정적 scanner 테스트에서 검증했으며 반복 성능 matrix에는 포함하지 않았다.

## 재현 자료와 남은 gate

검증 폴더의 source archive는 수정 전/후 Core와 테스트, 공통 패키지를 담는다. binary/source SHA, 실제 명령, 실패·warmup·fixture 정리·앱 pause/resume 기록과 압축 raw 결과를 함께 보존한다. 실제 설치 앱과 프로파일링용 scratch probe를 구분한다. 측정 시간은 engine scan과 digest 등을 포함한 process wall로 나누며 GUI 지연으로 해석하지 않는다.

다음 작업은 조용한 수집 조건에서 A/A 신뢰도를 먼저 확보하고 표준 latency·paired CI gate를 통과하는 것이다. 그 뒤 GUI/watch·패키징·배포를 검증한다. 거대 폴더의 중간 선점과 Windows native 검증은 별도 후속이다.
