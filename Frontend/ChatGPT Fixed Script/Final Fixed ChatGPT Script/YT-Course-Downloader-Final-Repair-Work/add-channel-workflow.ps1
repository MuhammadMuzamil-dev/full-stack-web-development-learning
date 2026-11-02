$ErrorActionPreference='Stop'
$dir='C:\Users\User\Desktop\full-stack-web-development-learning\Frontend\ChatGPT Fixed Script\Final Fixed ChatGPT Script\YT-Course-Downloader-Final-Repair-Work\yt-course-downloader-final-subtitle-429-fix'
$p=Join-Path $dir 'yt-course-downloader-final.ps1'
$s=[IO.File]::ReadAllText($p)
$func=@'
function Resolve-ChannelAndPlaylistLinks {
 param([string[]]$InputLinks)
 $out=[System.Collections.Generic.List[string]]::new()
 foreach($raw in $InputLinks){
  $link=([string]$raw).Trim();if(-not $link){continue}
  $base=($link -replace '[?&].*$','').TrimEnd('/')
  $root=$base -match '^https://(www\.)?youtube\.com/(@[^/]+|channel/[^/]+|c/[^/]+|user/[^/]+)$'
  $ptab=$base -match '^https://(www\.)?youtube\.com/(@[^/]+|channel/[^/]+|c/[^/]+|user/[^/]+)/playlists$'
  if(-not $root -and -not $ptab){$out.Add($link);continue}
  Write-Host ''
  Write-Host ("Channel detected: "+$base) -ForegroundColor Cyan
  Write-Host '1 Videos   2 Playlists   3 Courses   4 Shorts   5 Live streams   6 All video sections'
  Write-Host 'Note: Home and Community posts are not video download lists.'
  $c=(Read-Host 'Choose 1-6').Trim()
  switch($c){
   '1'{$out.Add("$base/videos")}
   '3'{$out.Add("$base/courses")}
   '4'{$out.Add("$base/shorts")}
   '5'{$out.Add("$base/streams")}
   '2'{
    $tab=if($ptab){$base}else{"$base/playlists"}
    $lines=@(& yt-dlp --flat-playlist --dump-single-json --no-warnings --ignore-errors $tab 2>&1)
    $json=($lines|ForEach-Object{[string]$_}|Where-Object{$_.Trim().StartsWith('{')}|Select-Object -Last 1)
    $entries=@();if($json){try{$o=$json|ConvertFrom-Json;$entries=@($o.entries|Where-Object{$_})}catch{}}
    if($entries.Count -eq 0){$manual=(Read-Host 'Could not list playlists. Paste a direct playlist URL or press Enter to skip').Trim();if($manual -match '^https://(www\.)?youtube\.com/playlist\?list='){$out.Add($manual)};continue}
    for($i=0;$i -lt $entries.Count;$i++){
     $e=$entries[$i];$title=[string](Get-InfoValue $e 'title');if(-not $title){$title='Playlist '+($i+1)}
     $count=Get-InfoValue $e 'playlist_count';if($null -eq $count){$count=Get-InfoValue $e 'count'}
     $u=[string](Get-InfoValue $e 'url');if(-not $u){$u=[string](Get-InfoValue $e 'webpage_url')}
     if($u -match '^[A-Za-z0-9_-]{10,}$'){$u="https://www.youtube.com/playlist?list=$u"}
     if(-not $u){$id=[string](Get-InfoValue $e 'id');if($id -match '^(PL|UU|FL|LL|OLAK|RD|WL|EC|PU|TL)'){$u="https://www.youtube.com/playlist?list=$id"}}
     $e|Add-Member -NotePropertyName _downloadUrl -NotePropertyValue $u -Force
     $suffix=if($count){" - "+$count+" videos"}else{''}
     Write-Host (($i+1).ToString()+'. '+$title+$suffix)
    }
    Write-Host 'Type A for all playlists or enter numbers separated by commas.'
    $pick=(Read-Host 'Playlists to download').Trim();$nums=@()
    if($pick -match '^(?i)a(ll)?$'){$nums=@(1..$entries.Count)}else{foreach($x in ($pick -split ',')){$n=0;if([int]::TryParse($x.Trim(),[ref]$n)-and $n -ge 1 -and $n -le $entries.Count){$nums+=$n}}}
    foreach($n in ($nums|Select-Object -Unique)){$u=[string](Get-InfoValue $entries[$n-1] '_downloadUrl');if($u -match '^https://(www\.)?youtube\.com/playlist\?list='){$out.Add($u)}else{Write-Status -Level 'WARN' -Message ("Playlist "+$n+" has no resolvable URL and was skipped.")}}
   }
   '6'{
    $out.Add("$base/videos");$out.Add("$base/courses");$out.Add("$base/shorts");$out.Add("$base/streams")
    $lines=@(& yt-dlp --flat-playlist --dump-single-json --no-warnings --ignore-errors "$base/playlists" 2>&1)
    $json=($lines|ForEach-Object{[string]$_}|Where-Object{$_.Trim().StartsWith('{')}|Select-Object -Last 1)
    $entries=@();if($json){try{$o=$json|ConvertFrom-Json;$entries=@($o.entries|Where-Object{$_})}catch{}}
    foreach($e in $entries){$u=[string](Get-InfoValue $e 'url');if(-not $u){$u=[string](Get-InfoValue $e 'webpage_url')};if($u -match '^[A-Za-z0-9_-]{10,}$'){$u="https://www.youtube.com/playlist?list=$u"};if(-not $u){$id=[string](Get-InfoValue $e 'id');if($id -match '^(PL|UU|FL|LL|OLAK|RD|WL|EC|PU|TL)'){$u="https://www.youtube.com/playlist?list=$id"}};if($u -match '^https://(www\.)?youtube\.com/playlist\?list='){$out.Add($u)}}
   }
   default{Write-Status -Level 'WARN' -Message 'Invalid choice; channel link skipped.'}
  }
 }
 return @($out.ToArray()|Select-Object -Unique)
}

'@
if($s -notmatch 'function Resolve-ChannelAndPlaylistLinks'){
 $needle='try {'+[Environment]::NewLine+'    Set-RunPaths'
 if(-not $s.Contains($needle)){throw 'Main try anchor missing'}
 $s=$s.Replace($needle,$func+$needle)
}
$line='    foreach ($url in $activeLinks) { if (-not (Test-YouTubeLink $url)) { throw "This is not an accepted HTTPS YouTube link: $url" } }'
if(-not $s.Contains($line)){throw 'URL validation line missing'}
$s=$s.Replace($line,$line+[Environment]::NewLine+'    $activeLinks = @(Resolve-ChannelAndPlaylistLinks -InputLinks $activeLinks)'+[Environment]::NewLine+'    if ($activeLinks.Count -eq 0) { throw ''No downloadable links were selected.'' }')
[IO.File]::WriteAllText($p,$s,(New-Object System.Text.UTF8Encoding($false)))
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)|Out-Null
if($e.Count -eq 0){Write-Output 'CHANNEL_SCRIPT_PARSE_PASS'}else{Write-Output ('CHANNEL_SCRIPT_PARSE_FAIL '+$e.Count);$e|Select-Object -First 10|ForEach-Object{Write-Output ($_.Message+' line '+$_.Extent.StartLineNumber)}}
