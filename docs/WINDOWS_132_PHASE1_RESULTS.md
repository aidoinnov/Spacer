# 132 Windows 실기기 검증 — 1단계, 2026-11-23

후속: 사용자가 실제 창과 동작을 완료 기준으로 요청해 [Windows 앱 v0.1까지 구현·실행 검증](WINDOWS_APP_RESULTS.md)했다. 아래는 공통 엔진만 검증했던 이전 단계의 기록이다.

**공통 엔진 Windows 호환성·실제 파일 I/O 검증은 통과했다.** 기존 Mac 기능·GUI 검증과 이번 공통 엔진 실기기 검증을 묶은1단계는 마무리할 수 있다. Windows 앱 전체 출시 완료나 Mac 성능 gate 통과를 뜻하지 않는다.

[정량 결과·SHA](validation/windows-132-2026-11-23/summary.json) · [debug 원자료](validation/windows-132-2026-11-23/debug.log) · [release 원자료](validation/windows-132-2026-11-23/release.log) · [Mac 기능 검증](SCAN_FINAL_GATE_RESULTS.md) · [남은 성능 gate](SCAN_PERFORMANCE_2026_11_23.md)

## 무엇을 실행했나

132번 PC(192.168.0.132, Windows10 build19045, AMD64)에서 Swift6.2.4 `x86_64-unknown-windows-msvc`로 독립 `SpaceSnifferScanEngine` 패키지를 직접 빌드하고 실행했다. Mac production과 같은 공통 엔진10파일은 변경 없이 SHA가 일치했다. Windows 전용 실제 파일 테스트3개를 추가했다. Mac 앱 실행 파일을 Windows로 옮겨 실행한 것이 아니다.

| 구성 | 실행 테스트 | 실패 | 테스트 실행 시간 | build+test 경과 |
|---|---:|---:|---:|---:|
| debug |22|0|23.459초|68.068초|
| release |22|0|21.722초|53.866초|

서로 다른 테스트는22개다. 기존19개와 새3개이며 debug/release를 합쳐44개의 다른 테스트라고 집계하지 않는다. Swift Testing runner의 별도0 tests 메시지는 추가 XCTest22개의 실행 결과와 구분한다. 위 시간은 fixture 생성·정리도 포함한 테스트 전체이며 스캔 처리량·Mac 대비 속도 성과가 아니다.

## 실제 파일 검증

검증 adapter는 Windows Foundation `FileManager`로 실제 디렉터리·파일 metadata를 읽고, 제품의 `DirectoryWorkerPool`·`DirectoryIOBudget`·ticket·취소 control에 연결했다. adapter는 테스트 코드에만 있으며 production Win32 고속 reader로 채택하지 않았다.

- 100개 branch×96파일, 별도 Unicode4파일,12단계 깊은 경로의1파일: 총9,605파일·논리 용량149,413byte.
- worker1·2·4개에서 직렬 기준과 파일별 metadata·raw UTF-8 이름 일치. 입력 생성 시 계산한 파일 수·바이트 합계도 일치.
- 한글·공백·emoji와 NFC/NFD의 서로 다른 이름을 보존.
- 생성→rename→크기 변경→delete 후 명시적 재검사에서 새 목록을 반영. 삭제 후 빈 목록 확인.
- 첫 metadata 읽기 후 취소가 부분 목록을 내보내지 않음. 사전 취소와 없는 폴더 오류도 terminal 결과 전달.
- 결과 소비 후 permit active0, shutdown terminal, 테스트 fixture 삭제 확인.

기존19개는 queue 포화·취소 범위·permit·작업 창·재보충·실패·합산·발행·metadata 계약을 포함한다.128-bit Windows identity 검증은 기존 synthetic fixture이며, 실제 Win32 file ID 조회를 검증했다고 주장하지 않는다.

## 환경 구성·재현성

Swift/C++ 도구가 없어 공식 Swift installer6.2.4와 MSVC14.44.35207·Windows SDK10.0.22621.0을 설치했다. 설치 파일의 Authenticode 서명과 SHA를 기록했다. WinGet은 기존 source 데이터 오류로 실패해 공식 직접 다운로드로 전환했다. 초기 실패 로그도 보존했다. 재부팅하지 않았으며 기존 Windows 작업을 종료하지 않았다. 내려받은 installer2개는 검증 후 삭제했고 개발 도구와 테스트 source/build/log는 PC의 전용 `sniffer-validation-20261123` 폴더에 남겼다. 비밀번호는 작업 스크립트·파일·결과 문서에 저장하지 않았다.

[공식 Swift Windows 안내](https://www.swift.org/install/windows/manual/)를 기준으로 필수 도구를 구성했다. 소스 ZIP와 각 파일의 SHA를 PC에서 검사한 뒤 빌드했고, 종료 후에도 source SHA를 다시 대조했다. [source manifest](validation/windows-132-2026-11-23/source-manifest.json) · [검증 ZIP](validation/windows-132-2026-11-23/engine.zip) · [도구 installer SHA](validation/windows-132-2026-11-23/installer-hashes.json) · [테스트 PE artifact SHA](validation/windows-132-2026-11-23/test-artifacts.json).

재현 방법은 [Windows 검증 스크립트](../scripts/windows-validation/README.md)에 있다. 전용 Windows runner로 개발 도구 환경을 설정하고 debug/release를 실행한다. 실행 당시 스크립트와 재사용 가능한 스크립트는 구분해 보존했다. 로컬에서 Windows guard를 제거한 복사본으로 test compile을 먼저 확인한 기록은 실제 Windows 실행 횟수로 집계하지 않았다.

## 1단계 종료와 후속

- [x] Mac 기능·20만 파일 GUI·감시·ARM/Intel 호환성 근거 확보.
- [x] 같은 공통 엔진 production의 Windows debug/release 빌드·기존19개 테스트 통과.
- [x] Windows 실제 파일 I/O 통합3개·worker1/2/4·취소·명시적 재검사 통과.
- [x] 소스·테스트 binary·결과 SHA와 fixture 정리 기록.
- [ ] Windows production 고속 reader: Win32 batch/fallback·handles·실제128-bit ID·allocated bytes·reparse/volume·network 검증.
- [ ] Windows 파일 변경 감시와 전체 scanner/model/filter/SNS·GUI 연결.
- [ ] 안정된 Mac 측정 조건의 A/A·표준7입력 성능 gate 및 기본 설치·배포.

따라서 **Mac 기능 구현과 공통 엔진 이식성 검증까지의1단계는 종료 가능**하다. Windows 완제품·전체 성능 채택은 위 후속 범위로 남긴다.
