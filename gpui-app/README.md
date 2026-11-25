# Space Sniffer GPUI

기존 Mac UI와 애니메이션을 공통 Rust/GPUI 화면으로 옮기는 중입니다. 기존 Swift 엔진은 재사용합니다. **Mac/Windows GPUI 0.3.0 설치·실행·주요 기능 검증은 완료했습니다. 일부 OS 입력 전체·장시간 검수는 남아 있습니다.** [이전 설치/성능 결과](../docs/GPUI_COMPLETION_RESULTS.md). [2026-11-24 콘솔·감시 갱신 후속 수정](../docs/GPUI_BACKGROUND_RESULTS.md). [기능 동등성/검증 TODO](../docs/GPUI_MIGRATION_TODO.md)를 먼저 확인하세요.

Mac:

```sh
swift build -c release --product MacScanBridge
swift build -c release --product MacPreviewSupport
cargo +1.97.0 build --locked --manifest-path gpui-app/Cargo.toml
cp .build/release/libMacPreviewSupport.dylib gpui-app/target/debug/
SNIFFER_SCAN_BACKEND="$PWD/.build/release/MacScanBridge" gpui-app/target/debug/space-sniffer-gpui --scan "$HOME/Downloads"
```

Windows는 VS x64 developer prompt에서 같은 Cargo manifest와 `Packages/SpaceSnifferExplorerBridge`의 `ExplorerBackend`를 빌드합니다. `ExplorerBackend.exe`와 Swift runtime DLL을 GPUI executable 옆에 배치합니다. WinForms UI executable은 필요하지 않습니다. `SNIFFER_SCAN_BACKEND`로 기존 native engine의 위치를 지정할 수도 있습니다.

```sh
cargo +1.97.0 test --locked --manifest-path gpui-app/Cargo.toml
python3 scripts/check-gpui-boundary.py
```

`--features qa` 빌드에서 `--scan FIXTURE --qa-output REPORT.json`을 전달하면 실제 GPUI renderer와 command handler를 이용한 acceptance 시나리오를 실행합니다. fixture에는 `.zip` 파일과 파일을 가진 하위 폴더가 있어야 합니다. 테스트 출력과 engine 임시 결과는 scan root 밖에 둡니다. 스크린샷은 원본 상태 검수용이며, 자동 PNG 비교가 기능 전체 동등성을 입증하지는 않습니다.

이 preview는 Noto Sans KR(OFL 동봉)과 GPUI Kit의 Lucide SVG를 사용합니다. SwiftUI system glyph/서체/native chrome의 완전한 시각 동등성은 최종 검수 대상입니다.

문서·필터·태그 및 플랫폼별 검증: [성과표](../docs/GPUI_DOCUMENT_RESULTS.md). Mac 번들에는 MacScanBridge와 libMacPreviewSupport.dylib, Windows candidate에는 ExplorerBackend.exe와 Swift runtime DLL을 함께 둡니다.

## Windows native preview companion

VS x64 developer prompt에서 다음 명령으로 별도 helper를 빌드하고 GPUI executable 옆에 배치합니다.

```bat
gpui-app\native\windows-preview\build.cmd gpui-app\target\debug
```

`WindowsPreviewHost.exe`가 없으면 preview 실행 오류를 표시합니다. production 패키저는 이 helper가 없으면 패키징을 거부합니다. 같은 GPUI UI에서 Space를 누르면 platform adapter가 helper를 실행합니다. 텍스트(최대 1MiB), WIC 정적 이미지(최대 32M pixels), 등록된 out-of-process Shell preview handler, metadata 순서로 대응합니다. Mac Quick Look과 모든 형식의 동등성을 뜻하지 않습니다. 부모의 Windows Job이 helper 수명을 관리합니다. [구조·Windows 실행 검증 항목](native/windows-preview/README.md).

Mac `--volumes selectedVolume|allVolumes`는 native bridge의 기존 scope 정책을 선택합니다. 공통 UI의 다른 볼륨 포함 옵션은 지원하는 platform에서만 활성화합니다. Windows scanner도 인식 가능한 mount point를 opt-in으로 포함하며 볼륨 ID로 중복/순환을 막습니다. 실제 owned VHD에서 native 100→6100→100개를 확인했습니다. 132 PC의 최종 visible GUI/release·바로가기·실제 watch 검증도 완료했습니다. [실제 검증 결과](../docs/GPUI_PREVIEW_SCOPE_RESULTS.md).


