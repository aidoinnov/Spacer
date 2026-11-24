# R09 필터·탐색 후속 감사

2026-11-09. Windows SpaceSniffer 2.2.0.27 x64의 보존 정적 근거와 Mac 코드를 대조해 아래 결함을 수정했다. **Windows 실행 결과와의 동적 비교는 이 기록에 포함하지 않는다. R09 전체 원본 동등성 완료 판정과 별개다.**

원본 EXE SHA-256은 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`이다. 아래 원문은 Ghidra pseudocode이며 원본 소스 코드가 아니다.

| 확인한 차이 | 원본 근거 | Mac 변경 |
|---|---|---|
| `; ;`는 생성자에서 빈 토큰이 모두 버려진다. Mac은 문자열 자체가 비어 있지 않다는 이유로 별도 필터 경로를 사용해 빈 폴더 membership을 잃었다. | ctor [0x43f450](validation/windows-optimization-functions/0x43f450.txt), `ev_b340ec2251e42716776f166b0d7651f762b80ed76095edcbbc60f1516fa58b70` | `ScanFilter.isEmpty`는 공백을 제거한 비어 있지 않은 `;` segment의 존재로 판정한다. `;*.bin;;` 같은 실제 조건은 그대로 유지한다. |
| native age 한계는 초에 10,000,000을 곱한 FILETIME 단위이고 나이를 정수 초로 자르기 전에 비교한다. Mac의 `<1s`가 1.25초 전 파일도 허용했다. | age parser [0x440810](validation/windows-optimization-functions/0x440810.txt), `ev_983b78fe08d9e35a1841106a7858fccfbd7d161ddc9d52a53fedd2ffe5b2cb1f`; included [0x444870](validation/windows-optimization-functions/0x444870.txt), `ev_15b7982c3b5ee3b855894ab93563f7ca51e6e0afd0fd02ea8e78354a89962a41` | created/accessed/modified age를 `TimeInterval`로 비교해 Date가 표현하는 소수초를 보존한다. size 비교는 여전히 Int64다. |
| native age bound=0은 해당 방향의 비활성 sentinel이다. Mac의 `<0s`는 실제 제한이 되어 거의 모든 파일을 제외했다. size bound의 sentinel은 -1이므로 `<0b`는 유효한 0바이트 제한이다. | 같은 [0x444870](validation/windows-optimization-functions/0x444870.txt)의 age `!=0`와 size `>=0` 분기 | age의 0 한계만 nil로 정리한다. 양쪽 age 한계가 모두 비활성인 경우 `isTimeDependent=false`; 실제 남은 방향은 계속 time-dependent다. 첫 반복 한계가 이기는 기존 계약은 유지한다. |
| native glob은 LF/CR도 일반 non-NUL byte로 소비하며 실제 NUL 끝이 일치해야 한다. ICU `.`는 기본적으로 newline을 제외하고 `$`는 최종 newline 앞에서도 일치했다. dotAll만 켜는 보완도 CRLF를 한 번으로 소비해 `a??b`와 `a\r\nb`가 어긋났다. | 새 callee [0x445370](validation/r-backlog-2026-11-09/functions/0x445370.txt), `ev_e6e724f0acdf7867bcccff276281dcc2d3bf13731855ea28dd7c4d1cf676e18a`; outer lower-case/mask OR·negative reject [0x445050](validation/windows-optimization-functions/0x445050.txt), `ev_5821b63db0bab9ebb2054359e2130f0430de878255a70fb5f5c524270b4ec35a` | ICU 경로는 `\A…\z`와 `[\s\S]`/`[\s\S]*`로 만든다. printable ASCII literal/suffix 빠른 경로는 유지한다. |
| 같은 path가 재등장하면 inode가 달라도 old node로 간주해 tag·selection·focus/history를 새 파일/폴더에 붙였다. FSEvents 사이에 delete+create가 합쳐질 수 있다. | removed-node [0x42ee60](validation/windows-optimization-functions/0x42ee60.txt), `ev_488903a7a14ad961914c864e99d000cbe202220edf6befb327a3cf25fae15c5f`; native rename [engine contract](engine-contracts.json)의 `0x406d30`, `ev_0261955c96dd41d366b16dd99d82ddb93d6095e970b18bada004c3a605e160ac` | 양쪽 snapshot에 fileIdentity가 있고 서로 다를 때 같은 경로를 생존으로 인정하지 않는다. 제거된 selection/tag는 정리하고 focus/history는 생존 부모로 복구한다. old inode가 유일한 새 경로에 있으면 기존 rename 정책에 따라 그 경로로 연결한다. |

## 구현 경계와 비용

수정 파일은 [Filter.swift](../Sources/SpaceSnifferCore/Filter.swift), [TagPolicy.swift](../Sources/SpaceSnifferCore/TagPolicy.swift), [NavigationState.swift](../Sources/SpaceSnifferCore/NavigationState.swift)다. ProjectionSession 자체는 변경하지 않았다.

identity 판정은 Mac의 파일시스템 대응이다. native가 Swift path dictionary나 inode reconciliation을 사용했다는 뜻이 아니다. 같은 NodeTable COW storage는 identity 재검사를 생략한다. 변경된 table의 같은 ID/path는 추적한 노드만 대조한다. ID가 이동한 소수 경로는 기존 hierarchy lookup, 큰 이력은 bounded tracked-path 값과 순회 fallback을 사용한다. whole-tree identity/path dictionary나 가변 snapshot pool을 추가하지 않았다.

SNS처럼 한쪽 identity가 없으면 기존 path fallback을 유지한다. 기존 hard-link alias를 rename 대상으로 삼지 않는 정책도 유지한다. 같은 inode 값이 OS에서 재사용된 경우, 모든 coalesced event의 원래 순서를 복원하는 문제까지 해결한 것은 아니다.

## 검증

[필터 경계 회귀](../Tests/SpaceSnifferCoreTests/FilterBoundaryFollowupTests.swift)는 빈 segment/빈 디렉터리, 세 시간 필드와 기본 modified의 0.75/1/1.25초 경계, zero sentinel/반복 한계/size 0의 차이, future date, LF·CR·CRLF 및 실제 끝을 검사한다. retained `matches`에서 따로 옮긴 ASCII byte recursion oracle와 13개 패턴 × 10개 이름 = 130개 조합을 대조한다. production regex나 ASCII shortcut을 oracle로 재사용하지 않는다.

[path identity 회귀](../Tests/SpaceSnifferCoreTests/PathIdentityFollowupTests.swift)는 known same-path replacement의 tag·selection·focus/history 정리, cached lookup 유무, replacement와 동시에 존재하는 유일한 rename target, 양쪽/한쪽 identity 누락과 같은 COW table을 검사한다. 기존 Navigation/ReferenceContract/FilterScratch/ProjectionSession/OptimizationMatrix 회귀도 함께 실행한다.

최종 선택 실행 명령:

```sh
TMPDIR="$PWD/.build/tmp" swift test --filter 'FilterBoundaryFollowupTests|PathIdentityFollowupTests|ReferenceContractTests|NavigationTests|FilterScratchTests|ProjectionSessionTests|OptimizationMatrixTests'
```

최종 결과와 source hash는 [R09 검증 manifest](validation/r-backlog-2026-11-09/r09/manifest.json), [실행 로그](validation/r-backlog-2026-11-09/r09/final-tests.log)를 따른다. 이 선택 패턴은 다른 단계의 `RescanNavigationTests`도 포함한다. 전체 TSAN·release·패키징은 root 통합 단계의 별도 실행 결과를 따른다.

## 남은 판정

- Windows ANSI 변환은 원본 `patternMatch_internal`의 코드페이지/locale에 의존한다. Mac의 ICU Unicode case-insensitive/code-point 대응을 모든 Windows Unicode/대소문자 결과와 동일하다고 주장하지 않는다. ASCII newline·끝 경계는 새 원문과 별도 oracle로 확인했다.
- Date는 원본 raw FILETIME의 모든 100ns tick을 비트 단위로 보존하는 타입이 아니다. 소수초를 정수 초로 자르는 오류를 제거한 것이며, 극단적 시각/overflow 입력의 native wrap 전체를 재현한 것은 아니다. 일반 future date의 unsigned-age 판정은 기존 정책을 유지한다.
- invalid condition 뒤 UI 오류와 이전 적용 필터 유지, repeated first bound, 폴더·태그 상속/제외는 기존 Mac 회귀가 통과하더라도 실제 Windows UI와 같은 fixture로 대조해야 한다. 정적 ctor 경고/제어 흐름만으로 UI의 모든 오류 처리 순서를 확정하지 않는다.
- 삭제/rename/tag의 Windows 실제 변경 이벤트와 Mac FSEvents 순서는 R08/R09 동적 대조 대상으로 남는다. 이번 identity guard를 전체 event 동등성으로 확대하지 않는다.
