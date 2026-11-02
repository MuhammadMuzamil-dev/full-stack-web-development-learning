#requires -Version 5.1
$ErrorActionPreference='Stop'
$source=$PSScriptRoot
$install=Join-Path $env:LOCALAPPDATA 'YT Course Downloader Final'
$required=@('yt-course-downloader-final.ps1','yt-course-downloader-final-encoded.ps1','ProtocolHandler.ps1','Install-YT-Course-Protocol.ps1','Uninstall-YT-Course-Protocol.ps1','yt-course-downloader-final-gui.cmd','Install-YT-Course-Protocol.cmd','Uninstall-YT-Course-Protocol.cmd','README.txt')
foreach($name in $required){if(-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)){throw "Required file missing: $name. Extract the full ZIP first."}}
Write-Host 'This registers a browser link for your Windows account only. No administrator access is needed.' -ForegroundColor Cyan
Write-Host 'When you click the green HTML button, the browser may ask permission to open PowerShell. You must approve that request.' -ForegroundColor Cyan
$answer=Read-Host 'Type Y to set up the HTML button, or N to cancel'
if($answer.Trim() -notmatch '^(?i)y(es)?$'){Write-Host 'Setup cancelled; no change was made.' -ForegroundColor Yellow; return}
New-Item -ItemType Directory -Path $install -Force | Out-Null
foreach($name in $required){Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $install $name) -Force}
$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\ytcourse')
$key.SetValue('', 'URL:YT Course Downloader Link', [Microsoft.Win32.RegistryValueKind]::String)
$key.SetValue('URL Protocol','',[Microsoft.Win32.RegistryValueKind]::String)
$cmdKey=$key.CreateSubKey('shell\open\command')
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$handlerPath=Join-Path $install 'ProtocolHandler.ps1'
$command='"'+$ps+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$handlerPath+'" "%1"'
$cmdKey.SetValue('', $command, [Microsoft.Win32.RegistryValueKind]::String)
$cmdKey.Close();$key.Close()
Write-Host '';Write-Host 'Setup complete. Reopen the HTML file and click its green button.' -ForegroundColor Green
Write-Host ('Installed files: '+$install)
Write-Host 'Only the current-user registry was changed. No system-wide policy was changed.' -ForegroundColor Cyan
