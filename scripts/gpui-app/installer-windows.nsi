; Build from a verified Spacer payload using prepare-spacer-installers.py.
!ifndef VERSION
 !error "VERSION is required"
!endif
Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"
!ifndef PAYLOAD
  !error "PAYLOAD is required"
!endif
Name "Spacer ${VERSION}"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\Spacer\${VERSION}"
RequestExecutionLevel user
ManifestDPIAware true
SetCompressor zlib
Icon "${APPICON}"
UninstallIcon "${APPICON}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "Spacer"
VIAddVersionKey "FileDescription" "Spacer per-user installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Spacer contributors"
!define KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Spacer-${VERSION}"
!define LINKNAME "Spacer ${VERSION}"
!insertmacro MUI_PAGE_WELCOME
; Versioned per-user path preserves the previous installation.
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "English"
Var OwnInstall

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "This package requires 64-bit Windows."
    Abort
  ${EndIf}
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\SpacerInstaller") p .r0 ?e'
  Pop $1
  ${If} $1 = 183
    MessageBox MB_ICONSTOP "Another installer is already running."
    Abort
  ${EndIf}
  SetShellVarContext current
FunctionEnd

Section "Spacer" SEC_MAIN
  ${If} ${FileExists} "$INSTDIR\*.*"
    MessageBox MB_ICONSTOP "This build is already installed. Uninstall it first. Your previous version remains available."
    Abort
  ${EndIf}
  CreateDirectory "$INSTDIR"
  StrCpy $OwnInstall "1"
  SetOutPath "$INSTDIR"
  !include "${INSTALL_INCLUDE}"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${LINKNAME}"
  CreateShortCut "$SMPROGRAMS\${LINKNAME}\Spacer.lnk" "$INSTDIR\Spacer.exe"
  CreateShortCut "$SMPROGRAMS\${LINKNAME}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "${KEY}" "DisplayName" "Spacer ${VERSION}"
  WriteRegStr HKCU "${KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${KEY}" "DisplayIcon" "$INSTDIR\Spacer.exe"
  WriteRegStr HKCU "${KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegDWORD HKCU "${KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${KEY}" "NoRepair" 1
SectionEnd

Function .onInstFailed
  ${If} $OwnInstall == "1"
    !include "${DELETE_INCLUDE}"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    Delete "$SMPROGRAMS\${LINKNAME}\Spacer.lnk"
    Delete "$SMPROGRAMS\${LINKNAME}\Uninstall.lnk"
    RMDir "$SMPROGRAMS\${LINKNAME}"
    DeleteRegKey HKCU "${KEY}"
  ${EndIf}
FunctionEnd

!macro GuardClosed NAME
  ; Request write access without writing: mapped executables must be closed.
  ${If} ${FileExists} "$INSTDIR\${NAME}"
  System::Call 'kernel32::CreateFileW(w "$INSTDIR\${NAME}", i 0x40000000, i 1, p 0, i 3, i 0, p 0) p .r0'
  ${If} $0 == -1
    MessageBox MB_ICONSTOP "Close Spacer and its preview before uninstalling. No process will be stopped automatically."
    Abort
  ${EndIf}
  System::Call 'kernel32::CloseHandle(p r0)'
  ${EndIf}
!macroend

Section "Uninstall"
  SetShellVarContext current
  !insertmacro GuardClosed "Spacer.exe"
  !insertmacro GuardClosed "SpacerCLI.exe"
  !insertmacro GuardClosed "ExplorerBackend.exe"
  !insertmacro GuardClosed "WindowsPreviewHost.exe"
  !include "${DELETE_INCLUDE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${LINKNAME}\Spacer.lnk"
  Delete "$SMPROGRAMS\${LINKNAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${LINKNAME}"
  DeleteRegKey HKCU "${KEY}"
  ; Unknown files, recovery data, previous installs and desktop shortcuts stay.
SectionEnd
