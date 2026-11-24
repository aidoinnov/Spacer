@echo off
setlocal
call "C:\BuildTools\Common7\Tools\VsDevCmd.bat" -no_logo -arch=amd64 -host_arch=amd64
if errorlevel 1 exit /b 1
set "PATH=%LOCALAPPDATA%\Programs\Swift\Toolchains\6.2.4+Asserts\usr\bin;%LOCALAPPDATA%\Programs\Swift\Runtimes\6.2.4\usr\bin;%PATH%"
swift build --package-path Packages\SpaceSnifferWindows -c release --jobs 2
if errorlevel 1 exit /b 1
if not exist WindowsApp\bin mkdir WindowsApp\bin
copy /y Packages\SpaceSnifferWindows\.build\x86_64-unknown-windows-msvc\release\WindowsScan.exe WindowsApp\bin\WindowsScan.exe >nul
if errorlevel 1 exit /b 1
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /codepage:65001 /target:winexe /platform:x64 /optimize+ /win32manifest:WindowsApp\SpaceSniffer.manifest /out:WindowsApp\bin\SpaceSniffer.exe /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll WindowsApp\*.cs
if errorlevel 1 exit /b 1
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /codepage:65001 /target:winexe /platform:x64 /optimize+ /out:WindowsApp\bin\SpaceSnifferLauncher.exe /r:System.Windows.Forms.dll WindowsApp\Launcher\Program.cs
if errorlevel 1 exit /b 1
copy /y "%LOCALAPPDATA%\Programs\Swift\Runtimes\6.2.4\usr\bin\*.dll" WindowsApp\bin\ >nul
if errorlevel 1 exit /b 1
endlocal
