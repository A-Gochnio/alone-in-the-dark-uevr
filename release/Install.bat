@echo off
rem Alone in the Dark VR installer. Extra arguments are passed on, e.g. Install.bat -Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
echo.
pause
