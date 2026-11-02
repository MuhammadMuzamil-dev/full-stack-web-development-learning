$ErrorActionPreference='Stop'
$dir='C:\Users\User\Desktop\full-stack-web-development-learning\Frontend\ChatGPT Fixed Script\Final Fixed ChatGPT Script\YT-Course-Downloader-Final-Repair-Work\yt-course-downloader-final-subtitle-429-fix'
$p=Join-Path $dir 'yt-course-downloader-final.ps1';$encPath=Join-Path $dir 'yt-course-downloader-final-encoded.ps1'
$s=[IO.File]::ReadAllText($p);$enc=[IO.File]::ReadAllText($encPath)
$payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
$enc=[regex]::Replace($enc,'(?s)(\$payload\s*=\s*@''\s*).*?(\s*''@)','$1'+$payload+'$2',1)
[IO.File]::WriteAllText($encPath,$enc,(New-Object System.Text.UTF8Encoding($false)))
foreach($f in @($p,$encPath,(Join-Path $dir 'ProtocolHandler.ps1'),(Join-Path $dir 'Install-YT-Course-Protocol.ps1'),(Join-Path $dir 'Uninstall-YT-Course-Protocol.ps1'))){
 $t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e)|Out-Null
 if($e.Count -eq 0){Write-Output ('PARSE_PASS '+[IO.Path]::GetFileName($f))}else{Write-Output ('PARSE_FAIL '+[IO.Path]::GetFileName($f)+' count='+$e.Count);$e|Select-Object -First 8|ForEach-Object{$_.Message}}
}
$m=[regex]::Match($enc,'(?s)\$payload\s*=\s*@''\s*(.*?)\s*''@')
$decoded=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.Groups[1].Value -replace '\s','')))
if($decoded -ceq [IO.File]::ReadAllText($p)){Write-Output 'ENCODED_PARITY_PASS'}else{Write-Output 'ENCODED_PARITY_FAIL'}
if($s.Contains('Resolve-ChannelAndPlaylistLinks') -and $s.Contains('%(playlist_title|Videos)s/%(title)s/%(title)s') -and $s.Contains('--format-sort-force', '$FormatSort')){Write-Output 'FEATURE_STATIC_CHECK_PASS'}else{Write-Output 'FEATURE_STATIC_CHECK_REVIEW'}
$ver=(& yt-dlp --version 2>&1|Out-String).Trim();Write-Output ('YTDLP_VERSION '+$ver)
$ff=(& ffmpeg -version 2>&1|Select-Object -First 1|Out-String).Trim();Write-Output ('FFMPEG_STARTUP '+$ff)
