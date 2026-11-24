# 성능 채택·종료 지연 추가 검수 — 2026-11-24

**종료 검사는 Mac 30회·Windows 30회와 Mac production visible 2회를 추가 통과했다. 과거 8초 지연은 재현되지 않아 원인은 미확정이다.** 성능 채택은 별도의 사전 조건·A/A·7입력 기준을 따른다. 종료 시간이 짧다는 결과를 스캔 처리량 채택으로 대체하지 않는다.

## 종료 검사의 차이

이전 5회 검사는 100만 파일 SNS를 반복해서 연 뒤 작은 문서로 교체하고 닫았다. 이번에는 같은 기존 입력 SHA-256 `0119c822debd8ea23ee0b6bad2ba4d38dc73f05ae5555dc3eb21958a19a9a205`를 사용해 세 조건을 나눴다.

| 조건 | 기존 184B 엔진 | 후보 168B 엔진 |
|---|---|---|
| 반복 대형 열기 → 작업 취소·작은 문서 교체 → 닫기 | 양쪽 각 5회 | 양쪽 각 5회 |
| 100만 파일 문서가 열린 상태 그대로 닫기 | 양쪽 각 5회 | 양쪽 각 5회 |
| 작은 문서에서 대형 import를 시작하고 pending/running 중 닫기 | 양쪽 각 5회 | 양쪽 각 5회 |

각 회차는 새 GUI 프로세스이며 최신 UI 소스의 QA 바이너리를 썼다. 각 네이티브 엔진은 독립 경로에 복사해 다른 앱과 구분했다. close 전에 독립 OS 종료 관찰자를 등록하고, **8초 제한·종료 코드 0·native 잔류 0**을 확인했다. import가 이미 끝났으면 in-flight 통과로 인정하지 않는다. GUI 부모가 끝난 뒤에도 늦게 태어난 native worker를 정확한 실행 경로와 creation token으로 점검하도록 harness를 보완했다. 원래 같은 native를 쓰던 다른 프로세스는 제외한다.

Mac 설치본과 전체 파일 hash가 같은 별도 production 번들로도 visible 창에서 100만 파일 상태 닫기 1회(166.01ms), 기존 반복·교체 시퀀스 1회(61.90ms)를 확인했다. 현재 설치 앱·기존 사용자 preview·Windows 의료 프로그램은 종료하지 않았다.

Windows의 최초 시도는 embedded Python의 module search path 설정 때문에 실행 전 실패했다. Mac 후보 최초 시도는 내가 profiling CLI를 GUI document backend로 잘못 지정해 usage 오류로 실패했다. 올바른 MacScanBridge로 바꾼 뒤 해당 세 조건을 다시 수행했다. 이 두 시도는 성공 회차에 넣지 않으며 원문도 보존한다. Mac의 한 차례 resource guard 중단 뒤 자원이 회복됐을 때 미실행한 조건을 이어 검사했다. 실패한 데이터를 통과로 바꾸지 않았다.

## 진단 오류 수정

기존 `diagnose_exit_timeout`은 메모리 통계 조회가 `ProcessLookupError`를 내면 `alreadyExited=true`로 끝냈다. 하지만 메모리 통계에 접근하지 못했다는 사실만으로 프로세스가 사라졌다고 판단할 수 없다. 이 경로는 필요한 OS 상태와 stack/dump 확보를 놓칠 수 있었다.

- Mac은 **ps 상태를 먼저 보존**한다. 실제로 PID 행이 없을 때만 disappearance로 기록하고, `E`가 있으면 exit-in-progress로 구분해 선택적 메모리 조회를 생략한다. sample의 성공/실패도 남긴다.
- Windows는 process snapshot의 존재를 별도로 확인하고 메모리 통계가 없어도 자체 PID의 MiniDumpNormal을 시도한다. 진단 API 실패가 원래 close timeout을 가리지 않도록 오류를 데이터로 보존한다.
- close timeout이면 진단 전후 OS witness와 이후 Popen return code를 별도로 남긴다. exit notification과 부모의 회수 완료를 같은 것으로 취급하지 않는다.

이 변경은 **검수 진단 코드의 결함 수정**이며 과거 제품 지연의 원인 수정이라고 주장하지 않는다. 실제 자체 sleep 프로세스에 의도적인 짧은 wait 제한을 걸어, 정상 metrics와 의도적인 metrics 포트 실패 두 경로의 sample/dump를 양쪽에서 검사한다. 제품을 멈추거나 메모리 압박을 인위적으로 만들어 장애를 재현한 시험은 아니다. 실제 `E` 상태 자체는 이번에도 관찰되지 않았다. 진단용 Python child는 stdout 준비 신호를 확인한 뒤 시험하도록 바꿔 시작 중인 프로세스를 sleep 상태로 오인하지 않는다. Windows CRLF도 같은 준비 신호로 처리한다.

