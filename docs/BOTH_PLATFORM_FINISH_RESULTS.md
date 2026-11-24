# Mac·Windows 남은 작업 후속 검증 — 2026-11-24

공통 168B 노드 후보를 **양쪽 실제 native 엔진과 hidden GPUI에서 검증했다.** 실제 파일 10만 개와 SNS 100만 파일의 수정 전후 RSS, 대형 가져오기/취소/교체/종료를 완료했다. 후보 패키지는 별도로 준비했다. 정식 속도 판정과 최신 설치본의 실제 OS 입력 검수는 미완료이며, 설치본은 기존 검증본을 유지한다.

## 같은 조건의 메모리 비교

184B/168B native만 교체하고 같은 frozen QA frontend·입력·API 렌더 순서를 사용했다. 각 조합 3쌍, 순서 교대, 매번 새 프로세스다. hidden 상태와 오류/파일 수를 확인하고 목록→트리맵 렌더 후 3초 안정화·0.5초 간격 3표본의 중앙값을 회차별로 계산한 뒤 3회 중앙값을 사용했다. 빌드와 수집은 순차 실행했다. 외부 부하가 있는 공유 호스트의 **탐색적 메모리 자료**이며 속도·최대 메모리·실제 화면 입력 통과를 뜻하지 않는다.

| 입력·측정 대상 | 기존 184B RSS | 후보 168B RSS | 감소 |
|---|---:|---:|---:|
| Mac 실제 독립 파일 10만 개, 엔진 probe | 28.08MiB | 26.59MiB | 1.48MiB |
| Windows 실제 독립 파일 10만 개, GPUI의 native | 52.84MiB | 51.46MiB | 1.38MiB |
| Mac SNS 100만 파일, GPUI의 native | 359.33MiB | 344.02MiB | 15.31MiB |
| Windows SNS 100만 파일, GPUI의 native | 351.14MiB | 334.77MiB | 16.38MiB |

실제 파일 fixture는 1,000분기·독립 1바이트 파일이며 양쪽 자기 fixture만 제거했다. Mac probe는 엔진 parallel4를 수정 전후 동일 적용하고 파일/폴더/할당 바이트·digest를 대조했다. Windows GUI 검사는 파일/폴더/logical 합계를 기대값과 대조했다. 두 측정의 실행 계층이 달라 OS 간 수치 우열 비교는 하지 않는다. 디스크 여유 때문에 이번에는 실제 100만 파일 fixture를 만들지 않았다. 기존 실제 100만 파일 자료와 SNS 결과를 혼동하지 않는다.

Mac 실제 10만 파일에서 최신 원격 HEAD와 동일한 disktree `9b18b272ca3c5a145f6ff58eaf89dc4d311eeaea`도 같은 수집에 포함했다. worker 1/4 RSS는 15.28/15.53MiB로 우리 후보보다 여전히 작다. 모델이 보관하는 metadata/reader가 달라 차이 전체를 제거 가능한 낭비로 해석하지 않는다.

같은 100만 SNS에서 GUI 자체 RSS 중앙값은 Mac 504.58→502.19MiB, Windows 390.55→390.42MiB였다. GUI는 같은 바이너리이므로 작은 차이를 Rust UI 최적화 성과로 주장하지 않는다. 원문에는 GUI/native별 RSS, Mac footprint, Windows private commit도 보존한다. GUI+native RSS 합은 공유 페이지를 중복 계산하므로 실제 고유 물리 메모리가 아니다. GPU 메모리·전 구간 peak는 측정하지 않았다.

## 대형 가져오기·교체·종료

`check-platform-lifecycle.py`가 양쪽 5회씩 통과했다. 회차마다 최초 100만 파일 SNS를 연 뒤 2회 더 가져오고, 대형 가져오기 중 작은 2파일 문서로 교체했다. 새 작업 완료·이전 작업 취소·watch 비활성·resize 시 snapshot revision 유지·hidden 상태를 확인했다.

| 항목 | Mac | Windows 132 |
|---|---:|---:|
| 통과 회차 | 5/5 | 5/5 |
| close 요청부터 종료 확인 | 71.47–105.14ms | 127.44–177.74ms |
| Popen / 독립 OS 관찰 종료 코드 | 모두 0 / 0 | 모두 0 / 0 |
| 확인한 native 자식의 종료 후 잔류 | 0 | 0 |

종료 요청 전에 Mac kqueue/Windows process handle로 독립 관찰자를 등록한다. 두 방식 모두 Popen의 wait를 대신하거나 프로세스를 reap하지 않는다. PID와 생성 시각 token으로 확인한 자체 native만 잔류를 검사한다. 실행 중 자체 프로세스 RSS 제한도 적용했다. OS별 측정·종료 관찰·진단은 `qa_process_metrics.py` 어댑터에 모았으며 제품 UI에 OS 분기를 추가하지 않았다.

과거 8초 종료 초과 원문은 두 번의 `Popen.wait(timeout=8)` timeout만 남아 있고 당시 stack/독립 OS 종료 관찰이 없다. **이번 재검사에서 재현되지 않았으므로 과거 원인은 미확정이다.** 새 lifecycle harness는 재발하면 정리 전에 자체 GUI의 Mac process state/1초 sample 또는 Windows MiniDumpNormal을 시도한다. 정상 종료 관찰은 양쪽 실제 검증했지만 timeout 진단 경로는 재발이 없어 실행 검증하지 않았다.

