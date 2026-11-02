@echo off
setlocal
cd /d "%~dp0"
echo YT Course Downloader - guided mode
echo This window will stay open so you can read results and errors.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0yt-course-downloader-final.ps1" -Gui -NoPause
echo.
echo Downloader finished or stopped. Read the messages above and the log in the selected save folder.
echo Press any key to close this window.
pause >nul
