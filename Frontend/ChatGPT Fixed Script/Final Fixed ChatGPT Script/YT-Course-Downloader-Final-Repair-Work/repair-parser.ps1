$ErrorActionPreference='Stop'
$p='C:\Users\User\Desktop\full-stack-web-development-learning\Frontend\ChatGPT Fixed Script\Final Fixed ChatGPT Script\YT-Course-Downloader-Final-Repair-Work\yt-course-downloader-final-subtitle-429-fix\yt-course-downloader-final.ps1'
$a=[System.Collections.Generic.List[string]]::new()
[IO.File]::ReadAllLines($p) | ForEach-Object {$a.Add($_)}
$a[264]='        $playlistHtml = "<div style=''margin-top:8px;''><b>Full playlist:</b> <a href=''$safePlaylist'' target=''_blank'' rel=''noopener noreferrer''>$safePlaylistTitle</a></div>"'
$a[276]='        $chaptersHtml = "<section style=''background:#fff;padding:16px;border-radius:8px;border:1px solid #e2e8f0;margin-bottom:16px;''><h3>Video chapters (click to jump)</h3><ul>$($rows -join '''')</ul></section>"'
$a[290]='<div><b>Direct video link:</b> <a href="$safeUrl" target="_blank" rel="noopener noreferrer">$safeUrl</a></div>'
$a[292]='<div style="margin-top:8px;"><b>Channel:</b> $channel &nbsp;|&nbsp; <b>Duration:</b> $safeDuration</div>'
$a[294]='<b>Re-download command (maximum $($Quality)p):</b><br><code id="redownload-command" style="white-space:normal;overflow-wrap:anywhere;">$command</code><br>'
$a[279]='$description = [regex]::Replace($description, ''(https?://[^\\s<]+)'', ''<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>'')'
[IO.File]::WriteAllLines($p,$a,(New-Object System.Text.UTF8Encoding($false)))
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)|Out-Null
if($e.Count -eq 0){Write-Output 'READABLE_PARSE_PASS'}else{Write-Output ('READABLE_PARSE_FAIL '+$e.Count);$e|Select-Object -First 12|ForEach-Object{Write-Output ($_.Message+' line '+$_.Extent.StartLineNumber)}}
