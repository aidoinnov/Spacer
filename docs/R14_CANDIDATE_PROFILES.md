# R14: 원본 최적화 후보의 재선정과 bounded prototype

작성일 2026-11-09. 원본 Windows 정적 원문을 재사용하고 Mac의 실제 입력·독립 oracle·국소 실측으로 후보를 재선정했다. Windows 실행 비교는 수행하지 않았다. 실행 당시 사용자의 GUI `/Volumes/develop` 스캔·watch 및 다른 에이전트 작업이 함께 실행되었으므로 전 볼륨의 속도 개선율을 주장하지 않는다. 아래는 체크리스트 완료 선언이 아니라 채택 근거와 남은 검증 경계다.

## 결론

| 원본 ID | 이번 판정 | 실제 근거 / 남은 경계 |
|---|---|---|
| W17 + W23, bulk 열거 + metadata 재사용 | bounded opt-in 후보 구현, 기본 POSIX 유지 | 독립 C oracle 2,063개 0차이, mount 5개 0차이. 실제 Scanner 동등성 8개 테스트 통과. 작은 APFS 디렉터리의 syscall 제거 이득 확인. 모든 FS·변경 경쟁 동등성을 의미하지 않음 |
| W18, 경로 segment 저장 | 추가 연구 필요 | 709만 노드의 full path 원시 UTF8 1.098GB, name 0.132GB. 잠재적 중복은 크지만 실제 heap 절감·경로 조합 비용·COW/API 계약 측정 없음 |
| W25, 계층 hit-test | 현재 기본 채택 보류 | 실제 presentation 표본 22개에서 flat kernel이 더 빠름. 2천/2만 개 synthetic에서는 계층 이득, transition containment·paint ordering 보장 필요 |
| W28, SNS stream reader | 담당 root의 reader 실측으로 별도 판정 | 원본 record stream 확인. 이번 O(depth) 감사기는 decoder가 아니므로 production 메모리 개선 증거로 대체하지 않음 |
| W29, child-name hint | 현재 기본 채택 보류 | 지역성 workload에서는 큰 이득, random에서는 느려짐. duplicate sibling name에서 first-match 계약이 달라짐 |

## 원본 근거와 플랫폼 대체

ID는 [기존 30항 체크리스트](OPTIMIZATION_CHECKLIST.md)의 번호를 유지한다. W23은 hit-test가 아니라 metadata 재사용이고, hit-test는 W25다. 각 원문 헤더에 대상 EXE SHA256와 전체 Evidence ID가 있다.

- W17/W23: [0x455be0](validation/windows-optimization-functions/0x455be0.txt), [0x405d30](validation/windows-optimization-functions/0x405d30.txt). Windows 큰 열거 버퍼 경로와 전달된 size 재사용, 조건부 compressed/sparse/handle size query. Mac `getattrlistbulk`는 해당 API의 복제가 아니라 플랫폼 I/O 대체다.
- W18: [0x405260](validation/windows-optimization-functions/0x405260.txt), [0x4061b0](validation/windows-optimization-functions/0x4061b0.txt). 부모/segment로 full path를 구성한다. Swift String intern이나 allocator 정책을 원본에서 관측한 것으로 확대하지 않는다.
- W25: [0x4680b0](validation/windows-optimization-functions/0x4680b0.txt). visibility/rect 검사 후 자식 재귀와 첫 일치. 현재 Mac reverse-paint hit oracle와 원본 forward-first/정수 경계는 별개다.
- W28: [0x408ef0](validation/windows-optimization-functions/0x408ef0.txt), [0x4093c0](validation/windows-optimization-functions/0x4093c0.txt), [0x4576f0](validation/windows-optimization-functions/0x4576f0.txt). FILE/fread record 입력, 최종 노드 트리는 유지한다.
- W29: [0x4068a0](validation/windows-optimization-functions/0x4068a0.txt), [0x406d30](validation/windows-optimization-functions/0x406d30.txt), [0x455be0](validation/windows-optimization-functions/0x455be0.txt). hint 주변 양방향 선형 이름 검색이며 이진 검색이 아니다.

