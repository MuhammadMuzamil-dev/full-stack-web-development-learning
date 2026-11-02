@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0yt-course-downloader-pro.ps1" -Gui
if errorlevel 1 (
  echo.
  echo The downloader reported an error. Read the messages above and the log in your chosen save folder.
  pause
)
