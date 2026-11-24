# R13 filter ID·modifiedAttributes 정적 재조사

2026-11-09. Windows SpaceSniffer 2.2.0.27 x64, EXE SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`을 별도 REA/Ghidra 12.1.4 세션으로 조사했다. 이 기록은 **정적 관측**이며 Windows에서 실제 변경·성능을 관찰한 기록이 아니다. production 코드를 변경하지 않았다. DU agent/형식의 별도 조사는 이 범위에 포함하지 않는다.

결론은 다음과 같다.

1. `TFileModifiedAttributes`를 size/name/time/attribute dependency bitset으로 해석하면 안 된다. 확인한 필드는 첫 byte의 변경 tag mask와 두 UnicodeString이다.
2. `isIncluded`의 반환 high byte는 이 payload에 저장된 metadata bit가 아니다. 포함 여부와 하위 트리 재필터 요청을 합친 16-bit 반환값의 일부다.
3. filter ID는 생성할 때 증가하는 32-bit instance generation 값이다. TM node의 ID 비교는 관측한 경로에서 paint의 palette/명도 선택에 사용된다. ID 같음만으로 membership 계산을 생략하는 cache-proof라고 해석할 근거가 없다.

## 보존 근거와 조사 경계

[완전 Evidence bundle](validation/r-backlog-2026-11-09/r13/native-evidence-bundle-complete.json)은 30개 canonical records를 가진다. [manifest](validation/r-backlog-2026-11-09/r13/manifest.json)에 binary/bundle/raw hash와 절차별 Evidence ID, producer/caller 범위를 기록했다. 중간 26개 bundle도 덮어쓰지 않고 보존했다. 읽기용 [함수 원문 폴더](validation/r-backlog-2026-11-09/r13/functions)는 pseudocode·assembly·resolved callers를 함께 둔다. pseudocode는 복원 결과이며 원본 소스가 아니다.

- literal `TFileModifiedAttributes` procedure search는 9개 이름을 반환했다. constructor 4개, View consumer와 this-adjusting thunk, RootData dispatch, Filter consumer, BaseThread dispatch다. 이 9개는 모두 dossier로 확인했다. search Evidence `ev_0a0515fb77793f02810fe504da6baff04a8a43fc3d4f3ebf88bd4a77e78b1f0b`.
- getter `getFilterID`의 resolved direct callers 6개와 field를 쓰는 nodeOperation/별도 wrapper를 확인했다.
- [LLVM 보조 assembly](validation/r-backlog-2026-11-09/r13/tmnode-allmembers.llvm.asm)는 `0x466200..<0x46bbc0`의 base `TTreeMapNode` named-member 영역을 원본 PE에서 별도로 disassemble했다. [11개 +0x58 후보](validation/r-backlog-2026-11-09/r13/tmnode-allmembers-field58-candidates.json) 중 config field·vtable slot을 실제 TM ID와 구분했다. 이 displacement 검색은 alias/type-complete binary-wide reference 증명이 아니다.
- Ghidra는 unresolved indirect/virtual flows를 완전히 복원하지 않는다. 특히 paint dossier의 high p-code view는 `truncated=true`다. 아래 paint 결론은 보존한 complete assembly/pseudocode에서 해당 비교와 분기를 확인한 것이며 p-code 전체 완전성을 주장하지 않는다.

## 1. modifiedAttributes의 실제 필드와 producer

| offset | 관측한 저장·사용 | 확인 수준 |
|---|---|---|
| `+0` | char/tag 변화 mask. tag ctor는 입력 DL을 그대로 저장하고 `isIncluded`는 include/exclude tag mask와 교차시킨다. | byte load/store 및 tag reader 관측 |
| `+8` | UnicodeString. rename producer에서 이전 path segment를 전달한다. | constructor 및 elementChange 호출 인자 관측 |
| `+0x10` | UnicodeString. rename producer에서 새 path segment를 전달한다. | constructor 및 elementChange 호출 인자 관측 |

두 8-byte 문자열 필드를 포함하는 24-byte 형태는 이 x64 ABI의 필드 배치로 추론한 크기다. padding 전체가 초기화된다고 주장하지 않는다. 이 구조에 size/mtime/attrs별 dirty bit가 별도로 저장된다는 증거는 없다.

| constructor | 초기화와 resolved producer | Evidence |
|---|---|---|
| [0x409f70](validation/r-backlog-2026-11-09/r13/functions/0x409f70.txt), `(char)` | byte0 = 입력 byte. 두 문자열은 아래 `%i` formatter를 통해 `"0"`으로 만든다. resolved caller는 `setTag` 0x408300 하나다. | `ev_d30a79263a24c171824a1bd0d03f2c2d16290f44ab2965887cb02681bca2cdbd` |
| [0x40a050](validation/r-backlog-2026-11-09/r13/functions/0x40a050.txt), `(UnicodeString,UnicodeString)` | byte0=0, 두 문자열에 전달받은 old/new segment 저장. C1 wrapper [0x409d10](validation/r-backlog-2026-11-09/r13/functions/0x409d10.txt)를 거쳐 `elementChange` 0x406d30 action4에서 사용한다. | `ev_9eac2c16ce10041e9f197c6d26875be9968f061d55be175faa17217cc80d4507`, `ev_6217913f5ae446f2a0cc9127009d0fc6642a14f57d4193b7c83486a158d4f975` |
| [0x40a120](validation/r-backlog-2026-11-09/r13/functions/0x40a120.txt), `()` | byte0=0, 두 문자열은 `"0"`. resolved callers는 elementChange/ADS scan/View nodeAdded/DU snapshot scan/filesystem scan/updateFiltering의 6개다. | `ev_e995b8d5b680e3ad2e2311799f63c6b6357107b24056b863060e113d0b3fe3a4` |

**기본/tag ctor의 문자열은 빈 문자열이 아니다.** 포인터를 0으로 초기화한 뒤 다시 formatter로 값을 넣는 부분까지 확인해야 한다.

- `read_bytes(0x73d270,16)`의 bytes는 `25006900000000000000000000000000`, UTF-16 `L"%i"`다. Evidence `ev_99f65a08cd013bc3ea576d4caaa34fe1c3c1225375f917a5771409a7d85c3b4b`.
- tag ctor `0x409fb4`와 `0x409fe8`, default ctor `0x40a165`와 `0x40a199`에서 `XOR R8D,R8D` 후 `UnicodeString::sprintf`를 호출한다. 따라서 해당 variadic integer argument는 0이다.
- [sprintf 0x73a760](validation/r-backlog-2026-11-09/r13/functions/0x73a760.txt), `ev_5b59d52a61f70a3ef76665362562360e567f7f1c5895b59069e19b3b544bd831`은 `vsnwprintf` 길이 계산→UnicodeSetLength→출력 경로다. 정상적인 `%i` formatting 결과가 `"0"`이므로 두 문자열은 nonempty가 된다. 이는 Windows 실행 관측이 아닌 byte/호출 인자로부터의 정적 결론이다.

[setTag 0x408300](validation/r-backlog-2026-11-09/r13/functions/0x408300.txt)는 실제 tag 변경 때 payload mask를 `oldTag | newTag`로 만들거나 boolean 인자에 따라 0으로 만든다. 별도 인자로 부모들의 tag OR도 전달한다. [elementChange 0x406d30](validation/r-backlog-2026-11-09/r13/functions/0x406d30.txt)는 action3에서 `updateInfo` 뒤 default payload, action4에서 같은 node의 segment를 바꾼 뒤 old/new payload를 보낸다. 단순 이름 변경을 전체 node replacement로 수행하는 구조가 아니다.

[BaseThread 0x458fc0](validation/r-backlog-2026-11-09/r13/functions/0x458fc0.txt), [RootData 0x43e7d0](validation/r-backlog-2026-11-09/r13/functions/0x43e7d0.txt), [View thunk 0x42e760](validation/r-backlog-2026-11-09/r13/functions/0x42e760.txt)는 payload reference를 View consumer까지 전달한다. RootData의 등록 callback은 indirect call이므로 모든 외부 callback 구현까지 조사했다는 뜻은 아니다.

## 2. isIncluded 반환 high byte

[isIncluded 0x444870](validation/r-backlog-2026-11-09/r13/functions/0x444870.txt), Evidence `ev_44ab62e9796cf41b3fe755230060e64e5619330261eb5daaf9c43dff6801e216`에서 반환 후보는 다음과 같다.

| 반환 word | low byte | high byte | consumer에서의 의미 |
|---|---:|---:|---|
| `0x0000` | 0 | 0 | 포함하지 않음 |
| `0x0001` | 1 | 0 | 포함함; 이 반환에 의한 subtree refilter 요청 없음 |
| `0x0101` | 1 | 1 | 포함함; subtree refilter 요청 |

assembly `0x444894..0x4448ad`가 stack의 세 후보 `0x0000/0x0001/0x0101`를 byte 단위로 만든다. container 경로의 `DIL`은 `changedTagMask & (includeTagMask | excludeTagMask)`의 관련성을 담고, `R15B`는 두 문자열의 nonempty 여부에서 시작해 folder-pattern 경로에 따라 좁혀진다. `0x444dac..0x444dcc`에서 관련 tag 변화 또는 남은 name/folder 조건에 따라 `0x0101`을 선택한다. file 경로는 size/time/tag/attrs/ADS/folder/file mask를 평가해 포함 bool을 반환한다.

한정한 예로, **container이고 include/exclude tag와 positive/negative folder 조건이 모두 없는 경우** default payload의 두 `"0"`은 nonempty다. `0x4449dc..0x4449fc`에서 folder list count가 모두 0이면 `0x444dac`로 바로 이동해 `R15B=1`을 보존하고, `0x444dbb/0x444dbe`가 `0x0101`을 선택한다. 따라서 이 경우에는 default metadata payload도 보수적인 subtree 요청을 만든다. 모든 folder-pattern 조합에서 무조건 high byte가 켜진다고 일반화하지 않는다.

[View nodeModified 0x42df10](validation/r-backlog-2026-11-09/r13/functions/0x42df10.txt), `ev_bd32ce5fa651a996e908c393c55557f2bc468cafe8d1fd88cc679ae3b56505d0`의 `0x42df75 TEST AL,AL`은 포함 여부를, `0x42df7d CMP AX,0xff`/`SETA R12B`는 high byte 존재를 판정한다. 포함하지 않으면 현재 TM node 제거 경로로 내려간다. 포함하면 nodeOperation으로 크기/표시 트리를 갱신하고, high byte가 있으면 다음으로 나뉜다.

- filtering worker가 이미 실행 중이면 부모 또는 해당 filesystem node를 `addRefilterRequest`에 넣는다.
- 해당 worker가 없거나 취소 상태이면 `applyFilterTo`를 시작한다.

nodeAdded와 updateFiltering도 isIncluded를 호출하지만 low byte를 사용한다. 재귀 전체를 순회하는 updateFiltering에서 매 child마다 별도의 high-byte 재접수는 하지 않는다. 반환 word를 원본 metadata dependency flags로 그대로 복제하는 것은 잘못된 모델이다.

## 3. filter ID 생성·저장·비교

| 위치 | 확인한 역할 | 근거 |
|---|---|---|
| filter ctor `0x43f450` | 전역 `0x948180`의 dword를 읽고 `INC EAX`, 다시 전역과 instance `+8`에 저장한다. 같은 expression으로 새 instance를 만들어도 이 경로가 실행된다. | [ctor](validation/r-backlog-2026-11-09/r13/functions/0x43f450.txt), `ev_e2e23f418185264ae44acbe9501d07f44afe307ca796f22726053acdf9b4d071` |
| getter `0x444830` | `MOV EAX,[RCX+8]` | [getter](validation/r-backlog-2026-11-09/r13/functions/0x444830.txt), `ev_64e8d83543ed9e7d344257f980c1b1d93f2bce0f0cdf7941d0158046cfb3c7e0` |
| TM init `0x4662d0` | 현재 View filter ID 또는 filter가 없으면 0을 TM `+0x58`에 저장한다. | [init](validation/r-backlog-2026-11-09/r13/functions/0x4662d0.txt), `ev_bba326630041a9b870b94556cadeeaa53fd48779e13a100d65d53b855cf05a0f` |
| nodeOperation `0x46af20` | 기존 node 수정, 새 node 생성, ancestor TM 복구 경로에서 전달받은 ID를 쓴다. ID 같음에 따른 early skip은 이 함수에 없다. | [nodeOperation](validation/r-backlog-2026-11-09/r13/functions/0x46af20.txt), `ev_9125775aa605b946a1bc9ae64fbeebbbc3b0d0cf2f290cfdc7b4c3253a05947f` |
| 별도 TM nodeModified/nodeAdded | 같은 ID 저장을 수행한다. direct caller가 없다는 것은 vtable 사용 부재의 증명이 아니다. | [0x46b290](validation/r-backlog-2026-11-09/r13/functions/0x46b290.txt), [0x46b320](validation/r-backlog-2026-11-09/r13/functions/0x46b320.txt) |
| updateFiltering `0x46a490` | 순회한 branch에 ID를 기록한다. early exit 조건은 thread 취소, 전달된 제외 subtree, 삭제 상태 등이다. ID 일치로 전체 판정을 skip하는 분기는 없다. exception/cleanup 경로에도 ID store가 있으므로 이 값만으로 모든 descendant의 성공 완료를 증명하지 못한다. | [updateFiltering](validation/r-backlog-2026-11-09/r13/functions/0x46a490.txt), `ev_d5c07cc4041406b299fe923f3f1b773254a933c04684613cadc0ea9dc689a7db` |
| paint `0x469770` | 현재 ID와 TM `+0x58`이 같은지 비교해 brightness lookup과 node palette/별도 config palette 선택에 사용한다. 불일치해도 paint 자체를 early-return하지 않는다. | [paint](validation/r-backlog-2026-11-09/r13/functions/0x469770.txt), `ev_f88eebd973836b7bf77ea4bb72c068337c44b5414a68355960eb197c191a57b3` |

counter `0x948180`의 resolved xrefs는 ctor의 read `0x43f49d`, write `0x43f4a5` 두 개다. xrefs Evidence `ev_67301b563356d7c3b53a91568a427ce2f9cd976415e2e921995c912052d98b76`, exact read instruction `ev_9c25cf5147478b3812db1e15f5653204c1d06b7d6dcc7abbcab761e8cbcd7012`를 보존했다. 이 machine increment는 32-bit이며 hash·전역 UUID·persistent cache key가 아니다. 초기 실제 값·동시 생성 thread-safety·wrap 시나리오를 실행 검증하지 않았다.

getter의 6개 resolved caller는 View nodeAdded/nodeModified/nodeRemoved, TM init/paint/updateFiltering이다. `resetCache` [0x46bb00](validation/r-backlog-2026-11-09/r13/functions/0x46bb00.txt)는 `+0x50` palette cache를 지우고 child reset을 호출하며 이 함수에서 `+0x58` generation을 초기화하지 않는다.

## Mac 적용 판단과 남은 unknown

- Mac의 projection revision, opaque source UUID, semantic filter key, snapshot storage proof는 서로 다른 역할이다. 원본 filter ID만 흉내 내서 `같은 ID → 결과 재사용`을 허용하면 metadata/하위 branch 상태를 증명하지 못한다. 현재의 conservative full fallback과 full oracle를 약화할 근거가 없다.
- 원본 modifiedAttributes를 모든 metadata bit의 완성된 change matrix로 바꿔 적지 않는다. Mac의 size/mtime/atime sparse delta와 name/path/creation/topology fallback은 해당 값·출처를 직접 검증하는 별도 플랫폼 자료구조 선택이다.
- updateFiltering은 recursive invocation **각각**에서 `GetSystemTimeAsFileTime`을 호출하고 그 부모의 child loop에서 공유한다. 원본이 전체 recursive pass에 timestamp 하나만 사용했다고 표현하면 과장이다. Mac의 한 evaluation에 고정한 `now`는 일관된 평가를 위한 Mac 정책으로 구분한다.
- 이번에 named constructors/readers와 resolved direct-call 경계는 확인했지만, 모든 포인터 alias·외부 callback·동시 event 순서·모든 UI 옵션의 동적 invalidate/skip 결과를 관찰한 것은 아니다. R13의 정적 오해와 주요 경계는 해소했으며 Windows 실행 대조 요구는 남는다.
- 이 범위에서 R11용 새 XML/export-script producer는 발견하지 않았다. nodeOperation의 getConfig/size mode와 paint palette 참조는 설정 소비자이며 modifiedAttributes producer로 분류하지 않는다.

새 tests/성능 측정/패키징을 했다는 주장은 하지 않는다. 원본 EXE는 읽기 전용으로 분석했고 child 소유 Ghidra target은 bundle 저장 후 정상 종료했다.