## 대규모 실제 SNS 입력: 경로와 NodeTable

[`develop-path-audit.json`](validation/r-backlog-2026-11-09/r14/develop-path-audit.json)의 입력은 `/Users/aido/.local/share/mac-space-sniffer/validation/2026-11-09/develop-baseline.sns`, 744,975,698B, SHA256 `ffee4c3f9d58eb8fd62bb6f095a600db0ef495ccce0d02aa1c386d39e8f7a3f4`다. 읽기 시작/끝 size·mtime 및 SHA를 확인했다. 6,236,823 files + 855,528 folders = 7,092,351 nodes. file logical/physical 합은 root와 일치한다. 최대 깊이 42, 최대 path 729 UTF8B, 최대 자식 196,608이다.

[`r14-sns-path-audit.py`](../scripts/bench/r14-sns-path-audit.py)는 O(depth) stack으로 record를 읽고 길이를 합산한다. 전체 full path·node 배열을 생성하지 않는다. 74.117초는 감사 시간이며 앱 decode benchmark가 아니다. v2 ACP는 명시적으로 거부한다.

| 분리한 표현 | 크기 | 해석 |
|---|---:|---|
| 재구성 full path UTF8 payload | 1,098,045,700B | String allocator/terminator/capacity 제외 |
| name UTF8 payload | 132,426,898B | 작은 String inline과 별도 heap payload를 혼동하지 않음 |
| 이름 UTF16 / Base64 | 264,223,506 / 361,988,744B | SNS 인코딩 단계의 다른 표현, 위 값과 동시에 heap 합산 불가 |
| DiskNode inline cells (stride 184 × count) | 1,304,992,584B | 현재 arm64 SDK의 MemoryLayout, String/Array/Optional handle 포함 |
| child edge Int payload | 56,738,800B | capacity/array header 제외 |
| full path minus segment payload | 965,618,802B | ancestor 반복의 원시 길이 모델, 실측 절감량 아님 |

[`layout.json`](validation/r-backlog-2026-11-09/r14/layout.json), [`memory-attribution-model.json`](validation/r-backlog-2026-11-09/r14/memory-attribution-model.json)에 가정과 제외 항목을 보관했다. NodeTable wrapper는 16B지만 내부 node cell이 사라지지 않는다. fileIdentity 문자열, allocator/header/capacity, Foundation/reader buffer, VM resident/shared/COW를 실제 attribution하지 않았다. 기존 전체 scan+SNS peak footprint 6.443GB를 이 숫자의 합으로 설명하지 않는다. W18은 실질적 기회지만 path materialization 비용, identity/tag/query/SNS 경계 및 freeze/COW 회귀를 먼저 측정해야 한다.

## W17/W23: bulk metadata 수집

API 계약은 로컬 macOS SDK `sys/attr.h`, `sys/vnode.h`, `sys/xattr.h`, `man2/getattrlistbulk.2`, `man2/getattrlist.2`를 확인했다. NAME + RETURNED_ATTRS 필수, ERROR 필드 순서, FSOPT_PACK_INVAL_ATTRS placeholder, OBJTYPE별 directory/file group packing, attrreference bounds를 검증했다. mount/firmlink 열거 record는 underlying entry를 기술할 수 있어 full-path lstat identity와 다르다. symlink는 link 자체 metadata이며 기존 skip 정책을 유지한다.

연구용 [`r14-bulk-metadata.c`](../scripts/bench/r14-bulk-metadata.c)의 독립 oracle은 readdir + relative fstatat(AT_SYMLINK_NOFOLLOW)와 이름별 모든 요청 필드를 비교한다. 2,063 entries에서 0차이, 6 bulk calls, fallback 0이다. `/Volumes` read-only oracle은 5 entries, 4 mount fallback, 0차이다. unicode/NFD/long/hidden/readonly/hardlink/symlink/broken/cycle/FIFO/resource fork가 포함된다. C fixture의 sparse-intent 파일은 실제 sparse가 아니었으며 Swift 회귀에서 F_PUNCHHOLE 후 blocks<size를 별도 검증했다.

