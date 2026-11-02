#requires -Version 5.1
$ErrorActionPreference='Stop'
Write-Host 'This removes the HTML-to-PowerShell link and helper files. Downloaded videos and notes will not be touched.' -ForegroundColor Cyan
$answer=Read-Host 'Type Y to remove it, or N to cancel'
if($answer.Trim() -notmatch '^(?i)y(es)?$'){Write-Host 'Cancelled; no change was made.' -ForegroundColor Yellow; return}
Remove-Item -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Classes\ytcourse' -Recurse -Force -ErrorAction SilentlyContinue
$install=Join-Path $env:LOCALAPPDATA 'YT Course Downloader Final'
if(Test-Path -LiteralPath $install){Remove-Item -LiteralPath $install -Recurse -Force}
Write-Host 'HTML launch button uninstalled. Your downloaded videos and HTML notes are unchanged.' -ForegroundColor Green
