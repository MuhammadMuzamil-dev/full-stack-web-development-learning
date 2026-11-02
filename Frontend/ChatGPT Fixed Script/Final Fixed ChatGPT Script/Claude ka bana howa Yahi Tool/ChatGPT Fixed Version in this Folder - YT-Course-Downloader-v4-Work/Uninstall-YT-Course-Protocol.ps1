#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Write-Host 'This removes only the browser-link registration and helper scripts installed under your Local AppData folder.' -ForegroundColor Cyan
Write-Host 'Downloaded videos and HTML notes in other folders will not be touched.' -ForegroundColor Cyan
$answer = Read-Host 'Type Y to remove the browser link, or N to cancel'
if ($answer.Trim() -notmatch '^(?i)y(es)?$') { Write-Host 'Cancelled; nothing was removed.' -ForegroundColor Yellow; exit 0 }
$schemePath = 'HKCU:\Software\Classes\ytcourse'
if (Test-Path -LiteralPath $schemePath) { Remove-Item -LiteralPath $schemePath -Recurse -Force }
$installFolder = Join-Path $env:LOCALAPPDATA 'YT Course Downloader'
if (Test-Path -LiteralPath $installFolder) { Remove-Item -LiteralPath $installFolder -Recurse -Force }
Write-Host 'Browser-link helper uninstalled. Your video files and HTML notes were left unchanged.' -ForegroundColor Green
Read-Host 'Press Enter to close' | Out-Null
