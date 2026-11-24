@echo off
if "%~1"=="" exit /b 2
call "C:\BuildTools\Common7\Tools\VsDevCmd.bat" -no_logo -arch=amd64 -host_arch=amd64
if errorlevel 1 exit /b 1
chcp 65001 >nul
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0run-tests.ps1" -Workspace "%~1"
