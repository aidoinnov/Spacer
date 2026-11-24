# R07 free·unknown·missing 회계 원본 근거

2026-11-09. **정적 조사와 순수 Core 회계 경계까지 확보했다. Windows 실행과 전체 볼륨 동등성 검증은 수행하지 않았다.** 대상 SpaceSniffer 2.2.0.27 x64의 EXE SHA-256은 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`이다.

독립 child REA/Ghidra 12.1.4 세션에서 조사했고 그 세션만 닫았다. [새 Evidence bundle](validation/r-backlog-2026-11-09/r07-space/rea-evidence.json)은 62개 기록, [manifest](validation/r-backlog-2026-11-09/r07-space/manifest.json)는 bundle·원문·Core source hash를 보존한다. [판정 ledger](validation/r-backlog-2026-11-09/r07-space/findings.json)는 관측·Mac 설계·미확인을 구분한다. 반환 bundle의 `unknowns=0`은 REA 세션 등록 상태이며 아래 의미적 미확인이 없다는 뜻이 아니다.

## 확인한 수식

변수를 `T=drive size`, `F=total free`, `P=physical data aggregate`로 두면 원본 live 경로는 다음과 같다.

```text
used    = T - F
unknown = max(0, T - F - P)
```

| 책임 | 원문·Evidence | 직접 관측 |
|---|---|---|
| drive 초기화 | [0x404350](validation/r-backlog-2026-11-09/r07-space/0x404350.txt), `ev_eb5f6290a3101eca2bc4042102583e80d1aea832df5b5fee16451c1fdbab641f` | folder init 후 `Free Space`와 `Unknown (not yet scanned) Space` child를 만들어 drive +0x70/+0x78에 보관한다. |
| drive total | [0x43d550](validation/r-backlog-2026-11-09/r07-space/0x43d550.txt), `ev_aa998e8e2ee5c604b110a2bc5ddc8913f624a6e715b463331ff9ac54f786fce2` | DriveInfo constructor에서 API 성공 시 `GetDiskFreeSpaceExA`의 세 번째 인자 out을 +8에 저장한다. 초기값은0이다. cluster는 `GetDiskFreeSpaceA`의 sectors/cluster×bytes/sector다. |
| total 접근 | [0x404790](validation/r-backlog-2026-11-09/r07-space/0x404790.txt), `ev_306a2b73681ed3e96ab80b1224baa24018a2c7f8fe17e9f49c6c229991664391`; [0x43e360](validation/r-backlog-2026-11-09/r07-space/0x43e360.txt), `ev_c3ab744ac52d9f0d25b5493999f24842bc0fe59b6f3d93a8578ed2d54c333175` | realtime이면 RootData→DriveInfo cached total, offline이면 node virtual +0x50을 읽는다. pseudocode의 void 복원 오류는 [assembly](validation/r-backlog-2026-11-09/r07-space/asm-0x404790.txt)로 return register 경로를 확인했다. |
| free | [0x4047d0](validation/r-backlog-2026-11-09/r07-space/0x4047d0.txt), `ev_28e3436fc86738cd2e3ca8088488bce43ae70a9ba4ec99bff9dce249656c8326` | realtime은 경로에 `GetDiskFreeSpaceExW`를 호출해 네 번째 인자 out을 반환한다. 실패 시0이다. offline은 free child의 virtual +0x50 저장값을 읽는다. |
| physical data | [0x405a50](validation/r-backlog-2026-11-09/r07-space/0x405a50.txt), `ev_9aab2ecced615af5d9a5ab9cd3e1ad446cecc8cd402532e5643ddf2ab6cfb702` | base physical getter는 `max(0, node+0x38)`다. [assembly](validation/r-backlog-2026-11-09/r07-space/asm-0x405a50.txt)는 Max 결과가 RAX로 반환되는 경로를 보존한다. |
| unknown | [0x404880](validation/r-backlog-2026-11-09/r07-space/0x404880.txt), `ev_797bf10dc5e86a9160a21712420c9ab275d1b718d8c0b0b151d6f69cb2cc01c0` | realtime은 `(drive-free)-physicalData`를 계산한다. 음수면0이고 fine logging이 켜져 있으면 입력과 음수 residual을 기록한다. offline은 unknown child의 virtual +0x50 저장값이다. |
| used | [0x404cb0](validation/r-backlog-2026-11-09/r07-space/0x404cb0.txt), `ev_b6f86c6ebf32b0f279f3300708e6938894ed3c8b0be947dbd2c5978fdadc91b7` | `drive-free`를 반환하며 별도 음수 clamp는 이 함수에 없다. |

Microsoft의 [GetDiskFreeSpaceExW 명세](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getdiskfreespaceexw)에 따르면 네 번째 out은 디스크의 전체 free이고, 두 번째 out은 caller에게 사용 가능한 free다. 세 번째 total도 quota가 있으면 caller 기준으로 제한될 수 있다. 따라서 원본의 선택값을 사용 가능한 free나 물리 디스크 원시 길이와 동일시하지 않는다. 이 API 의미는 공식 문서이고 실제 어떤 quota 상태에서 실행됐는지는 미관측이다.

## 데이터 기여와 화면 기여는 다르다

Live `TFreeSpaceNode`의 logical/physical getter [0x40a710](validation/r-backlog-2026-11-09/r07-space/0x40a710.txt) / [0x40a750](validation/r-backlog-2026-11-09/r07-space/0x40a750.txt)는 모두0이다. `TUnknownSpaceNode`도 [0x40ad40](validation/r-backlog-2026-11-09/r07-space/0x40ad40.txt) / [0x40ad80](validation/r-backlog-2026-11-09/r07-space/0x40ad80.txt)에서 동일하다. Offline일 때만 base 저장값을 사용한다.

이 구조는 pseudo-space를 physical data aggregate에 다시 더해 unknown 수식을 순환시키지 않는다. 화면에서 필요할 때 다음 전용 경로가 값을 더한다.

- [DriveTreeMap physical 0x465610](validation/r-backlog-2026-11-09/r07-space/0x465610.txt), `ev_06957c885dd85d047d52b82f356d57da37a67e3291f9290c65fa2bfde2625e1b`: base treemap physical + visible free + visible unknown. realtime은 drive getter를 호출하고 offline은 해당 저장 child 값을 쓴다.
- [free TM logical 0x465e90](validation/r-backlog-2026-11-09/r07-space/0x465e90.txt), `ev_721aadbd01ba61262bd359fcbbe859bcf96fff0cc1915f774f1d119781ce1c18`: visible일 때 parent drive의 free 값, 아니면0.
- [unknown TM logical 0x46bef0](validation/r-backlog-2026-11-09/r07-space/0x46bef0.txt), `ev_844bf9d2cd9a897a009d7aa95c8fc8c40f644ad3a654ebce2325372ec1298485`: visible일 때 parent drive의 unknown 값, 아니면0.
- physical TM getter [0x465ee0](validation/r-backlog-2026-11-09/r07-space/0x465ee0.txt) / [0x46bf40](validation/r-backlog-2026-11-09/r07-space/0x46bf40.txt)는 virtual +0x40에 위임한다. constructor vtable 주소와 [free table+0x40](validation/r-backlog-2026-11-09/r07-space/free-tm-vtable.json) / [unknown table+0x40](validation/r-backlog-2026-11-09/r07-space/unknown-tm-vtable.json) 원시 pointer가 각각 logical getter를 가리키므로 구성된 이 타입에서는 같은 값이다.
- [View free-visible 0x42f6b0](validation/r-backlog-2026-11-09/r07-space/0x42f6b0.txt), `ev_b787d35ac70ba10bf16caa85d62cc9ad8cc59e8815ba528cebed994600244c8a`; [unknown-visible 0x42f6f0](validation/r-backlog-2026-11-09/r07-space/0x42f6f0.txt), `ev_d042952ed37a9012816a7d6f9e3f1dfa05b3bdbc33bd84b6608322279e39892a`: explicit enable byte가 켜져 있고 filter engine이 없거나 void filter일 때만 표시한다. non-void filter에서는0이다. 추가로 각 TM isVisible은 크기0이면 숨기고 base visibility를 검사한다.

free/unknown을 일반 파일로 추가하거나 항상 area에 넣는 것은 이 근거와 다르다. 이 단계에서는 UI 토글과 가짜 DiskNode를 자동 생성하지 않았다.

## 갱신·캐시 경계

`TFileSystemSnifAgent.isRealtime` [0x457190](validation/r-backlog-2026-11-09/r07-space/0x457190.txt)는1, `TDUSnapshotSnifAgent.isRealtime` [0x455860](validation/r-backlog-2026-11-09/r07-space/0x455860.txt)는0이다. Node.isRealtime은 root의 snif-agent virtual 호출을 따른다.

검사한 live getter 경로는 free를 호출 시점에 API에서 읽고 현재 physical aggregate로 unknown을 계산한다. 별도의 scan-finish 시점에만 unknown 숫자를 저장하는 경로가 아니다. 반면 total은 DriveInfo constructor의 cached 값이다. [DataCache.getRootData 0x43ec60](validation/r-backlog-2026-11-09/r07-space/0x43ec60.txt)에서 새 root entry를 만들 때 DriveInfo를 구성하는 호출을 확인했고, 직접 caller 검색에서도 constructor wrapper와 이 경로가 나왔다.

이는 검사한 경로의 갱신 조건이다. 전체 instruction의 모든 field writer 부재, paint 호출 빈도, Windows OS cache 동작, 매 frame의 원자적 일관성을 증명하지 않는다. total/free/data는 서로 다른 시점의 표본일 수 있다.

## SNS type4/5와 DU missing type6의 관계

기존 [SNS import 0x408ef0](validation/r-backlog-2026-11-09/r07-space/retained-0x408ef0.txt), `ev_f761ae2de7fd81aac2ac871d8b655e0bce8eab6ea08ab6595b1b50d16334f3d0`는 free4/unknown5의 parent가 drive인지 검사하고 이미 있는 해당 child를 읽는다. missing6은 별도 MissingDataNode를 만든다. live OS 수식과 offline 저장값은 별개다.

기존 [writer 0x408a80](validation/r-backlog-2026-11-09/r07-space/retained-0x408a80.txt), `ev_5600410e604de05627fef9296308e383109246c061535bfd5820f2ebea6d9efd`는 drive에는 drive size를, free/unknown에는 parent drive 전용 값을 기록하는 특수 분기가 있다. 후자는 cluster rounding한 physical을 기록한다. 이 함수의 전체 pseudocode에는 decompiler 경고가 있으므로 [새 assembly](validation/r-backlog-2026-11-09/r07-space/asm-0x408a80.txt), `ev_fe21708eeb0e48b308fa7b7d4447c70f8983281d34053de87946eccd26e576bf`를 대조했다. **cluster가0이 아니고 free/unknown logical 값이0이면 physical에 cluster 하나를 쓰는 분기**도 0x408d0c~0x408d2e에 존재한다. 일반적인 roundUp(0)=0을 가정해 이 byte 동작을 지우지 않는다. 이 특이 edge의 실제 Windows SNS 왕복은 아직 미실행이다.

`TMissingDataNode.newNode` [0x40a8c0](validation/r-backlog-2026-11-09/r07-space/0x40a8c0.txt), `ev_0047abae3074d6a5fd7a63f9c8c44934088c74fdef682b0e9a8db5ed242ed87b`는 `Files` 이름으로0 크기 node를 초기화한다. 확인한 resolved direct callers는 SNS import와 DU snapshot parser다. 이 검색만으로 모든 indirect caller 부재를 증명하지 않는다.

[DU parser canonical entry 0x4547f0](validation/r-backlog-2026-11-09/r07-space/0x4547f0.txt), dossier `ev_5e5050fe671bef819825466a308e010e94978ee427a5dd32b8d53de262db56f3`는 기록 크기를 `atoi64 << 10`으로 읽는다. 최종 folder component의 logical aggregate가 기록 크기보다 작으면 missing child에 차이를 넣는다. 더 세부 folder가 새로 생기면 상위의 기존 missing 기여를 차감하고0 이하에서는 제거하는 경로도 있다. 기존 bundle의 selector `0x455440`은 이 canonical function body 내부 주소였다. 이 dossier는 non-contiguous body ranges를 보존하며 enclosing span 전체를 code라고 가정하지 않는다.

따라서 DU의 missing은 부족한 상세 파일 정보를 대표하는 별도 회계이며, live 접근 오류 수나 volume residual과 동일한 값이 아니다. 실제 SNF/DU fixture의 Windows 해석과 runtime 양방향 왕복은 별도다.

## Mac Core 적용과 검증

[SpaceAccounting.swift](../Sources/SpaceSnifferCore/SpaceAccounting.swift)는 immutable 숫자 DTO와 수식만 소유한다. `SpaceAccounting(snapshot:offline:)`는 live + `isVolumeRoot` + root node가 있는 경우만 허용한다. snapshot nodes/합계/issueCount를 바꾸지 않으며 offline SNS type4/5/6 저장값을 OS 수식에 섞지 않는다.

- `systemUsedBytes=total-free`, `unattributedBytes=max(0,total-free-observedPhysical)`다. `unattributed`는 접근 거부 byte나 OS에서 영구적으로 잃은 byte라는 단정이 아니다.
- negative 입력은 거절한다. `zero_capacity`, `free_exceeds_total`, `observed_exceeds_used`, `residual_underflow`를 별도 진단하며, signed underflow가 가상의 큰 positive unknown으로 바뀌지 않게 한다. raw unclamped residual이 representable하지 않으면 nil이다. 이 overflow guard는 Mac 방어 경계로 원본의 불가능한 extreme 입력 wrap 동등성을 주장하지 않는다.
- `presentation(isVoidFilter:showFreeSpace:showUnknownSpace:dataPhysicalBytes:)`만 표시 기여를 계산한다. filter가 있으면 caller가 전달한 filtered data만 남는다. observed data에 pseudo-space를 두 번 더하지 않는다. presentation 합계 overflow는 nil로 보고한다.
- 현재 parsed `ScanFilter.isEmpty`를 void-filter 입력으로 쓰며, invalid-filter fallback과 whitespace/separator-only를 고려해 raw 요청 문자열만 검사하지 않는다. 실제 Hub 연결과 UI 표시 여부는 상위 통합 단계가 결정한다.

[4개 focused 회귀](validation/r-backlog-2026-11-09/r07-space/space-accounting-tests.log)는 실패0/skip0이다. 정상 식/모든 명시 표시 조합, filtered suppression, observed 초과·free 초과·capacity0 표본, negative 입력, Int64 residual/area overflow, live volume scope, offline type4/5/6 차단, issueCount와 residual의 독립성을 확인했다. 실제 성능 측정이나 전체 볼륨/Windows 실행 검증이 아니다.

이번 후속으로 R07의 static live 수식 unknown은 해소했지만, 실제 Windows의 접근 오류·스캔/중지·용량 차이와 Mac 전체 볼륨 합계의 동적 대조는 여전히 남아 있다. 새로운 UI 동작·모든 원본 기능 동등성·모든 OS 표본의 원자성을 완료로 보고하지 않는다.
