# disktree 대비 남은 개선점 재확인 — 2026-11-21

최신 shared C3를 다시 빌드해 고정 disktree Core와 비교했다. **분기 처리량·메모리·reader 비용의 격차가 남아 있으며, 첫 폴더 하나로 전체 sibling group을 판정하는 admission 맹점도 실행 counter로 확인했다.** 이번 작업은 개선 대상의 재검증이다. production 알고리즘·기본 설치 앱은 변경하지 않았다.

## 최신 비교

고정 Core `9b18b272ca3c5a145f6ff58eaf89dc4d311eeaea`다. 로컬 reference의 tracked 변경이 없고, 실제 benchmark용 Rust production source가 이 reference와 byte 단위로 같은지 확인했다. 원격 최신 버전이라고 주장하지 않는다.

동일 실제 일반 파일, 내부 APFS, release executable, fresh process, warm/unknown cache 조건이다. 동일3회 워밍업 뒤21쌍, 2입력×7변형=294회와 별도 워밍업42회를 수집했다. 기존 root 앱은 watchdog/finally로 잠시 정지·복귀했고 다른 호스트 부하는 통제하지 않았다.

| 입력 | 설치0.2.1 기본2 | C3 직렬 | C3 기본2 | C3 실험4 | disktree1 | disktree2 | disktree4 |
|---|---:|---:|---:|---:|---:|---:|---:|
| flat20000 | 35.14ms | 35.46ms | 36.51ms | 35.93ms | 22.32ms | 21.50ms | 22.86ms |
| branches200x100 | 29.58ms | 37.51ms | 22.97ms | 17.58ms | 22.28ms | 14.54ms | 10.37ms |

C3 기본2/disktree4의 소요 시간 비는 단일 폴더 약1.60배, 분기 약2.22배다. disktree2와의 분기 비는 약1.58배다. 설정값2가 양쪽에서 완전히 같은 thread/work 단위를 뜻하지는 않는다. C3는 생성·접근 시각/추가 필드와 immutable progress reader 등을 유지해 작업량이 다르다. 언어·GPUI 자체 성능 또는 전체1TB 속도의 판정이 아니다.

이 입력에서 C3 기본2의 분기 p50은 설치0.2.1의29.58→22.97ms로 줄었지만, 단일 폴더는35.14→36.51ms였다. 이21쌍·2입력 결과는 전체 회귀 gate가 아니고 기존 A/A의 수집 변동 문제도 남아 있으므로 새 채택/회귀 확정으로 해석하지 않는다.

## 현재 메모리 비교

실제100,000파일·1,000폴더+root를 별도로 만들고 각 엔진을3쌍 교차 실행했다. 두 wrapper 모두 SDK `proc_pid_rusage` V2의 scan 직후 resident/footprint를, Swift digest/validation 전에 수집했다. SDK struct160bytes도 확인했다. RSS는 allocator/runtime와 Swift progress reader까지 포함하며 순수 노드 크기가 아니다.

| 변형 | scan 직후 RSS | footprint |
|---|---:|---:|
| swift-c3 | 38.86MiB | 37.14MiB |
| disktree-1 | 15.27MiB | 13.91MiB |
| disktree-4 | 15.38MiB | 14.03MiB |

C3의 scan 직후 RSS는 disktree4의 약2.53배다. 현재 C3의 실제100만 파일이나 GUI 전체 메모리까지 측정한 것은 아니다. 이전37MiB 표본과 직접 비교해 C3의 메모리 회귀를 주장하지 않는다: wrapper/build/수집 시점 조건이 다른 실험이다.

C3 `DiskNode`는 실행 중192bytes로 확인했다. disktree에는88bytes를 요구하는 Node layout test가 있고 full path를 보유하지 않는다. C3는 full path/name·명시적 ID/parent·logical/allocated·여러 optional metadata를 함께 보관한다. record 크기 차이와 path heap은 구조적 비용이지만 각 필드의 RSS 기여도를 분리 측정한 것은 아니다.

## 새로 확인한 admission 맹점

별도 사전 계획으로100개의1-file 폴더와100개의199-file 폴더를 만들었다. 파일20,000개·폴더201개·logical/allocated 합계는 같고, DFS에서 먼저 보이는 b199의 크기만 뒤집었다. 동일 워밍업3회 뒤15쌍×2입력×7변형=210회, 별도 warmup42회다.