후반의 Mac 고부하 환경에서는 기존 5초 sample 명령 제한이 여러 번 초과됐다. 부분 stderr도 보존하도록 보완했고, 별도 자체 child의 실제 수집을 대조했다. **샘플링 시간은 1초 그대로**, debugger 준비/수집/보고서 처리 전체의 별도 상한만 **15초**로 나눠 최신 경로의 정상·metrics 불가 두 경우 모두 비어 있지 않은 stack과 exit 0을 확보했다. **제품 close 합격 제한 8초는 변경하지 않았다.** 5초 수집 실패와 성공 원문을 함께 남긴다. Windows도 준비 신호를 포함한 최신 경로에서 실제 MiniDumpNormal 두 경우를 확인했다.

## 공간·부하 정리와 성능 기준

실행 중인 파일이 없는 자체 SwiftPM/Cargo scratch cache 네 곳을 정리했다. engine-before·선택된 profiling CLI·현재 production/QA 바이너리·원본 SNS·로그는 보존했다. 사용하지 않는 QA 앱 세 개는 ZIP CRC와 **13개 전체 파일 SHA-256**을 대조한 뒤 압축 보관하고 중복 디렉터리만 제거했다. 기존 사용자 preview는 보존했다.

Docker VM은 기존 승인에 따라 실행 경로·사용자·Docker.raw 소유를 확인한 뒤 watchdog/lease로 잠시 정지하고 재개했다. 다른 프로젝트의 빌드·브라우저 테스트·검색은 중단하지 않았다.

첫 기존 runner 진입은 CPU idle 30.75–70.94%, load1 11.03–12.82, 여유 공간 1.94–2.00GiB로 거부됐다. 공간 회복·작업 상태 변화 후 한 차례 더 검사했을 때 load/swap/pressure/disk는 통과했지만 CPU 5개 표본 중 하나가 65.25%여서 거부됐다(기준은 **모든 표본 70% 이상**). 이전 실패 원문은 그대로 보존했다.

추가로 60초 연속 안정 상태를 최대 240초 동안 기다린 뒤에만 동일 runner를 한 번 실행하도록 했다. 기존 CPU/load/pressure/swap/disk 기준, A/A 100쌍, 7입력 21쌍과 latency/CI/CPU/RSS 기준은 낮추지 않는다. 대기는 41개 표본을 남기고 `no_sustained_quiet`로 끝났으며 60초 연속 조건을 충족하지 못했다. A/A 100쌍과 정식 7입력 21쌍은 **시작하지 않았고**, 후보는 **배포하지 않았다**. 세 VM lease 모두 재개 완료를 확인했다.

다른 프로젝트의 빌드·브라우저 테스트·장시간 검색을 정상 종료할지 사용자에게 질문했고, 답변 전에는 그 작업을 중단하지 않는다. 공간 문제는 자체 캐시 정리와 후속 자원 회복으로 완화됐지만, 부하가 안정되지 않아 정식 성능 판정은 남는다. 과거 8초 지연은 이번의 새로운 정상 종료 결과만으로 원인이 확인됐다고 판정하지 않는다.

[기존 종료 조사](EXIT_DELAY_INVESTIGATION.md) · [UI 실제 입력 결과](GPUI_OS_INPUT_RESULTS.md) · [후속 원문](validation/performance-exit-recheck-2026-11-24/README.md).

## 작업 마감·리소스 반환 추가 확인

사용자 요청에 따라 고부하 상태의 추가 성능 실행을 중단하고, 정식 속도 판정·후보 배포 및 과거 8초 지연 원인 조사는 후속 작업으로 이관한다. 부하 측정 미실행을 성능 합격으로 기록하지 않는다. 검수 코드의 child 종료/wait, stdout·종료 관찰자·dump 핸들 close 및 VM finally 재개 경로를 확인했다. Mac 추가 점검에서 이번 검수용 프로세스 잔류는 없고 VM lease 세 개는 모두 resumed다. 설치 앱과 사용자의 기존 preview는 유지했다. Windows는 앞서 종료·예약 작업 제거를 확인했으며, 마지막 재접속은 인증 불가로 최신 상태를 다시 조회하지 못했다. 다른 프로젝트 작업은 중단하지 않았다.

[리소스 추가 확인 기록](validation/resource-return-2026-11-24.json).
