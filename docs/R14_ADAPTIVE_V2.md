# R14 adaptive-v2: directory count hint로 bulk 재시도 제한

2026-11-09. [v1 후보 감사](R14_CANDIDATE_PROFILES.md)의 원시 결과·소스 archive·manifest는 변경하지 않았다. 이 후속은 Mac I/O 선택 후보이며 Windows 동적 실행 증거가 아니다. 기존 W17/W23 원문([0x455be0](validation/windows-optimization-functions/0x455be0.txt), [0x405d30](validation/windows-optimization-functions/0x405d30.txt))의 큰 열거 버퍼·열거 metadata 재사용 원칙을 플랫폼 API로 대체한다.

**판정: internal `.adaptive` 후보는 유지하되 기본 `.posix`를 유지한다.** count hint로 wide 디렉터리의 bulk 시도를 없앴지만, 이번 실제 Scanner 측정에서 wide의 시간 회귀까지 제거되지는 않았다. 작은 flat fixture는 전 pair에서 개선됐지만 recursive는 변동이 컸다. 전체 볼륨에 대한 기본 활성화 근거는 부족하다.

## SDK 확인

로컬 SDK `getattrlist(2)`의 `ATTR_DIR_ENTRYCOUNT`는 UInt32이며 해당 디렉터리의 filesystem object 수다. synthetic items 및 `.`/`..`는 제외한다. 일부 볼륨은 필드를 지원하지 않으며, SDK는 특히 non-HFS [Plus] 볼륨에서 count 계산이 비쌀 수 있다고 경고한다. 따라서 count 조회를 무비용으로 취급하지 않는다. `getattrlist` options는 UInt32이고 `getattrlistbulk` options는 UInt64다. 최초 빌드에서 둘을 같은 형식으로 선언한 오류는 `initial-build.log`에 보존하고 수정했다.

구현은 다음 경계를 유지한다.

1. root만 `getattrlist`로 RETURNED_ATTRS + ENTRYCOUNT를 한 번 읽는다. 실패·누락·malformed·취소는 hint 없음이다.
2. hint가 있고 최대 4,096 이하인 디렉터리에서만 bounded bulk 수집을 시도한다. root가 크거나 hint가 없으면 기존 POSIX로 읽는다.
3. adaptive bulk는 child directory의 ENTRYCOUNT를 함께 요청한다. 디렉터리별 추가 count syscall 없이 transient stack `(id,hint)`로만 전달한다. Model/DiskNode/NodeTable에는 새 필드를 추가하지 않았다.
4. parent가 POSIX fallback되면 child hint는 없다. 후속 child도 보수적으로 POSIX를 사용하며 별도 count query를 추가하지 않는다. 큰 root 아래 작은 child의 잠재적 이득은 포기한다.
5. mount/firmlink 경계의 underlying-entry count는 mounted/redirected 대상의 count로 사용하지 않는다. 해당 hint는 버리고 기존 lstat 정책을 유지한다.
6. count는 race-prone hint다. 오래된 과소 count에도 기존 entry/memory cap과 all-or-nothing fallback을 유지한다. 과대 count는 POSIX 선택만 유발하고 노드를 누락하지 않는다. count와 실제 항목 수의 차이를 사용자 데이터 오류로 만들지 않는다.

기존 단일 scanner worker·정렬·symlink skip·issue·데이터 합계 정책을 바꾸지 않는다. 기존 public scan API는 그대로이며 override는 internal이다. private fd와 전체 수집 검증 후 append 정책도 유지한다. count 필드가 packed directory group에서 MOUNTSTATUS보다 먼저 온다는 SDK 순서를 적용했다. 추정 4MiB는 allocator hard limit가 아니다.

## 동등성·오류 회귀

[tests-final-root-count.log](validation/r-backlog-2026-11-09/r14/adaptive-v2/tests-final-root-count.log): **24 tests, 0 skipped, 0 failures**. NativeDirectoryMetadata 11개와 기존 Recovery/Progress/Scheduling 13개다.

