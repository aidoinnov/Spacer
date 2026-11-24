# R01/R02/R04 Windows runtime QA 준비

2026-11-09. **상태: PREPARED_NOT_EXECUTED.** 이 호스트에는 사용할 Windows runtime이 없고 PowerShell `pwsh`도 없다. Windows 프로그램 실행·PowerShell AST parse·GUI help 관찰을 수행하지 않았다. macOS에서 만든 문서/정적 검사 결과는 R01/R02/R04 통과 증거가 아니다. REA skill의 shipped-artifact 근거/관측·추론·unknown 구분을 적용했다.

## 고정 대상과 구문 출처

- EXE: `References/Windows/2.2.0.27/SpaceSniffer.exe`, 8,691,097B, SHA256 `192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6`.
- 동봉 User Manual PDF SHA256 `95b74f901e94b8cbe6c2b853d70bf0e20303782233245bc789cc988584d9f196`, section 11, pp26–28. [추출 원문](validation/r-backlog-2026-11-09/windows-harness/shipped-manual.txt).
- 실제 EXE embedded CLI help: file offset **0x33f7a9..<0x3400a7**. [raw bytes](validation/r-backlog-2026-11-09/windows-harness/embedded-cli-help.bin), [literal text](validation/r-backlog-2026-11-09/windows-harness/embedded-cli-help.txt), [출처·해시](validation/r-backlog-2026-11-09/windows-harness/embedded-cli-help-origin.json). 문자열 풀의 연속 payload이며 반복 문구는 공유될 수 있다. 정확한 runtime display 조립 순서는 관찰하지 않았다.

확인된 구문은 `help`, `scan "<path>"`, `load "<file>"`, `save "<path>"`, `export "<name>" "<path>"`, `autoclose`다. 여러 scan/load와 세미콜론 path list도 문서화되어 있다. `Grouped by folder`는 동봉 매뉴얼 예제의 case-sensitive export config 이름이다. 설정에 해당 이름이 없으면 runtime 실패로 남기고 임의 이름으로 대체하지 않는다.

