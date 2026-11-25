; Build from a hash-verified payload using prepare-installers.py.
Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"
!ifndef PAYLOAD
  !error "PAYLOAD is required"
!endif
Name "Space Sniffer 0.3.0"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\SpaceSniffer-Windows\0.3.0-GPUI-20261124.1"
RequestExecutionLevel user
ManifestDPIAware true
SetCompressor zlib
Icon "${APPICON}"
UninstallIcon "${APPICON}"
VIProductVersion "0.3.0.300"
VIAddVersionKey "ProductName" "Space Sniffer"
VIAddVersionKey "FileDescription" "Space Sniffer per-user installer"
VIAddVersionKey "FileVersion" "0.3.0 (20261124.1)"
VIAddVersionKey "LegalCopyright" "Space Sniffer contributors"
!define KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SpaceSniffer-GPUI-20261124.1"
!define LINKNAME "Space Sniffer 0.3.0 (20261124.1)"
!insertmacro MUI_PAGE_WELCOME
; Fixed versioned per-user path: never overwrite the previous 0.3.0-GPUI app.
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
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\SpaceSnifferInstaller20261124_1") p .r0 ?e'
  Pop $1
  ${If} $1 = 183
    MessageBox MB_ICONSTOP "Another installer is already running."
    Abort
  ${EndIf}
  SetShellVarContext current
FunctionEnd

Section "Space Sniffer" SEC_MAIN
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
  CreateShortCut "$SMPROGRAMS\${LINKNAME}\Space Sniffer.lnk" "$INSTDIR\MacSpaceSniffer.exe"
  CreateShortCut "$SMPROGRAMS\${LINKNAME}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "${KEY}" "DisplayName" "Space Sniffer 0.3.0 (20261124.1)"
  WriteRegStr HKCU "${KEY}" "DisplayVersion" "0.3.0"
  WriteRegStr HKCU "${KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${KEY}" "DisplayIcon" "$INSTDIR\MacSpaceSniffer.exe"
  WriteRegStr HKCU "${KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegDWORD HKCU "${KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${KEY}" "NoRepair" 1
SectionEnd

Function .onInstFailed
  ${If} $OwnInstall == "1"
    !include "${DELETE_INCLUDE}"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    Delete "$SMPROGRAMS\${LINKNAME}\Space Sniffer.lnk"
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
    MessageBox MB_ICONSTOP "Close Space Sniffer and its preview before uninstalling. No process will be stopped automatically."
    Abort
  ${EndIf}
  System::Call 'kernel32::CloseHandle(p r0)'
  ${EndIf}
!macroend

Section "Uninstall"
  SetShellVarContext current
  !insertmacro GuardClosed "MacSpaceSniffer.exe"
  !insertmacro GuardClosed "ExplorerBackend.exe"
  !insertmacro GuardClosed "WindowsPreviewHost.exe"
  !include "${DELETE_INCLUDE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${LINKNAME}\Space Sniffer.lnk"
  Delete "$SMPROGRAMS\${LINKNAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${LINKNAME}"
  DeleteRegKey HKCU "${KEY}"
  ; Unknown files, recovery data, previous installs and desktop shortcuts stay.
SectionEnd
