@echo off
setlocal
if "%~1"=="" exit /b 64
if not exist "%~1" mkdir "%~1"
cl.exe /nologo /std:c++20 /EHsc /utf-8 /O2 /W4 /DUNICODE /D_UNICODE "%~dp0preview-host.cpp" /Fo"%~1\preview-host.obj" /Fe"%~1\WindowsPreviewHost.exe" /link /SUBSYSTEM:WINDOWS ole32.lib shell32.lib shlwapi.lib user32.lib gdi32.lib windowscodecs.lib uuid.lib
exit /b %errorlevel%
