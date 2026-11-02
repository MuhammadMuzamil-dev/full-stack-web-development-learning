@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-YT-Course-Protocol.ps1"
if errorlevel 1 echo Uninstall failed. Read the error shown above.
pause
