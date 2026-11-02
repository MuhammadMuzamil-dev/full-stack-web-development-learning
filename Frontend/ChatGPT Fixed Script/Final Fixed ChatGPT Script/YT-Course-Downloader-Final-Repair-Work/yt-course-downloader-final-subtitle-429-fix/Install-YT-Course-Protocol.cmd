@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-YT-Course-Protocol.ps1"
echo.
echo Setup finished or cancelled. See the messages above.
pause
