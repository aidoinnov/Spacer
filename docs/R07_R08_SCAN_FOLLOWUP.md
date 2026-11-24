# R07/R08 scan·watch 후속 감사

2026-11-09. 이 문서는 새 Mac 결함 수정과 로컬 회귀를 기록한다. Windows 실행 동등성이나 전체 R07/R08 완료를 선언하지 않는다. 상위 TODO·원본 evidence JSON은 이 단계에서 변경하지 않았다.

## 원본 근거와 플랫폼 경계

대상은 Windows SpaceSniffer 2.2.0.27 x64, SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`다. 아래는 retained 정적 pseudocode의 관찰이며 Windows 실행을 관측한 것이 아니다.

| 원문·Evidence | 관측 | Mac 적용 범위 |
|---|---|---|
| [snifChildrenPaths 0x455be0](validation/windows-optimization-functions/0x455be0.txt), `ev_c4d89b45eb9e66208230dc7096e4c43e638dd01b9af05b0b7fb33d1c50e56fda` | thread 취소 flag를 반복 검사한다. 디렉터리 open 실패를 10회/10ms 재시도하고 size=0·로그를 남긴다. 재스캔에서 기존 child에 rescanned 표시를 하고 enumeration 이후 미관측 child를 제거하며 취소 시 그 제거 경로를 중단한다. | POSIX lstat/opendir/readdir·st_blocks는 플랫폼 대체다. immutable partial tree의 부재를 확정 삭제로 처리하지 않는 publication/cancellation 정책을 보완했다. 원본 mutable node graph의 모든 중간 갱신을 동일 복제한 것은 아니다. |
| [deltaSize 0x405a00](validation/windows-optimization-functions/0x405a00.txt), `ev_e10ccfd2798296de840e3be50630adf85369438d8162a4dd4f73b75febf78557` | 파일 기여를 조상에 전파한다. | 경로별 기여 합산·하드링크 별칭 기여를 유지한다. 변경 수렴을 독립 full scan과 대조했다. |
| [elementChange 0x406d30](validation/windows-optimization-functions/0x406d30.txt), `ev_0261955c96dd41d366b16dd99d82ddb93d6095e970b18bada004c3a605e160ac` | action2 삭제와 조상 크기 제거, action3 metadata 갱신, action4 기존 node rename 후 nodeModified를 전달한다. | FSEvents는 Win32 old/new 쌍을 보장하지 않으므로 현재 parent 재검사와 unique identity rename 정책을 유지한다. 이 단계에서 이벤트만으로 직접 mutation하는 새 추측 경로는 넣지 않았다. |
| [SNS import 0x408ef0](validation/windows-optimization-functions/0x408ef0.txt), `ev_f761ae2de7fd81aac2ac871d8b655e0bce8eab6ea08ab6595b1b50d16334f3d0` | type4 free/type5 unknown은 drive parent를 요구하고 getter에서 가져온다. type6 missing은 별도 node를 만든다. | SNS type 규칙의 근거다. 접근 오류를 임의 free/unknown/missing node로 바꾸거나 APFS의 volume-used 차이를 Windows unknown 공식이라고 주장하는 근거로 쓰지 않았다. |

FSEvents의 loss/root-change/mount/unmount flag를 root 재검사로 바꾸는 것은 Mac 플랫폼 복구 정책이다. native API 의미 자체나 모든 Windows event-order 동등성을 위 정적 원문만으로 증명하지 않는다.

## 발견·수정한 결함

### 1. 취소된 scoped rescan이 completed로 되돌아감

기존 `ScanWork.run`은 취소된 subtree를 `SnapshotTree.replacing`에 넘겼다가 nil을 받으면 `original`을 그대로 반환했다. 그 original의 `cancelled=false` 때문에 실제 stop이 정상 완료처럼 publish됐다.

현재는 control/result 취소를 merge 전에 확인한다. 기존 tree가 있으면 그 whole-root baseline을 `cancelled=true/finished=now`로 반환한다. 초기 scan은 보유 baseline이 없으므로 현재 읽힌 partial을 보존한다. merge 도중 취소도 반환 상태에 반영한다. root lstat가 실패하는 scanner 조기 반환도 control의 취소 상태를 보존한다. UI도 완결 baseline을 보존한 취소라면 “이전에 완료한 결과를 유지합니다”로 표시해 최초 partial scan의 중지와 구별한다.

재스캔 취소 시 기존 tree를 보존하는 것은 immutable snapshot에서 미관측 child를 삭제로 확정하지 않기 위한 보수적인 플랫폼 정책이다. 그 rescan에서 새로 발견한 모든 metadata가 terminal tree에 병합된다고 주장하지 않는다. heartbeat에는 해당 실행의 진행량이 계속 보이고 snapshot은 보유 baseline일 수 있다. native syscall 자체를 강제로 interrupt하지 않는다.

### 2. 저장된 오류 500개 이후 scoped merge가 total을 낮춤

기존 merge는 scope 밖의 **저장된 문자열 수**와 새 subtree 오류 수만 합쳤다. total issueCount가 stored issues보다 클 때 생략된 오류의 소속을 알 수 없어 총수가 사라졌다.

`ScanWork.requiresRootRefresh`는 `issueCount > issues.count`를 확인한다. ScanService launch가 실제·공개 scope를 root로 승격하고 ScanWork의 직접 호출도 root를 재검사한다. SnapshotTree는 생략된 오류가 있는 입력의 scoped merge를 거절한다. 한계: 정확한 오류 분포를 저장하지 않는 현재 500개 정책에서는 root 재검사 비용이 필요하다. 생략 오류를 임의로 특정 subtree에 배분하지 않는다.

### 3. root-only 중간 결과가 focus/history/selection을 확정 삭제함

기존 ScanStore는 full rescan의 첫 root-only partial을 바로 projection에 넘겼다. NavigationState가 아직 재발견되지 않은 focus/history를 root로 수리하고 preservedFocus까지 덮어써서 terminal tree에 폴더가 남아도 원래 위치를 잃었다.

ScanStore는 같은 root의 마지막 오류 없는 완결 baseline을 명시적으로 추적한다. 해당 rescan의 중간 전체-tree publication만 보류하고 heartbeat·scanning/watch/scope/오류는 계속 반영한다. 현재 authoritative tags는 보유 tree에 overlay해 tag toggle/clear가 늦은 partial에 의해 복구되지 않게 한다. terminal tree에서 실제 삭제가 확인되면 정상 navigation repair를 실행한다.

초기 partial·새 root replacement는 계속 publish한다. canceled/failed/empty 결과를 새로운 complete baseline으로 등록하지 않는다. 기존 완결 tree와 동일 storage를 보존한 취소 결과만 기존 marker를 유지한다. disconnect/load/new-root/shutdown은 marker를 지운다. 기본값 `.shared`인 ScanService 주입 경계는 이 동작을 실제 actor/worker와 함께 제어해 검사하기 위한 경계이며 production 실행 모델을 바꾸지 않는다.

## 검증

[최종 focused + 기존 회귀 로그](validation/r07-r08-2026-11-09/final-recovery-tests.log): **16개 / skip0 / 실패0**. 이 표본의 실행 시간은 성능 측정으로 쓰지 않는다. 다른 팀의 소스 변경·빌드가 겹친 호스트였고 전체 TSAN/release/package는 상위 통합 단계가 수행한다.

- `ScanRecoveryTests` 6개: scoped/full rescan 취소의 baseline/cancelled 보존, 최초 partial 취소, truncated issue merge 거절·실제 root 재검사·공개 scope 승격, 실제 POSIX 접근 거부와 scan 도중 root 삭제, running scoped scan stop의 actor publish, 그 실행 중 loss event 이후 full-root 수렴과 frozen reader 유지.
- `RescanNavigationTests` 1개: 실제 scanner의 root-only progress를 gate에서 멈춰 focus/history/selection이 유지되는지 확인했다. 같은 시간 tag→동일 tag clear 후 terminal callback이 tag를 복구하지 않는다. terminal subtree 실제 삭제는 살아 있는 parent로 이동하고 인접 history를 합친다. root 전체 실제 삭제는 focus/selection/history를 비우고, 뒤이어 새 root 초기 scan은 root-only partial을 정상 publish한다.
- 기존 `RefreshLifecycleTests` 2개: 실제 FSEvents 48분기 burst, running 취소, promoted queue weak 해제, stale monitor callback·root recreation 차단, 이후 full refresh 수렴.
- 기존 `ScanSchedulingTests` 4개·`ScanProgressTests` 3개: queued 취소/교체/overflow, 늦은 old-root 완료, 가벼운 heartbeat와 부분 결과 취소의 회귀를 유지했다.

실제 POSIX permission fixture는 일반 사용자에서 실행해 통과했다. root UID는 해당 한 case를 skip하도록 했지만 이 실행은 skip0이다. 생성한 test 경로·권한만 바꾸고 정리했다. loss 이벤트 테스트는 실제 filesystem 변경과 monitor delivery seam의 `mustRescan=true`를 조합한 deterministic 복구 검사다. kernel buffer를 실제로 overflow시킨 실험이라고 표현하지 않는다.

초기 4개/6개 focused pass와 다른 팀 새 테스트의 compile-error 로그도 그대로 보존했다. 최종 판단에는 최종 16개 pass만 사용한다. Windows 실행·전체 볼륨 실측을 Mac 테스트 수로 대신하지 않는다.

## 여전히 미완료인 경계

R07 전체의 Windows 접근 거부·삭제·취소 중간 값 동적 대조는 미확인이다. 이후 [독립 정적 회계 조사](R07_SPACE_ACCOUNTING_FINDINGS.md)에서 live free/unknown 수식과 별도 treemap 표시 기여, DU missing의 부족분 회계 근거를 확보했고 순수 Core 경계에 적용했다. 현재 live scanner 자체는 접근 오류와 volume 메타데이터를 분리하며 가상의 용량 node를 합산하지 않는다. 같은 fixture의 Windows 실행 근거와 실제 볼륨 결과는 여전히 별도 판정해야 한다.

R08의 Windows notification action/modified-attribute별 실제 순서·rename 쌍·폭주/overflow 복구의 동적 대조도 미완료다. 이번 Mac 변경은 parent/full rescan의 보수적 수렴 경로를 검증했다. 직접 event mutation·원본과 동일한 concurrency/event-thread 구조를 구현했다고 주장하지 않는다.