## 패키지·성능·실제 입력 상태

- [x] 공통 후보의 실제 파일 순회·양쪽 GPUI/native RSS 비교.
- [x] 양쪽 대형 가져오기/취소/교체/종료 5회와 OS 종료 코드 0 확인.
- [x] 양쪽 후보 패키지 구성·manifest/ZIP hash 검증. Mac 서명 검증, production QA 옵션 거부 확인. 설치 교체 전 단계의 후보로 보관.
- [ ] 정식 A/A 100쌍·7입력 21쌍의 기존 latency/CPU/RSS gate 통과.
- [ ] 최신 production 설치본의 실제 화면, 앱 간 drag/drop, 전체 단축키/접근성, Windows 기본 앱·클립보드, 양쪽 휴지통 확인→재분석→OS 복원.
- [ ] 과거 종료 초과 원인 규명. 새 정상 결과로 원인 해결 표시를 하지 않는다.
- [ ] 성능 gate 통과 후 양쪽 설치 교체·설치 경로 재검수.

이번 시작 때 기존 host admission을 다시 실행했다. CPU idle 32.77–40.10%(필수 70% 이상), pressure 2(필수 1)로 `host_not_admitted`였다. load/swap/disk 조건은 통과했고 **A/A·7입력은 실행하지 않았다.** VM/Folio/Steam/cmux 등의 사용자 작업을 임의 중지하거나 기준을 낮추지 않았다. 호스트 정리가 필요하다.

실제 OS 검수는 이전의 마우스·키보드 조작 중단 요청을 유지한다. 이번에 자동 조작 허용/직접 조작/보류를 질문했으며 답변 전에는 창 활성화나 OS 입력을 실행하지 않았다. 후보 QA는 자기 hidden 프로세스만 실행했다. 사용자 preview/복구 자료와 기존 설치/rollback은 보존했다. 자체 테스트 예약 작업은 종료 뒤 제거했다.

## 재현 도구와 증거

- `scripts/gpui-app/measure-gui-memory.py`: `--gui`, `--sns`, `--before-native`, `--candidate-native`, `--pairs 3`, `--expected-files`, `--output`. 실제 폴더는 `--input-kind directory`를 추가한다. QA 지원 바이너리만 사용하며 production에 QA 명령을 열지 않는다.
- `scripts/gpui-app/check-platform-lifecycle.py`: `--gui`, `--backend`, `--large-sns`, `--small-sns`, `--rounds 5`, `--output`.
- `scripts/bench/disktree-adoption/measure_memory.py`: `--baseline-swift-mode parallel4`를 추가해 후보와 동등 비교했다. 기본값 parallel2는 기존과 같다.

[원문·사용 harness·source/artifact hash](validation/both-platform-finish-2026-11-24/README.md). 최초 메모리 실행에 사용한 metrics/harness와 이후 directory/lifecycle용 버전은 구분해 보존한다. 이전 고정 결과는 수정하지 않았다. [전체 TODO](GPUI_MIGRATION_TODO.md), [저장 후보](NODE_STORAGE_RESULTS.md).

## 같은 날 추가 요청 후

사용자가 실제 입력 검수를 허용해 Mac 최신 설치본에서 폴더 선택·트리맵·뒤/앞/상위 단축키·휴지통 취소와 실제 이동을 확인했다. Finder가 만든 `.DS_Store`를 포함한 파일/폴더/logical oracle과 재분석 상태가 일치했다. 이후 Finder의 다른 사용자 작업이 관측돼 OS 복원·드래그 등은 입력이 겹치지 않는 시간을 확인 중이다. Windows 실제 입력 전체는 아직 실행하지 않았다.

정식 속도 gate를 새로 요청한 시점에 한 번 실행했지만 CPU idle 44.73–58.00%, load 기준 미달로 다시 host_not_admitted였다. pressure/swap/disk는 통과했다. A/A·7입력과 설치 교체는 하지 않았다. VM·cmux·folio-dev의 종료 범위는 사용자 응답 대기다. 읽기 전용 Docker 상태 조회도 약 60초 무응답이라 해당 자체 CLI만 종료했다. Docker daemon/VM은 건드리지 않았다.

과거와 같은 단일 폴더 100만 파일 SNS로 양쪽 5회씩 추가 정상 종료했고, 실제 별도 프로세스로 timeout 진단 경로를 검증했다. [과거 원인과 현재 확인 범위를 구분한 조사](EXIT_DELAY_INVESTIGATION.md)를 따른다.

## 실제 검수에서 발견한 추가 수정·설치

Mac Quick Look의 중첩 이벤트 루프에서 App borrow panic을 발견해 실제 입력으로 재현하고 공통 UI 호출 경계·접근성 초점을 수정했다. 양쪽 184B 엔진을 유지한 UI 패치 설치·실행을 완료했다. Mac OS 휴지통 복원도 완료했다. 승인된 VM 임시 정지 후에도 정식 속도 환경은 미달이며 168B는 미채택이다. [최신 설치·정량 결과와 남은 입력 검수](GPUI_PREVIEW_REENTRY_RESULTS.md)가 현재 상태를 설명한다.