**중요한 parser 차이:** EXE help는 기본 internal parser에 escape char가 없고 double quote가 기본 delimiter라고 명시한다. `@parser=OS`, `@delim=X/XY` 메타구문도 존재한다. harness는 기본 parser를 사용하며 path의 마지막 `\`를 CRT 방식으로 두 번 만들지 않는다. 따옴표·줄바꿈은 인자에서 거부하고 output path의 `;`도 거부한다. escape 지원이나 검증하지 않은 `--help`, `--cancel`, `--headless`를 발명하지 않는다. UI filter/stop 등은 auto save/export/autoclose를 해제할 수 있고, export가 없거나 취소되면 autoclose는 무시된다.

## Windows에서 수행하는 순서

repository 또는 아래 script 두 개와 frozen EXE를 Windows로 옮긴다. EXE를 실행하기 전에 Windows PowerShell에서 read-only parser 검사를 수행한다. 실행 정책을 script가 자동 변경하지 않는다.

```powershell
powershell.exe -NoProfile -File .\scripts\windows\Test-SpaceSnifferHarness.ps1
powershell.exe -NoProfile -File .\scripts\windows\Invoke-SpaceSnifferRuntimeQA.ps1 -Executable .\References\Windows\2.2.0.27\SpaceSniffer.exe -OutputDirectory C:\QA\sniffer-run-001
```

Mac가 생성한 SNS도 실제 Windows 왕복 대상에 포함하려면 다음과 같이 **복사할 입력**을 명시한다. 원본 파일은 읽기만 하고 output directory로 복사한다.

```powershell
powershell.exe -NoProfile -File .\scripts\windows\Invoke-SpaceSnifferRuntimeQA.ps1 -Executable .\References\Windows\2.2.0.27\SpaceSniffer.exe -OutputDirectory C:\QA\sniffer-run-002 -MacSnapshot C:\QA\inputs\mac-generated.sns
```

별도의 NEW directory로 `-HelpOnly`를 실행하면 proven `help`만 호출한다. help는 interactive이며 operator가 help와 QA 창을 닫아야 한다. stdout이 비어 있어도 help가 없다는 증거가 아니므로 스크린샷/표시된 내용을 별도 보관한다. 무인 완료가 불가능하면 timeout으로 기록한다.

script는 Windows 여부와 frozen SHA를 확인하고, 실행 중인 SpaceSniffer process가 있으면 중단한다. 기존 UI session이나 single-instance forwarding에 영향을 주지 않기 위해서다. output directory가 이미 있으면 중단하며, EXE는 새 directory의 private `bin`에 복사해 실행한다. 자동 설치·권한 상승·기존 프로세스 종료·사용자 데이터 삭제는 하지 않는다. 생성 fixture와 설정/결과는 그대로 보관한다.

## 자동화된 관찰 범위

[`Invoke-SpaceSnifferRuntimeQA.ps1`](../scripts/windows/Invoke-SpaceSnifferRuntimeQA.ps1), [`Test-SpaceSnifferHarness.ps1`](../scripts/windows/Test-SpaceSnifferHarness.ps1).

| case | 명령으로 관찰할 내용 | 완료 판정 한계 |
|---|---|---|
| 01 scan/save/autoclose | 작은 owned fixture → native-generated.sns | 파일 존재·exit만으로 field semantics 통과 아님 |
| 02 native load/resave | native-generated.sns → native-resaved.sns | byte equality를 무조건 요구하지 않음 |
| 03 native load/export | documented Grouped by folder text | native config/locale와 Mac 비교 조건 필요 |
| 04/05 trailing/case | 별도 process에서 path acceptance | RAM cache hit 테스트가 아님 |
| 06 duplicate same path | 같은 process의 두 view/save | manual은 scan once라고 설명. artifact 두 개만으로 실제 cache hit 입증 불가 |
| 06b path variants | 같은 process base/trailing/uppercase view | profiler/log/관찰로 공유 여부 판단. Windows case-sensitive directory에서는 다른 결과 가능 |
| 07 fresh explicit scan | 새 process로 명시적 scan/save | 재시작 자동 cache 유무를 판정하지 않음 |
| 08/09 optional Mac SNS | Windows load→native resave/text export | Mac로 되돌려 parsed tree/field 비교까지 해야 R02 왕복 |

fixture 기본 256 files + Unicode/emoji 파일 + hidden/readonly 파일, child folders 3개(하나는 empty)다. file 수는 1..10,000으로 제한한다. 실제 fixture manifest에 path·logical bytes·attributes·SHA를 기록한다. hardlink/sparse/ACL/reparse/large volume/원격 FS는 이 작은 fixture에서 검증한 것으로 처리하지 않는다.

## 로그와 실패 처리

- identity.json: 원본/staged EXE, frozen SHA, FileVersion/ProductVersion, Windows/PowerShell 버전, 시작 시각, sampling interval.
- 각 case의 command.json: argv와 실제 literal-delimited command line, expected output 경로.
- resources.jsonl: 200ms interval CPU ms, working set, peak working set, private/virtual bytes, handle/thread 수. 짧은 process는 sample이 없을 수 있고 sample 오류도 기록한다. working set/private bytes를 Mac footprint와 같은 지표로 취급하지 않는다.
- result.json/results.json: PID, exit code, elapsed ms, timeout/cleanup kill/harness error, 파일 size/SHA, missing artifacts. 모든 result는 observation_only이며 semantic pass를 자동 선언하지 않는다.
- stdout/stderr: GUI EXE라 비어 있을 수 있다. manifest.json은 모든 retained output의 SHA를 보관한다. `manual-required.json`은 미실행 수동 항목을 명시한다.

timeout/예외 cleanup은 harness가 시작한 Process만 Kill한다. **이 Kill은 원본 Stop/취소 테스트가 아니다.** native cancellation·remaining-export abort·autoclose ignored 결과로 기록하지 않는다. timeout/cleanup/error/누락 파일/nonzero exit가 있으면 harness exit2다. exit0도 의미 동등성 인증이 아니며 `results.json`을 검토해야 한다. setup/hash/입력 오류는 PowerShell 오류로 중단한다.

## R02의 실제 왕복 acceptance

native-generated.sns와 native-resaved.sns 및 원본 EXE identity/전체 로그를 Mac로 되돌린다. path separator/drive root, timestamp/attributes, cluster allocation, pseudo types4/5/6, encoding/version/filter를 분리한 independent parsed comparison이 필요하다. 서로 다른 platform에서 새 live scan한 allocation을 파일 단위로 동일하다고 가정하지 않는다. Mac-generated SNS는 이 script의 optional load/resave/export를 거쳐 다시 Mac decoder로 읽는다. origin input/output SHA를 연결하고 leaf/parent/size/type/attributes/tags 같은 실제 field 차이를 ledger로 남긴다. golden unit tests로 Windows 읽기 성공을 대체하지 않는다.

## R04/R06 수동 Windows 계획

1. QA process에 같은 path/끝 구분자/대소문자 variant view를 열고 cache root/worker 공유를 실제 프로파일러 또는 앱 log로 확인한다. 시간 감소·동일 SNS만으로 cache hit를 추정하지 않는다. 원본 [getRootData 0x43ec60](validation/windows-optimization-functions/0x43ec60.txt)는 agent GUID/path 비교 후 miss 경로에서 ExpandFileName을 호출하므로 caller 정규화도 관찰해야 한다.
2. fresh staging/bin의 실행 전 파일 목록, no-argument startup UI와 파일 접근을 기록한다. 아무 scan/load 없이 자동 복원되는지 관찰한다. 모든 profile/config 위치를 탐색하지 않은 상태에서 자동 영구 cache가 전혀 없다고 단정하지 않는다. explicit save는 persistent cache의 증거가 아니다.
3. 큰 **owned QA fixture**의 scan/export 도중 UI Stop을 누르고 event 시각·진행량·각 export output 존재/완결 여부·autoclose 동작을 기록한다. 실행 성공을 위해 이 action은 default 자동 suite와 분리한다. cancel CLI는 확인되지 않았다.
4. master scan 중 focus rescan, 같은 node/ancestor/disjoint focus, 두 view, close/root replacement, 직접 FS create/remove/rename/modify를 시간표로 수행한다. [R06 contract](R06_FOCUS_WORKER_CONTRACT.md)의 합계·취소·owner·stale merge oracle와 연결한다. static code가 동시 실행 가능한 구조라는 사실과 runtime 순서 관찰을 구분한다.

취소·focus·무인 no-argument 종료를 위한 검증되지 않은 CLI 옵션이나 UI automation 좌표를 script에 넣지 않았다. 현재 실행 가능한 Windows host가 생기면 parser 검사→작은 suite→수동 matrix 순서로 진행한다. 이 준비만으로 R01/R02/R04/R06 체크박스를 완료하지 않는다.