| C3 기본2 counter | 첫 폴더1파일 | 첫 폴더199파일 |
|---|---:|---:|
| prefetch 수락 | 0 | 198 |
| 최대 directory sections | 1 | 2 |
| stat API 호출 | 101 | 101 |
| bulk API 호출 | 202 | 202 |

각 열의 모든15회에서 같은 counter를 확인했다. [Scanner](../Sources/SpaceSnifferCore/Scanner.swift)의 siblingAdmission은 부모별로 첫 폴더의 entryCount만 조사해 전체 그룹에 같은 enabled 값을 캐시한다. 첫 폴더가64…1024 범위를 벗어나면 뒤의 충분한 작업도 전부 inline이 된다. 기본4도 첫 폴더가 작을 때 prefetch0이었다. worker 수만 올려 해결되는 문제가 아니다.

단, 두 mixed 입력의 절대 시간 차이를 순서의 속도 효과로 단정하지 않는다. 두 번째 입력에서는 C3 직렬·설치본·disktree도 함께 느려져 호스트/fixture locality 변동을 분리하지 못했다. 활성화198회가 곧 throughput 개선을 뜻하지도 않는다: 이 수집에서 C3 기본2는 두 mixed 입력 모두 직렬 대비 p50 차이가 작았다.

또한 작은 폴더100개의 파일은 stat101(root1+file100)로 남았다. Native reader 최소16개 조건에서 작은 batch는 metadata 없이 이름만 반환하고, [append의 fallback stat](../Sources/SpaceSnifferCore/Scanner.swift)은 builder에서 실행된다. worker를 늘려도 이 부분의 I/O는 그대로 직렬일 수 있다.

## 개선 우선순위

| 우선순위 | 개선 대상 | 다음 작업과 통과 조건 |
|---|---|---|
| P0 | 첫 sibling 하나로 그룹 전체를 비활성화 | bounded multi-sample/개별 hint 기반 admission 비교. 혼합 입력에서 실제 eligible 작업이 수락되는지 확인하고 all-tiny·small1000 CPU 회귀를 막는다 |
| P1 | worker의 fallback metadata 미처리 | 작은/unsupported batch의 bounded stat 또는 small native bulk를 adapter에서 비교. builder는 ID/합산만 유지. 오류·취소·mount·첫 개요 지연과 CPU를 함께 검증 |
| P1 | full path·큰 node record | private compact store와 public DiskNode projection 분리 후보. 경로 지연 재구성·optional side table/packing을 각각 평가. 필드 삭제 없이 SNS/필터/CoW 계약과 실제100만 메모리·CPU를 확인 |
| P2 | names+metadata 중복 열거·정렬/대조 | 안전한 단일 수집/조립 후보. namespace 누락·중복·raw 이름/동적 변경 검증을 생략하지 않는다. 이전 unsafe bulk-first는 기각 상태 유지 |
| P3 | native64KiB scratch 반복 할당 | thread별 take/return 재사용 단독 비교. 재진입·동시 read·fallback·취소·thread 종료 수명 검증. malloc 줄었다고 속도 개선으로 간주하지 않는다 |

단일 폴더20,000개에서 C3 stat은1회(root), readdir API 호출20,003회, bulk43회, prefetch0이었다. 정상 입력을 매 파일 lstat하기 때문에 느리다고 설명하면 틀린다. readdir API 호출 수를 kernel syscall 수로 해석하지 않는다. 분기 입력은 readdir20,803회·bulk402회·stat1·prefetch198이었다.

우리 reader는 POSIX 이름 열거/정렬과 bulk metadata 및 namespace 대조를 모두 한다. disktree는 native iterator를 소비하고 thread-local64KiB buffer를 재사용한다. C3는 NativeDirectoryMetadata.read마다64KiB를 allocate/deallocate한다. 이중 열거/할당이 차지하는 시간 비율은 최신 CPU/allocation ablation 전까지 미확정이다. Node가 file full path를 보유하는 차이는 읽기 CPU와 메모리 양쪽의 후속 후보다.

거대 폴더 내부 cursor pause/resume은 여전히 미구현이지만 disktree도 실행 중 폴더를 쪼개는 구조가 아니므로 상대의 해결 기능으로 열세를 과장하지 않는다. C3의 개선점과 별도 설계 과제로 구분한다.

[사전 계획·원시값·소스 hash·fixture 정리](validation/disktree-recheck-2026-11-21/README.md), [실행 TODO](DISKTREE_RECHECK_TODO.md). 이번 확인을 전체 최적화 완료나 기본4 채택으로 표시하지 않는다.