첫 parser는 file record에서도 directory group을 읽어 2,055/2,063 차이를 냈다. 실패 원문·binary·stderr를 보존하고 object type별 group 파싱으로 수정했다. 이를 성공한 실행으로 덮어쓰지 않았다.

[`bulk-profile.json`](validation/r-backlog-2026-11-09/r14/bulk-profile.json)은 5 alternating fresh-process pairs × 25 passes다. process별 checksum 동등. POSIX median 0.658367s (0.240–0.824), bulk 0.159575s (0.098–0.266). POSIX는 readdir 51,650 + stat 51,575 calls, bulk는 150 calls + stat 0이다. RSS median은 6.09MB / 6.01MB다. flat fixture와 relative fstatat baseline이므로 전체 Scanner 4배 개선이라는 결론은 성립하지 않는다.

### 실제 Core 후보의 안전 경계

[`NativeDirectoryMetadata.swift`](../Sources/SpaceSnifferCore/NativeDirectoryMetadata.swift)는 디렉터리별 private fd, 64KiB buffer, 최대 4,096 entries/추정 4MiB로 전체 수집한다. 추정량은 hard allocator limit가 아니며 String/Set/Array overhead의 보수적 charge다. 이름/record 전체 검증 완료 전에는 Scanner에 append하지 않는다. cap, 오류, malformed, 누락 이름, 취소면 nil을 반환해 기존 opendir/readdir+lstat 경로를 그대로 수행한다. 유효한 이름의 필수 metadata 누락/entry error/mount/firmlink/unknown type은 그 entry의 lstat만 사용한다. 필요한 필드 DTO만 전달하며 가짜 stat을 만들지 않는다. 기존 정렬·symlink skip·스캔 단일 worker·issue 정책은 유지한다.

`Scanner.swift`의 public scan API는 유지했다. internal backend override로 양쪽 경로를 비교하며 기본은 `.posix`다. 4,096보다 큰 실제 디렉터리에서는 bounded 시도 후 원래 경로를 수행해 비용이 추가될 수 있다. 현재 앱 watcher/rescan 공통 scheduling이나 FSEvents 의미를 바꾸지 않는다. 디렉터리가 수집/사용 사이 바뀌는 경쟁은 두 방식 모두 원자적 snapshot이 아니므로 완전 동등하다고 주장하지 않는다.

[`NativeDirectoryMetadataTests.swift`](../Tests/SpaceSnifferCoreTests/NativeDirectoryMetadataTests.swift), [`native-bulk-tests-final.log`](validation/r-backlog-2026-11-09/r14/native-bulk-tests-final.log): **8 tests, 0 skipped, 0 failures**. recursive DiskNode 전체 필드/identity/times/attributes/합계, >4,096 wide 및 작은 cap, 지원 안함·첫/후속 오류·malformed·필드 누락·firmlink·unknown type, actual mount, cancellation+private fd close, sparse, denied/deleted directory를 비교했다. fixture atime은 양쪽 scan 전에 재설정하고 volume free/time처럼 별도 OS 표본은 field 동등성 대상에서 제외했다. 추가 [legacy scan 회귀](validation/r-backlog-2026-11-09/r14/scanner-regression-tests.log)는 Recovery/Progress/Scheduling 13 tests, 0 failures다.

### 실제 Scanner 최적화 빌드 측정

[`r14-native-scan.swift`](../scripts/bench/r14-native-scan.swift)는 현재 Core 소스를 같은 module로 `swiftc -O -whole-module-optimization` 빌드한다. [`native-profile.json`](validation/r-backlog-2026-11-09/r14/native-profile.json)은 fixture별 5 alternating fresh-process pairs × 5 scans/process다. scan만 timed, checksum은 타이머 밖이며 양쪽의 모든 pair가 일치했다. field 완전 동등성은 앞의 XCTest가 담당한다. 시간은 5회 scan 합계의 process median이다.

| owned fixture | POSIX | bulk | POSIX / bulk peak RSS median |
|---|---:|---:|---:|
| flat 2,048 files | 0.074935s | 0.051581s | 8.59 / 10.55MB |
| 32 folders × 64 files | 0.122532s | 0.065918s | 8.49 / 8.83MB |
| wide 4,100 files (cap fallback) | 0.149830s | 0.212810s | 11.09 / 14.14MB |

