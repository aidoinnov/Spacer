# GPUI 남은 작업 후속 — 2026-11-24

사용자 입력을 방해하지 않는 hidden QA와 백그라운드 빌드만 사용했다. 기존 사용자 Mac preview와 분석/복구 자료는 유지한다. 이 문서는 [이전 콘솔 수정 결과](GPUI_BACKGROUND_RESULTS.md)의 후속이며, 이전 고정 증거를 덮어쓰지 않는다.

후속: [공통 노드 168B 개발 후보·검증·미배포 상태](NODE_STORAGE_RESULTS.md). 아래 184B/탐색 측정은 완료 당시의 고정 기록이다.

## 폴더 지정 재검사

`scan_rescan(path)`가 요청 경로를 무시하던 GPUI 구현을 교체했다. 입력 검증·문서 소유자 선택·진행 상태 갱신은 `ui/control_rescan.rs`가 담당한다. 화면 이동과 분석 명령을 분리해 현재 폴더·이동 기록을 유지한다. 현재 화면과 다른 주차 문서의 갱신도 지원한다.

Mac의 하위 트리 갱신과 Windows의 전체 소유 루트 갱신은 platform 어댑터에서 선언한다. Windows 전체 갱신은 하드 링크의 루트 단위 집계를 유지하기 위한 기존 엔진 정책이다. 응답에 요청 경로와 실제 범위를 함께 반환한다. 원래 루트 생략 의미와 완료 폴링은 [API 명세](MCP_API_REFERENCE.md#gpui-030-후속-계약-2026-11-24)에 기록했다.

기존 줄 단위 native 프로토콜에 JSON 문자열 명령을 추가했다. 줄바꿈/CR이 포함된 Unix 파일명이 별도 제어 명령으로 해석되지 않는다. canonical Swift codec을 Mac/Windows가 공유하며, 독립 복제본을 만들지 않았다.

Windows 실측에서 발견한 없는 경로의 Temp/TEMP 표기 불일치는 Windows 경로 어댑터에서 기존 부모의 canonical 표기를 보존하도록 수정했다. 잘못된 범위는 엔진 실행과 화면 상태 변경 전에 거부한다.

## 기능·회귀 결과

- 실제 Mac/Windows hidden GPUI와 native backend에서 지정 경로·생략 루트 재검사, 파일/없는 경로/범위 밖 거부, 화면 위치·이동 기록 유지, 강제로 분리한 주차 문서 갱신, SNS 재열기 후 offline 거부, 정상 종료·자체 fixture 정리가 통과했다. Mac은 줄바꿈 이름의 실제 폴더도 추가 검증했다.
- Rust Mac 29개/Windows 30개, 양쪽 QA/all-targets clippy `-D warnings`, Python 11개, 공통 경계와 canonical 43개 검사가 통과했다. Windows는 기존 부모의 대소문자 표기·없는 하위 경로·기존 경로의 불필요한 끝 구분자 회귀를 포함한다.
- 최신 Mac 100만 파일 문서 import 2회, 큰 import→작은 문서 교체/취소와 resize revision 보존을 두 번 실행했다. 종료 11.943ms/9.749ms, 자식 잔류 없음. 두 번째부터 종료 코드 0도 명시적으로 확인한다. 100ms 샘플 GUI RSS 최대 약 710–758MiB, 프로세스 트리 약 1.34–1.42GiB였으나 다른 호스트 부하/캡처 조건 때문에 이전 시험 대비 개선율로 사용하지 않는다.

## 확장 안정성 결과

| 항목 | 최종 코드 Mac | 최종 코드 Windows 132 | 이전 콘솔 수정 Windows 132 |
|---|---:|---:|---:|
| 반복 변경 시간 | 1,800.21초 | 1,800.38초 | 3,602.35초 |
| 회차 | 1,320 | 652 | 1,315 |
| 파일 변경 작업 | 105,600 | 52,160 | 105,200 |
| 파일·바이트·폴더 수 대조 | 3,085회 | 1,527회 | 3,074회 |
| hidden 렌더/캡처 | 4,682회 | 2,749회 | 5,580회 |
| GUI 종료 | 9.70ms | 84.85ms | 105.32ms |
| 별도 OS 관찰 종료 상태 | 0 | 0 | 0 |

Windows 추가 관찰은 최종 30분 2,201회, 이전 수정 1시간 4,965회다. 두 검사 모두 **보이는 backend 콘솔 0개, backend 최대 1개, 종료 후 잔류 0개**였다. Mac도 해당 자체 native 실행 경로에 잔류가 없었다. 60초 워밍업 후 Windows working-set 증가 최대는 각각 5.66MiB/7.24MiB로 64MiB 예산을 통과했다. private/GPU 메모리나 무누수 증명으로 해석하지 않는다. 자체 fixture 정리는 모두 통과했다.

1시간 검사는 재검사 API/Windows 경로 수정 전 콘솔·watch·frame 수정본이다. **최종 전체 코드의 1시간 검사로 표시하지 않는다.** 최종 코드는 양쪽 별도 30분 결과를 사용한다. 플랫폼 간 회차 차이는 탐색 처리량이나 OS 우열을 뜻하지 않는다.

기존 반복 harness가 종료 여부만 검사하던 부분도 발견했다. 장시간 GUI가 살아 있을 때 Mac kqueue의 `NOTE_EXITSTATUS`, Windows의 사전 확보 process handle을 등록해 세 실행 모두 종료 상태 0을 직접 확인했다. 향후 harness에는 종료 코드 0 검사를 추가했고, 보강한 양쪽 30초 smoke도 정상 종료를 확인했다. 긴 검사에서 사용한 이전 harness를 별도 보존했다.

장시간 harness의 마지막 root 복귀 검사는 주차 상태를 강제하지 않아 parked-watch 증거로 확대 해석하지 않는다. 마지막 짧은 검사는 snapshot의 canonical 경로로 이동하고 실제 focus를 확인하도록 보강했다. 감시를 끈 뒤 새 빈 branch를 만들고 진입해 **원래 문서가 주차된 상태를 강제**했다. 양쪽 모두 원래 문서의 watch 갱신 12회, branch 화면 유지, root 복귀 뒤 파일/바이트/폴더 oracle, 감시 중지와 종료 코드 0을 통과했다. Windows의 이 검사는 소유 root+표시 branch로 정상 backend 최대 2개, 콘솔 0·종료 후 잔류 0이었다.

강제 주차를 만들 때 감시 중지 중 생성한 폴더는 명시적 전체 재검사로 기준 상태를 동기화한 뒤 새 watch 이벤트를 검사한다. 현재 감시 켜기 명령은 watcher 등록이며 중지 중 OS 이벤트 재생을 보장하지 않는다. 첫 Mac 검사는 이 기준 동기화를 빠뜨려 빈 폴더 수가 1개 모자랐고, 그 실패도 보존했다. Windows 전체 갱신과 Mac 부분 갱신의 차이를 테스트 성공으로 숨기지 않았다.

## 최신 disktree 메모리 비교

Mac arm64에서 동일한 1,000분기·독립 1바이트 일반 파일을 사용했다. 각 엔진/worker 조합당 3회, 두 크기에서 총 18회다. 파일 수·폴더 수·할당 바이트가 모두 일치했고 자체 fixture는 제거했다. 양쪽 같은 macOS `proc_pid_rusage` V2 API로 **스캔 완료 시점**의 RSS를 읽었다. Swift의 checksum/정렬 전 값이다.

| 파일 수 | 우리 현재 엔진 worker 4 | disktree worker 1 | disktree worker 4 |
|---|---:|---:|---:|
| 100,000 | 28.27MiB | 15.16MiB | 15.53MiB |
| 1,000,000 | 207.17MiB | 113.94MiB | 114.44MiB |

각 칸은 3회 RSS 중앙값이다. 현재 엔진의 100만 파일 RSS는 이 입력에서 약 1.81배였다. 전후 최적화 효과나 모든 입력에서의 우열을 뜻하지 않는다. disktree는 원격 HEAD와 보관 소스가 같은 `9b18b272ca3c5a145f6ff58eaf89dc4d311eeaea`(0.11.0)임을 확인했다.

실제 컴파일된 저장 간격은 우리 `DiskNode` 184바이트(내용 size 177), disktree `Node` 88바이트였다. 우리 구조는 parent/id, logical/allocated, 추가 native metadata, 경로 표현 등을 보관하고 값 snapshot/reader를 유지한다. disktree는 중첩 children과 이름 중심의 다른 모델이다. 따라서 96바이트 차이는 구조의 증거지만, 그 전체를 기능 손실 없이 제거할 수 있다는 증거는 아니다. RSS는 할당기 캐시·런타임·reader도 포함한다. Windows 엔진/GUI, peak/private/GPU 메모리 비교도 아니다.

기존 memory probe의 폐기된 `DirectoryIOBudget.shared` 참조만 현재 리소스 소유자 `MacScanResources.directoryIO`로 연결해 별도 프로필로 빌드했다. 과거 고정 프로필과 결과는 수정하지 않았다. 별도 layout probe 소스/manifest도 보관한다. 자체 빌드·기능 검사 및 다른 프로젝트 부하가 겹쳐 도구의 순차 수집 원칙을 충족하지 못한 탐색 자료다. **속도 채택이나 정식 메모리 재대결 통과로 사용하지 않는다.** 원문 RSS와 별도 layout 관측을 보존하며, 정식 비교는 안정된 호스트에서 순차 재수집해야 한다. 현재 wrapper는 `scripts/bench/disktree-adoption/memory_probe.swift`로 남겼고 과거 frozen 소스와 분리했다.

후속 메모리 개선은 hot node/추가 metadata 분리와 이름·경로·ID 표현의 중복 비용을 먼저 계측하고, SNS/native 필드·하드 링크·불변 snapshot/watch 의미를 보존하는 저장 어댑터로 검토해야 한다. 단순 필드 삭제나 플랫폼별 UI 모델 복제는 하지 않는다. 변경 전후 같은 18회 메모리 oracle과 기존 7입력 성능/정확성 gate를 통과해야 한다.

## 정식 성능 판정 진입

Mac의 자체 빌드·기능 검사가 끝난 뒤 사전 계획한 `run_acceptance.py`를 실행했다. 원래의 5회 호스트 검사에서 CPU 유휴율 29.70–34.00%가 최소 70%에 못 미쳐 `host_not_admitted`로 종료했다. load1 7.92–8.09(한도 10), 메모리 pressure 1, swapout 증가 0, 디스크 reserve는 통과했다. Windows 장시간 검사는 별도 PC에서 진행 중이었다.

**A/A 100쌍과 표준 7입력 21쌍은 실행하지 않았다.** 기존 기준을 낮추거나 조용한 표본만 재시도하지 않았다. 현재 작은 입력·대형 단일 폴더·깊은 트리 등의 성능 회귀 해소 여부와 최신 disktree 처리량 비교는 여전히 미판정이다. 빌드 가능한 새 probe와 원문 환경 실패를 보존했다. GPUI 기능 수정 배포가 엔진의 성능 채택 통과를 뜻하지 않는다.

## 남은 OS 검수와 성능 판정

- 최신 production 설치본의 visible GUI 수동 검수는 남는다. 이번 실행은 사용자 입력을 방해하지 않는 hidden QA이며 이전 설치본의 visible 검증과 구분한다.
- 실제 앱 간 drag/drop, Windows 기본 앱 열기·클립보드, 양쪽 전체 휴지통 확인→재분석→OS 복원, 단축키·접근성 입력은 OS 입력 중단 조건 때문에 남아 있다. hidden renderer/API/port 검증과 구분한다.
- 과거 8초 종료 초과 1회의 원인은 남는다. 재실행 정상 종료는 그 원인을 증명하지 않는다. lifecycle harness는 이후 timeout 시 자체 GUI의 1초 stack sample을 정리 전에 보존하고, 종료 코드 0도 검사한다.
- 속도 비교는 기존 7입력·A/A·정확성·CPU/RSS gate를 유지한다. 호스트 기준 미달에서 수집한 속도를 채택 근거로 사용하지 않는다.
- 최신 disktree HEAD는 원격으로 확인했다. 엔진 메모리 비교는 런타임/할당기 캐시와 우리 추가 메타데이터·불변 reader를 포함한 실제 상주량이며, 순수 노드 구조 크기나 GUI 메모리 비교가 아니다.

## 설치·증거

Mac `~/Applications/Mac Space Sniffer.app`, Windows `%LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.3.0-GPUI`에 반영했다. 설치 전체 hash(Mac 9개/Windows 38개), Mac ad-hoc 서명, production QA 옵션 exit 64, ZIP CRC/전체 hash를 확인했다. Windows 바로가기 대상 경로는 유지한다. 기존 설치본 rollback과 사용자 preview/복구 자료를 보존했으며 자동으로 앞에 띄우지 않았다.

배포 ZIP/manifest는 `~/Downloads/SpaceSniffer-GPUI-0.3.0-20261124-scoped-rescan`, 프로젝트 링크는 `dist/releases/gpui-0.3.0-scoped-rescan`이다. 외장 공간 부족 때문에 이번 증거도 같은 Downloads의 `Evidence`에 보관했고 [프로젝트 증거 경로](validation/gpui-2026-11-24/remaining/README.md)는 symlink다. 이전 고정 증거는 그대로 보존한다. 서명 제거 후 code hash 대조는 자체 임시 복사본에만 수행했으며 설치본 서명은 유지한다.

[원문·source/artifact hash](validation/gpui-2026-11-24/remaining/README.md) · [남은 TODO](GPUI_MIGRATION_TODO.md).

## 2026-11-24 양쪽 후속

실제 파일 10만 개·양쪽 GPUI/native 100만 파일 SNS 메모리 비교, 양쪽 5회 대형 import/취소/교체/종료·독립 OS 종료 관찰과 후보 패키지 구성을 완료했다. [정량 결과와 현재 남은 조건](BOTH_PLATFORM_FINISH_RESULTS.md)을 따른다. 정식 속도 gate, 최신 설치본 OS 입력 전체, 과거 종료 초과 원인과 후보 설치는 여전히 미완료다.
