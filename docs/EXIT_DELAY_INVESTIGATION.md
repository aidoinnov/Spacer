> 추가 검수: [최신 UI·기존/후보 엔진 60회와 visible production 2회, 진단 오류 수정](PERFORMANCE_EXIT_RECHECK_RESULTS.md). 과거 원인은 계속 미확정이다.

# 종료 지연 재조사 — 2026-11-24

과거 8초 초과의 **원인은 미확정**이다. 같은 단일 폴더 100만 파일 SNS로 현재 후보를 양쪽 5회씩 추가 검사했고 정상 종료했다. 재발 진단 경로도 실제 별도 프로세스로 실행 검증했다. 재현되지 않은 과거 장애를 수정 완료로 표시하지 않는다.

## 확인한 사실과 범위

이전 `complete-lifecycle-before.log`에는 Mac의 `Popen.wait(timeout=8)` 실패와 terminate 이후 두 번째 8초 실패가 있다. 당시 stack/독립 OS 종료 이벤트는 보존되지 않았다. 이전 결과 문서는 OS `E` 상태 관찰과 메모리 압박을 기록하지만, 이것만으로 메모리 압박이 직접 원인이라고 확정할 수 없다.

Apple 공개 `ps` 구현은 `P_WEXIT`가 설정되고 아직 zombie가 아니면 `E`를 덧붙인다. 즉 종료 진행 상태를 뜻하며, 특정 UI 교착이나 Python wait 오류를 식별하는 코드는 아니다. 공개 소스의 의미를 확인한 것이며 당시 설치 OS의 정확한 kernel stack을 복원한 것은 아니다. [Apple ps state 구현](https://github.com/apple-oss-distributions/adv_cmds/blob/main/ps/print.c).

과거 traceback은 Python의 kqueue 대기 경로를 가리킨다. CPython 구현도 해당 이벤트가 제한 시간 안에 오지 않으면 timeout을 발생시키므로 traceback 위치만으로 Python 버그라고 판단하지 않는다. [CPython subprocess 구현](https://github.com/python/cpython/blob/v3.15.0/Lib/subprocess.py).

최근 5회 검사는 분기 폴더 1,000개인 SNS였지만 과거 실패는 **단일 폴더에 100만 파일이 몰린** `complete-scale-flat.sns`였다. 입력 차이를 확인하고 과거 파일 그대로 SHA-256 `0119c822debd8ea23ee0b6bad2ba4d38dc73f05ae5555dc3eb21958a19a9a205`를 양쪽에 적용했다. UI는 같은 소스의 frozen QA frontend, native는 선택한 168B 후보다. 과거 실패 당시 바이너리/호스트 메모리 압박까지 동일 재현한 시험은 아니다.

| 추가 단일 폴더 검사 | Mac | Windows 132 |
|---|---:|---:|
| 회차 | 5/5 통과 | 5/5 통과 |
| close 요청부터 종료 확인 | 42.05–77.70ms | 148.27–194.17ms |
| Popen / 독립 OS 관찰 종료 코드 | 모두 0 / 0 | 모두 0 / 0 |
| 자체 native 잔류 | 0 | 0 |

각 회차는 대형 SNS 최초 열기→추가 2회 열기→대형 작업을 작은 2파일 SNS로 교체→이전 작업 취소·새 작업 완료→resize revision 보존→종료다. 8초 회수 기준은 유지했다. 이 닫기는 작은 문서로 교체한 뒤 수행하며, 거대한 문서를 열린 채 즉시 종료하는 모든 경우를 대신하지 않는다.

현재 native 종료 코드는 quit/cancel 전송 후 별도 thread에서 회수한다. 수동 frame arena 해제 누락도 앞선 작업에서 수정했지만, 그 수정이 과거 한 번의 종료 초과를 일으킨 직접 원인을 제거했다는 인과 증거는 없다.

## 재발 자료를 확보하는 방법

공통 lifecycle harness는 close 전에 독립 OS 종료 관찰자를 등록한다. Mac은 kqueue exit status, Windows는 확보한 process handle을 사용한다. Popen의 자식을 별도로 reap하지 않는다. timeout이면 자체 PID의 상태와 Mac 1초 sample / Windows MiniDumpNormal을 먼저 보존하고 정리한다. 정상 종료·PID 재사용 구분·자식 잔류 검사도 유지한다.

`check-exit-diagnostics.py`를 추가해 양쪽 실제 진단 API를 시험했다. 비밀 환경 변수를 물려주지 않은 **자체 Python sleep 프로세스**에 의도적으로 0.2초 wait 제한을 적용하고 다음을 확인했다.

- Mac: 실제 process state와 비어 있지 않은 stack sample, sample exit 0.
- Windows: MiniDumpWriteDump 성공과 비어 있지 않은 MiniDumpNormal 파일.
- 이후 시험 프로세스만 terminate하고 Popen/OS 관찰 결과 일치. Mac -15, Windows 1은 이 의도적 종료의 기대값이며 제품 오류가 아니다.

이는 진단 어댑터의 실동작 시험이다. 제품을 인위적으로 멈추거나 과거 장애를 재현한 것으로 표시하지 않는다.

남은 확정 자료는 **실제 제품 종료 지연 재발 당시의 OS 종료 상태·stack/dump**다. 재현 없는 추정 수정이나 제한 시간 상향으로 원인 해결을 주장하지 않는다. [후속 검증 원문](validation/final-acceptance-2026-11-24/README.md), [전체 TODO](GPUI_MIGRATION_TODO.md).

## 추가 로컬 기록 대조

보관된 11월 23일 `space-sniffer-gpui` 진단 4건도 process/path/time과 대조했다. 두 건은 Preview QA assertion 스택이고 두 건은 별도 Completion QA 경로의 SIGABRT다. 설치된 `MacSpaceSniffer --scan ...complete-scale-flat.sns`의 8초 wait 실패와 직접 연결할 PID/stack 자료는 확보하지 못했다. 다른 진단을 해당 시험 원인으로 대체하지 않는다. 원문 요약은 최신 UI 패치 증거의 `historical-report-audit.json`에 있다.

11월 24일 실제 Space 검수의 Quick Look borrow panic은 별도로 재현·수정·양쪽 UI 패치 설치했다. [수정 전후 비교](GPUI_PREVIEW_REENTRY_RESULTS.md). 이것을 과거 8초 지연의 원인 해결로 표시하지 않는다.