## Release 구성

production 기본 `capture` feature는 고정한 upstream GPUI의 offscreen capture API를 사용하기 위해 `test-support`를 켭니다. 우리 acceptance 실행 명령은 별도 `qa` feature로 제한하며 production에서는 `--qa-*`를 exit 64로 거부합니다.

```sh
SPACE_SNIFFER_BUNDLE_ID=local.macspacesniffer.app cargo +1.97.0 build --release --locked --manifest-path gpui-app/Cargo.toml
python3 scripts/gpui-app/package-macos.py --rust-binary /ABS/target/release/space-sniffer-gpui --native-directory /ABS/swift/release --output '/ABS/new/Mac Space Sniffer.app'
```

Windows도 `SPACE_SNIFFER_BUNDLE_ID=local.macspacesniffer.app`으로 release 빌드하고 `package-windows.ps1`에 Rust release executable 및 `ExplorerBackend.exe`, `WindowsPreviewHost.exe`, Swift runtime DLL이 들어 있는 companion directory를 지정합니다. SDK `rc.exe`가 필요합니다. 패키저는 기존 출력 경로를 덮어쓰지 않습니다. Mac 패키지는 macOS 14 이상, 현재 검증된 architecture는 arm64이며 서명은 ad-hoc입니다.

`check-control.py`는 **별도 QA instance**의 문서를 자체 생성한 fixture로 바꾸고 마지막 창을 닫습니다. 사용자 분석 창에 실행하지 마세요. `benchmark-scale.py`는 visible QA 창에서 JSON/binary를 교대로 비교하며 SNS 첫 표시와 파일시스템 탐색 시간을 구분합니다.


## 기본 빌드 명령

Mac: `scripts/build-gpui-app.sh`. `SNIFFER_BUILD_ROOT`를 지정하면 같은 Swift/Cargo cache를 재사용합니다. 작업 볼륨 공간이 부족하면 `SNIFFER_OUTPUT_ROOT`로 패키지 출력도 내부 디스크에 둘 수 있습니다. 기본 cache는 OS 임시 디렉터리에 두며 작업 볼륨을 수 GB의 Cargo cache로 채우지 않습니다. output은 새 버전/architecture/시각 경로이고 `dist/Spacer.app` alias를 갱신합니다. 현재 `--universal`을 지원한다고 표시하지 않습니다.

Windows x64 Developer PowerShell:

```powershell
.\scripts\build-gpui-app.ps1 -SwiftBin "$env:LOCALAPPDATA\Programs\Swift\Toolchains\6.2.4+Asserts\usr\bin" -SwiftRuntimeDirectory "$env:LOCALAPPDATA\Programs\Swift\Runtimes\6.2.4\usr\bin"
```

Windows script는 일치하는 Swift runtime DLL과 native backend/preview helper를 조립합니다. SDK shell의 PATH를 초기값으로 되돌리지 않으며, 아이콘/버전 resource와 GPUI가 소유하는 manifest를 중복 삽입하지 않습니다.

Noto variable source의 기본 축은 Thin(100)입니다. UI에는 고정 400/500/600/700 face를 넣어 CoreText/DirectWrite가 동일한 굵기를 선택하게 합니다. 생성: fonttools 4.68.0으로 `prepare-fonts.py`, 독립 metadata/hash 검사: `check-fonts.py`. 원본 OFL과 생성 manifest를 함께 보관합니다.

## 입력 없이 실행하는 QA

QA feature 빌드만 `--qa-background`를 허용하며 창 표시와 앱 activation을 하지 않습니다. `scripts/gpui-app/check-watch-soak.py`는 자체 fixture·프로세스에서 감시, 옵션 전환, 빈/목록/필터 화면 및 root 복귀를 반복합니다. Windows는 `check-windows-console-watch.ps1`로 같은 작업을 감싸 콘솔 표시나 backend 4개 초과를 관찰하면 자체 시험을 중단합니다. 실제 OS drag/drop·클립보드·단축키 입력 검수를 대신하지 않습니다.

일반 감시 갱신은 현재 backend에 `rescan`을 전달합니다. 활성 문서와 주차한 원본 문서 모두 같은 정책이며 엔진이 종료된 경우에만 다시 시작합니다. Windows child process의 console 생성 차이는 `platform::configure_child_process` 어댑터에서 처리합니다.
