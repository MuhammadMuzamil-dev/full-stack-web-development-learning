$ErrorActionPreference='Stop'
$p='C:\Users\User\Desktop\full-stack-web-development-learning\Frontend\ChatGPT Fixed Script\Final Fixed ChatGPT Script\YT-Course-Downloader-Final-Repair-Work\yt-course-downloader-final-subtitle-429-fix\yt-course-downloader-final.ps1'
$a=[System.Collections.Generic.List[string]]::new();[IO.File]::ReadAllLines($p)|ForEach-Object{$a.Add($_)}
$idx=-1
for($i=0;$i -lt $a.Count;$i++){if($a[$i] -like "*'--write-subs', '--write-auto-subs', '--sub-langs'*"){$idx=$i;break}}
if($idx -lt 0){throw 'Subtitle args line not found'}
if($a[$idx+1] -notlike "*--format*"){
 $a.Insert($idx+1,'        ''--format'', $FormatSelector, ''--format-sort-force'', ''--format-sort'', $FormatSort,')
}
[IO.File]::WriteAllLines($p,$a,(New-Object System.Text.UTF8Encoding($false)))
$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)|Out-Null
if($e.Count -eq 0){Write-Output 'SUBTITLE_FORMAT_ALIGNMENT_PARSE_PASS'}else{$e|ForEach-Object{$_.Message};throw 'Parse failed'}
