# 작업 마감·배포 준비 — 2026-11-24

프로젝트 이름은 **Spacer**, GitHub 저장소는 `aidoinnov/Spacer`(공개)로 정했다.
기존 실행 파일·bundle ID·설치 경로·0.3.0 설치파일의 Space Sniffer 이름은 그대로다.
제품 표시명/설치파일 이름 전환은 다음 릴리스에서 별도로 적용·검증한다.

최신 CLI/MCP 점검: [검수 결과·수정·미완료 범위](CLI_MCP_VALIDATION.md).
CLI 입력/출력 보존, MCP UTF-8·요청 검증, 이전 오류가 남는 UI 상태를 소스에서
수정하고 별도 QA 빌드로 확인했다. 현재 설치본과 동결 패키지는 교체하지 않았다.
Windows 연결 단절 후 원문 회수·소유 예약 작업 제거·진행 중 파일 스캔 취소 입증이
남아 있다. GPUI 본체에 레거시 헤드리스 CLI를 연결하는 작업도 별도다.

사용자 결정: 1단계 구현·검수 작업을 마감한다. 다른 프로젝트의 고부하 때문에
정식 속도 판정과 과거 종료 지연 원인 조사는 후속으로 이관한다. 해당 항목을
합격·해결로 바꾸지 않는다. 현재 작업은 검증된 설치본의 설치파일 제작과 배포 준비다.

## 완료

- Mac/Windows 공통 GPUI UI 이식, 트리맵 탐색·진행 표시·애니메이션·아이콘,
  필터·문서·태그·보고서·preview·감시·부분 재검사. 플랫폼 차이는 포트/어댑터로 분리.
- Windows backend 콘솔 반복 생성, watch backend 재생성, frame arena 반환,
  Quick Look 재진입 충돌, 접근성 초점, 휴지통 취소 역할 수정.
- 양쪽 실제 설치 경로 실행·스캔·파일 oracle, SNS/폴더 drag/drop, 탐색/단축키,
  preview, 휴지통 취소/이동/OS 복원 등 실제 입력 검수. 모든 OS/형식의 전수 검수는 아님.
- Mac Rust 29/Windows 30 및 clippy 등 당시 변경에 맞는 검증.
- 최종 추가 종료 검증: 양쪽 기존/후보 엔진 × 3조건 × 각5회 = 60회와
  Mac production visible 2회 통과. 약40–236ms, 정상 종료·native 잔류0.
- metrics 조회 실패를 프로세스 소멸로 오판하던 QA 진단 수정.
  Mac stack/Windows MiniDump 수집·의도적 metrics 실패 경로 실검증.
- 자체 캐시 정리, 비활성 QA 앱은 검증 후 ZIP 보존. VM lease 3개 모두 재개.
  추가 Mac 검수 프로세스 잔류0. Windows는 앞선 종료/예약 작업 정리를 확인했으나
  마지막 재접속은 인증 불가로 최신 상태 재조회 불가.

## 배포 기준 — 검증된 184B 설치본

원본 동결 패키지:
`~/Downloads/SpaceSniffer-GPUI-0.3.0-OS-Input-20261124/`.
`mac.manifest.json`, `windows.manifest.json`의 전체 파일 SHA-256과 대조해 사용한다.

| 구성 | SHA-256 |
|---|---|
| Mac GUI | `71b58ddcacc0404b79d9c7c98ed0993ef7a99782ddd8d81410e5136a1b569137` |
| Mac 184B backend | `a8ab73ee1e9f307669bdd4138015a64e31cba2c0d9feb2720f235f014cb97df5` |
| Windows GUI | `77280faa7f57cf40f385925d7b828d621c90becc11cd80ce30061a70f229a2d2` |
| Windows 184B backend | `1bf91efa01a4ecadeb96141dd1d5ca00099a7bf5d49e8e235cf3becc813e57d3` |

Mac: `~/Applications/Mac Space Sniffer.app`. Windows132:
`%LOCALAPPDATA%\Programs\SpaceSniffer-Windows\0.3.0-GPUI`.
현재 설치본과 rollback, 사용자 preview/Recovery는 유지한다.
Mac arm64/macOS14+ 검증, Windows132 x64 검증. Intel Mac runtime은 미검증.
Mac ad-hoc, Windows unsigned. 공인 서명/공증 완료로 설명하지 않는다.

## 이관한 후속 작업

- [ ] 유휴 호스트·공간 확보 후 기존 admission 기준 그대로 A/A100쌍 및
  표준7입력21쌍 성능 판정. 현재 **미실행**, 속도 합격 아님.
- [ ] 최신 disktree와 순차 처리량/RSS 비교. 이전 배수 비교를 최신 결과로 재사용 금지.
- [ ] 168B 후보가 성능 gate를 통과한 뒤 별도 양쪽 패키지·설치 교체·재검수.
  현재 후보 **미배포**. working tree 단순 빌드는 후보를 섞을 수 있다.
- [ ] 과거 8초 종료 지연 재현 시 OS 상태/stack/dump·독립 exit witness 수집으로
  원인 규명. 62회 정상 결과만으로 해결로 간주하지 않는다.
- [ ] 새 설치파일 자체의 Windows clean install/upgrade/uninstall runtime 검수.
- [ ] 외부 공개 전 Developer ID/notarization·Authenticode 및 의존성 재배포 고지 검토.

## 근거·다음 진입점

- [최종 OS 입력·현재 설치본](GPUI_OS_INPUT_RESULTS.md)
- [종료62회·성능 admission·진단 수정](PERFORMANCE_EXIT_RECHECK_RESULTS.md)
- [리소스 반환 기록](validation/resource-return-2026-11-24.json)
- [전체 이식 체크리스트](GPUI_MIGRATION_TODO.md)
- 설치파일·배포 준비 결과는 `RELEASE_PREPARATION.md`에 기록한다.

이 기록 이후 추가 검수는 다른 프로젝트의 프로세스나 마우스/키보드를 건드리지 않는
검증을 우선한다. 동결된 과거 증거의 내용·SHA는 수정하지 않는다.
