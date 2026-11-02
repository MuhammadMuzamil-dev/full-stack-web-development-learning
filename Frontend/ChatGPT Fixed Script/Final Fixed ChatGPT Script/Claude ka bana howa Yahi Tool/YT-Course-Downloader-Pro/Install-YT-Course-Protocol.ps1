#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$sourceFolder = $PSScriptRoot
$installFolder = Join-Path $env:LOCALAPPDATA 'YT Course Downloader'
$required = @('yt-course-downloader-pro.ps1','yt-course-downloader-pro-encoded.ps1','ProtocolHandler.ps1','Install-YT-Course-Protocol.ps1','Uninstall-YT-Course-Protocol.ps1','yt-course-downloader-pro-gui.cmd','Install-YT-Course-Protocol.cmd','Uninstall-YT-Course-Protocol.cmd','README.txt')
foreach ($name in $required) {
    $source = Join-Path $sourceFolder $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required file is missing: $name. Extract the full ZIP first." }
}

Write-Host 'This setup only registers a browser link for your Windows account (HKCU). Administrator access is not required.' -ForegroundColor Cyan
Write-Host 'When you click the green HTML button, the browser may ask whether to open PowerShell. You must approve that prompt.' -ForegroundColor Cyan
$answer = Read-Host 'Type Y to install the browser-to-PowerShell link, or N to cancel'
if ($answer.Trim() -notmatch '^(?i)y(es)?$') { Write-Host 'Setup cancelled; no changes were made.' -ForegroundColor Yellow; exit 0 }

New-Item -ItemType Directory -Path $installFolder -Force | Out-Null
foreach ($name in $required) { Copy-Item -LiteralPath (Join-Path $sourceFolder $name) -Destination (Join-Path $installFolder $name) -Force }

$schemeKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\ytcourse')
$schemeKey.SetValue('', 'URL:YT Course Downloader Link', [Microsoft.Win32.RegistryValueKind]::String)
$schemeKey.SetValue('URL Protocol', '', [Microsoft.Win32.RegistryValueKind]::String)
$commandKey = $schemeKey.CreateSubKey('shell\open\command')
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$handlerPath = Join-Path $installFolder 'ProtocolHandler.ps1'
$command = '"' + $windowsPowerShell + '" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $handlerPath + '" "%1"'
$commandKey.SetValue('', $command, [Microsoft.Win32.RegistryValueKind]::String)
$commandKey.Close(); $schemeKey.Close()
Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host 'Open a Notes & Links HTML page and click “Open PowerShell for this video”.' -ForegroundColor Green
Write-Host ('Installed helper files: ' + $installFolder)
Write-Host 'This setup did not change the machine-wide execution policy and did not request administrator access.' -ForegroundColor Cyan
Read-Host 'Press Enter to close' | Out-Null
