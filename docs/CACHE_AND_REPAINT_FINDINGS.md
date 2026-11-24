# 캐시·다시 그리기 추가 분석

대상: SpaceSniffer 2.2.0.27 x64. EXE SHA-256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`.

2026-11-08 정적 분석. 아래 주소와 Evidence ID는 [REA 근거](engine-rea-evidence.json)에 보관한다. 정적으로 확인한 호출 경로의 결론이며 Windows 실행 관찰은 아직 없다.

## 루트 캐시는 어떻게 맞추는가

`getRootData` (`0x43ec60`, `ev_6366c304a1eaf0fc40d12e92df991085f4c5e4639b71efb9ea0474e9775c77be`)는 목록을 순회하며 저장된 루트 path segment와 요청 문자열을 `UnicodeString::operator==`로 비교한다. 일치하면 agent GUID도 같은 비교로 확인하고, 기존 리스너 목록과 참조 수를 증가시킨다.

- 비교 함수 안에는 소문자 변환, 부분 경로·공통 조상 일치 판정이 없다.
- `ExpandFileName`은 cache miss 뒤 새 루트를 만드는 분기에 있다. 그러므로 함수 내부가 비교 전에 모든 요청을 정규화한다고 설명하면 틀리다. 호출자까지 포함한 대소문자·끝 구분자 동작은 원본 실행으로 대조해야 한다.
- filesystem agent의 `getGUID` (`0x4559f0`, `ev_ff81c0622cccc0dc08852b069fc6f24ba48dbaf40ab4f79e34779d07bbf2016e`)는 고정 문자열 `TFileSystemSnifAgent`를 반환한다.
- SNS agent의 `getGUID` (`0x4574e0`, `ev_a3e8bee60c15de6330bbd64cfeb4a679653ced0688a2dca828bfdae6374f60a4`)는 카운터를 증가시킨 식별 문자열을 반환한다. 같은 표시 경로만으로 live scan과 snapshot을 합칠 근거가 없다.
- Mac은 live filesystem만 ScanService에서 공유한다. URL 정규화·symlink 해석은 macOS 경로 대응이다. offline SNS는 이 캐시에 넣지 않는다.

캐시 생성 (`0x43e940`)은 락과 메모리 목록을 만들고, 소멸 (`0x43ea50`)은 스캔·감시를 종료하고 목록과 루트를 해제한다. **이 생성·조회·해제·소멸 경로에서는 자동 파일 저장/복원 호출을 확인하지 못했다.** 이것은 프로그램 전체에 영구 캐시가 없다는 증명은 아니다. 종료·재시작 파일 I/O 관찰은 미완료다.

## 변경별 재사용·갱신

| 사건 | 원본에서 확인한 경로 | Mac 반영과 경계 |
|---|---|---|
| 같은 live 루트 열기 | `getRootData` → 기존 루트 + listener/refcount | 기존 결과·태그 공유, 새 스캔을 시작하지 않음 |
| 마지막 뷰 해제 | `releaseNode` `0x43f230` → scan/watch 종료·목록 제거 | 마지막 구독 해제 시 메모리 entry 제거. 다음 구독은 새 스캔 |
| 전체 재스캔 | `TRootData::rescan` `0x43e4c0` → 스캔 종료, pool reset, 기존 root에서 새 작업 | 기존 entry를 유지하며 재스캔. master/focused 동시 실행은 아직 미구현 |
| 필터 입력 | `applyFilterTo` `0x42cba0`, `terminateFilterThread` `0x429020` | filesystem 재스캔 없이 캐시된 snapshot에서 projection 교체 |
| 태그 변경 | `setTag` `0x408300` → `fireNodeModified`; `reapplyFilterIfTagInvolved` `0x430400` | 공유 태그 변경을 뷰에 전달. Mac은 projection을 다시 계산하며 원본보다 넓게 재계산할 수 있음 |
| 파일 수정 | `TfrmView::nodeModified` `0x42df10` → 포함 판정, 노드 작업, 필요 시 refilter | FSEvents 부모 범위 재검사·병합. 직접 노드 mutation과 동일한 구현은 아님 |
| 설정 변경 | `configChanged` `0x427ff0` → repaint 및 root vtable `+0x98` | 현재 Mac 색상 cache key로 표현 설정 구분. 원본 테마·설정 전체는 미구현 |

설정 변경의 간접 호출은 drive/file vtable로 보강했다. drive vtable `0x926650`의 address point는 `0x926660`이고, `+0x98 = 0x9266f8`의 8 bytes는 `00bb460000000000`, 즉 `resetCache` `0x46bb00`이다. file vtable의 대응 슬롯 `0x9268c8`도 동일하다. `resetCache`는 색상 포인터 `node+0x50`을 비우고 자식에도 재귀 적용한다. 단순히 직접 caller 목록이 비었다는 이유로 사용하지 않는 함수라 판단하지 않는다.

## 일반 재배치와 확대 애니메이션

- `zoomFromTo` (`0x42bb40`)의 resolved direct caller는 `setNewFocus` (`0x428bb0`)다. xref에도 해당 코드 호출이 있다.
- `setNewFocus`는 기존 focus가 없거나 zoom 시간이 0이면 직접 그린다. **이전·새 노드 깊이가 같을 때도 직접 그리며**, 깊이가 다를 때 확대 애니메이션을 호출한다.
- 단일 클릭 `pnlGraphMouseDown` (`0x42b5c0`)은 선택 후 `DrawTreeMap`을 호출한다.
- 일반 repaint timer (`0x42c760`)도 `DrawTreeMap` → `refreshBitmap` (`0x4295a0`)을 호출한다. 필요하면 root `setCoords` → `layout`, 이어서 `paint`한다.
- `setCoords` (`0x468320`)는 `+0xc0/+0xc2/+0xc4/+0xc6`에 사각형 좌표를 직접 기록한다. `paint` (`0x469770`)는 이 좌표를 읽는다. 이 경로에서는 이전·새 사각형 사이의 시간 보간을 확인하지 못했다.

따라서 현재 확보한 코드에서 확인되는 것은 확대 시 500ms 보간, 변경 노드의 색상 강조, DynaSmooth의 갱신 간격이다. 일반 재배치의 위치 보간은 미확인이다. Mac의 일반 재배치 애니메이션은 사용자가 요청한 UI 선택으로 구분한다. 다른 원본 버전·옵션·간접 경로까지 없다고 단정하지 않는다.

## 대기 중인 변경 범위

`addRefilterRequest` (`0x42e130`)는 요청을 뒤에 추가하고, 동일 노드 또는 조상이 덮는 자손 요청을 제거한다. `isOnPathTo` (`0x408260`)는 target의 부모를 올라가며 ancestor와 비교한다. `getRefilterRequest` (`0x42c9e0`)는 앞에서 꺼내며 detached node를 건너뛴다.

Mac의 기존 구현은 서로 다른 변경 경로를 공통 조상 하나로 합쳐 과도한 재검사를 했다. `RefreshQueue`는 원본의 중복·조상 packing과 독립 분기 FIFO를 FSEvents 경로에 적용한다. 새로 생기거나 삭제된 폴더는 가장 가까운 cached ancestor를 재검사한다. 해당 범위에 포함된 대기 항목만 지우고 다른 분기는 남긴다. **원본의 부분 refilter를 완전히 이식한 것은 아니며**, 변경 감지 뒤 읽을 filesystem 범위를 줄이는 플랫폼 적용이다.

## 선택·방문 기록의 수명

`treeMapNodeRemoved` (`0x42ee60`, `ev_488903a7a14ad961914c864e99d000cbe202220edf6befb327a3cf25fae15c5f`)는 제거 노드의 자손에 있는 focus를 부모로 옮기고, selection을 해제한다. 같은 자손을 가리키는 history도 부모로 바꾸고 연속 중복을 뒤에서부터 합치며 history index를 조정한다. `updateFiltering` (`0x46a490`)도 제거 시 이 함수를 호출한다.

Mac `NavigationState`는 원본 포인터를 snapshot 경로로 대응한다. 삭제·필터 제외 시 가까운 생존 부모를 찾고 history를 정리한다. 원본 rename은 같은 노드의 이름 변경이므로, Mac도 기존 TagPolicy와 같은 유일한 새 inode 경로 판정으로 focus·selection·history를 유지한다. 기존 hard-link alias나 모호한 새 경로로는 추측해서 연결하지 않는다.

## 남은 검증

- Windows 실행에서 경로 표기별 cache hit/miss, 재시작 자동 캐시, 일반 재배치 프레임 확인.
- 현재 Mac의 전체 projection 재계산을 원본의 focus-first 부분 refilter에 더 가깝게 전환.
- 원본 직접 변경 처리와 FSEvents 부모 재검사의 최종 결과·취소·오류 경계 대조.
- master scan과 focused scan 동시 실행.

이 호스트에는 Parallels Desktop과 `prlctl`이 있으나 `prlctl list -a`에 등록된 VM이 없었다. Windows VM을 새로 설치하거나 원본 실행을 관찰한 상태는 아니다.


## 최적화 재조사 보강

후속 [원본 최적화 조사](WINDOWS_OPTIMIZATIONS.md)에서 TTextBox의 dirty/font 치수 캐시, persistent tooltip의 dirty rebuild, repaint 병합/clip 검사, node recycle can과 busy 보호, thread pool의 event wait와 상한, deltaSize의 기존 정렬 국소 교환을 추가 대조했습니다. 기존 107개 근거는 이 파일의 링크를 유지하고, 새 근거를 포함한 139개 기록은 [별도 bundle](windows-optimization-rea-evidence.json)에 보관합니다. 원본 큐의 자료구조는 TList 중첩 비교이므로 고속 trie 큐라고 해석하지 않습니다.