wide fallback은 약 42% 느렸고 추가 메모리를 사용했다. 실제 입력에는 최대 196,608 siblings가 있으므로 이 손해를 숨기고 기본 활성화할 수 없다. 후보를 유지하되 기본 `.posix`로 두는 이유다. RSS는 checksum/전체 process를 포함한다. 재귀 작은 fixture에서 이득이 있어도 전체 develop scan에 같은 비율이 적용된다는 뜻은 아니다. fixtures는 profile 종료 뒤 제거했고 cleanup receipt를 보관했다. 첫 시도는 compiler 완료 전에 실행해 exit127로 실패했으며 별도 로그로 보존했다.

## W25/W29: 작은 kernel 실측과 반례

[`r14-lookup-hit.swift`](../scripts/bench/r14-lookup-hit.swift), [`kernel-profile.json`](validation/r-backlog-2026-11-09/r14/kernel-profile.json)은 독립 expected ID/flat oracle를 먼저 실행하고 timed loop와 분리했다. 5 alternating fresh-process pairs이며 index build는 별도 기록했다.

| 작업 | 기준 median | 후보 median | 의미 |
|---|---:|---:|---|
| 196,608 sibling, 500 localized lookup | 0.456227s | 0.000011584s | 비교 49,214,786 → 1,508, 가까운 hint에서 큰 이득 |
| 같은 크기 random lookup | 0.301953s | 0.336541s | 비교가 조금 줄어도 후보가 더 느림 |
| 22 rectangles, 10k hit points | 0.000320959s | 0.000735333s | 작은 presentation에서는 hierarchy overhead |
| 200 rectangles | 0.0018875s | 0.000943917s | synthetic 중간 규모 |
| 2,000 rectangles | 0.0208773s | 0.00169679s | containment가 성립하는 stress |
| 20,000 rectangles | 0.284099s | 0.00806192s | 실제 앱 input 성능 주장 아님 |

실제 read-only GUI 표본 [`live-presentation-sample.json`](validation/r-backlog-2026-11-09/r14/live-presentation-sample.json)은 scanning 2,583,976 nodes, viewport 880×564, depth3, presentation 22개다. 한 표본이며 항상 작다는 증거는 아니다. 현재 `TreemapView.hit`은 flat last-match이고 `paint.rect_index`는 paint/tooltip/AX용 path→rect dictionary다. MapRectIndex라는 계층 hit-test 자료구조가 이미 있는 것으로 부르지 않는다.

W25 kernel은 current Mac reverse-paint, opacity/interactivity/identity gate를 보존했다. 자식 rectangle이 부모 밖인 반례에서는 flat=child, hierarchy=nil이다. 실제 앱이 그 상태를 만든다는 증거는 아니지만 transition/reparent 중 containment를 증명하거나 fallback을 마련해야 한다. 비교의 시간에는 index build/배열 추가 메모리가 포함되지 않는다.

W29 duplicate siblings `[zero,same,other,same]`에서는 first-match=1, hint-match=3이다. 파일 시스템의 일반 directory name 유일성과 import된 tree의 유일성은 다르다. 기존 path/cache/cursor가 이미 줄인 조회량을 측정하고 호출 문맥의 hint locality를 확인해야 한다. 수십만 sibling의 localized microbenchmark만으로 기본 적용하지 않는다.

## 보관과 재현

실행 입력·해시·원시 출력은 [r14 evidence directory](validation/r-backlog-2026-11-09/r14/)에 보관한다. 최초 audit의 불필요한 record별 stat을 중단한 로그, parser 실패, helper API signature 실패, build 전 profile 시작 실패를 별도 보존했다. 완료 결과와 섞지 않는다. 연구 scripts는 production 경로 압축/정렬 정책을 도입하지 않는다. SDK와 production/test/probe source 해시는 manifest에 기록한다. W28 production reader 변경과 전체 release/TSAN/package 검증은 root 담당이며 이 문서의 8개 필터 테스트로 대체하지 않는다.
