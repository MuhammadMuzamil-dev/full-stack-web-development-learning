@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-YT-Course-Protocol.ps1"
if errorlevel 1 echo Setup failed. Read the error shown above.
pause