- 실제 count와 entry 수 일치, parent가 받은 네 child count 각각 16 및 recursive scan 전체 root count syscall=1 검증.
- adaptive vs POSIX의 recursive 전체 DiskNode 필드·identity·times·attributes·합계·issues 비교. resource fork, 실제 F_PUNCHHOLE sparse, hidden, UTF8/NFD, hardlink 포함.
- count API 지원 안함/누락/malformed 및 4,100-wide hint에서 bulk calls=0 확인.
- stale root hint=0이 기존 4,096 cap에서 전체 POSIX fallback하는지 검증.
- child count 누락은 POSIX로 진행하고 데이터 의미가 유지되는지 검증.
- count 조회 중 취소, metadata 수집 취소/private fd close 및 mount 경계 hint 폐기 검증.
- v1의 bulk 오류/필드 누락/unknown type/firmlink/후속 batch 오류/denied/deleted directory 경계 유지.

## 실제 Scanner 측정

[`r14-native-scan-v2.swift`](../scripts/bench/r14-native-scan-v2.swift)는 현재 Core 소스를 `swiftc -O -whole-module-optimization`로 같은 module에서 빌드한다. [`r14-native-profile-v2.py`](../scripts/bench/r14-native-profile-v2.py)는 fixture별 5 alternating fresh-process pairs × 5 scans/process를 실행했다. scan-only 시간 합계의 process median이며 checksum 계산은 시간 밖이다. 모든 pair checksum이 일치했다. RSS는 checksum을 포함한 process peak다. fixture는 `/private/tmp`에 직접 생성하고 종료 후 제거했다.

| owned fixture | POSIX median (range), s | adaptive median (range), s | 개선 pair 수 | POSIX/adaptive RSS median |
|---|---|---|---:|---|
| flat 2,048 files | 0.068961 (0.063061–0.083055) | 0.040763 (0.036062–0.052099) | 5/5 | 9.14/10.53MB |
| recursive 32×64 files | 0.070335 (0.059403–0.093065) | 0.057095 (0.040440–0.150069) | 3/5 | 8.49/8.91MB |
| wide 4,100 files | 0.079759 (0.066894–0.091505) | 0.094930 (0.078864–0.153048) | 1/5 | 10.11/10.49MB |

[원시 JSON](validation/r-backlog-2026-11-09/r14/adaptive-v2/native-profile.json), [원시 출력](validation/r-backlog-2026-11-09/r14/adaptive-v2/native-profile.log). wide median은 약 19% 느렸으므로 cap-fallback **시도 비용 제거**를 **성능 회귀 해결**로 표현하지 않는다. root count 조회 자체 비용과 동시 host 활동 영향을 이 실험만으로 분리할 수 없다. 사용자 GUI scan/watch 및 다른 에이전트 작업이 동시 실행되었다. v1과 v2의 절대 시간이 달라진 원인을 새 코드로 귀속하지 않으며, v1과 v2의 서로 다른 실행 구간을 직접 개선율로 비교하지 않는다.

좁은 flat 디렉터리에서 syscall 감소의 실익이 반복 확인됐다. 다만 실제 전체 SNS에는 최대 196,608 siblings가 있으며 APFS 외 지원 범위, 변경 경쟁, count 조회 비용, POSIX 하위 subtree로의 보수적 fallback 비중을 더 확인해야 한다. 기본 활성화를 하려면 실제 파일 분포를 대표하는 fixture 또는 격리된 readonly 실행에서 end-to-end 비용을 다시 측정해야 한다. 현재 opt-in 후보와 재현 도구를 보존한다.

## 증거 보관

새 원시 파일·실패 빌드·소스 archive·SDK 사본/해시는 [adaptive-v2](validation/r-backlog-2026-11-09/r14/adaptive-v2/) 아래에만 추가했다. v1 source/hash/raw를 덮어쓰지 않았다. 본 후속은 TODO나 상위 완료 JSON을 변경하지 않는다. 전체 release/TSAN/packaging은 root 검증 범위다. GUI 제어·앱 종료·사용자 파일 수정은 수행하지 않았다.
