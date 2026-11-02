$ErrorActionPreference='Stop'
$dir='C:\Users\User\Desktop\full-stack-web-development-learning\Frontend\ChatGPT Fixed Script\Final Fixed ChatGPT Script\YT-Course-Downloader-Final-Repair-Work\yt-course-downloader-final-subtitle-429-fix'
$p=Join-Path $dir 'yt-course-downloader-final.ps1'
$s=[IO.File]::ReadAllText($p)
function Replace-Exact([string]$old,[string]$new,[string]$label) {
 if(-not $s.Contains($old)){throw "Patch anchor missing: $label"}
 $script:s=$script:s.Replace($old,$new)
 Write-Output "PATCHED $label"
}
Replace-Exact @'
    $script:MetadataTemplate = Join-Path $script:OutputDirectory ("%(playlist_index&{} - |)s%(title)s [max-" + $script:Quality + "p].%(ext)s")
    $script:DownloadTemplate = Join-Path $script:OutputDirectory '%(playlist_index&{} - |)s%(title)s [%(height)sp].%(ext)s'
'@ @'
    # Playlist folder -> video folder -> media, HTML notes and optional SRT.
    $script:MetadataTemplate = Join-Path $script:OutputDirectory ("%(playlist_title|Videos)s/%(title)s/%(title)s [%(height)sp].%(ext)s")
    $script:DownloadTemplate = Join-Path $script:OutputDirectory '%(playlist_title|Videos)s/%(title)s/%(title)s [%(height)sp].%(ext)s'
'@ 'nested output templates'
Replace-Exact @'
    $files = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.info.json' -File -ErrorAction SilentlyContinue)
'@ @'
    $files = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.info.json' -File -Recurse -ErrorAction SilentlyContinue)
'@ 'recursive info files'
Replace-Exact @'
    $subtitleTemplate = Join-Path $OutputDirectory '%(title)s [%(height)sp].%(ext)s'
'@ @'
    $subtitleTemplate = $DownloadTemplate
'@ 'subtitle output template'
Replace-Exact @'
    $subtitleFiles = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.srt' -File -ErrorAction SilentlyContinue |
'@ @'
    $subtitleFiles = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.srt' -File -Recurse -ErrorAction SilentlyContinue |
'@ 'recursive subtitle scan'
Replace-Exact @'
        $candidateVideo = Join-Path $OutputDirectory ($subtitleStem + '.mp4')
'@ @'
        $candidateVideo = Join-Path $subtitle.DirectoryName ($subtitleStem + '.mp4')
'@ 'subtitle matching folder'
Replace-Exact @'
    $files = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.mp4' -File -ErrorAction SilentlyContinue |
'@ @'
    $files = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.mp4' -File -Recurse -ErrorAction SilentlyContinue |
'@ 'recursive final video scan'
Replace-Exact @'
    $localVideos = @(Get-ChildItem -LiteralPath $OutputDirectory -File -ErrorAction SilentlyContinue |
'@ @'
    $localVideos = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse -ErrorAction SilentlyContinue |
'@ 'recursive local video scan'
Replace-Exact @'
        $expectedHtml = Join-Path $OutputDirectory ($videoFile.BaseName + ' - Notes & Links.html')
'@ @'
        $expectedHtml = Join-Path $videoFile.DirectoryName ($videoFile.BaseName + ' - Notes & Links.html')
'@ 'notes beside each video'
Replace-Exact @'
        & yt-dlp --skip-download --no-warnings --write-info-json --no-write-playlist-metafiles --windows-filenames --output $MetadataTemplate $url
'@ @'
        & yt-dlp --skip-download --no-warnings --write-info-json --no-write-playlist-metafiles --windows-filenames --format $FormatSelector --format-sort-force --format-sort $FormatSort --output $MetadataTemplate $url
'@ 'metadata format matches download'
[IO.File]::WriteAllText($p,$s,(New-Object System.Text.UTF8Encoding($false)))
$encPath=Join-Path $dir 'yt-course-downloader-final-encoded.ps1'
$enc=[IO.File]::ReadAllText($encPath)
$payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
$enc=[regex]::Replace($enc,'(?s)(\$payload\s*=\s*@''\s*).*?(\s*''@)','$1'+$payload+'$2',1)
[IO.File]::WriteAllText($encPath,$enc,(New-Object System.Text.UTF8Encoding($false)))
foreach($f in @($p,$encPath)){
 $t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e)|Out-Null
 if($e.Count -eq 0){Write-Output ('PARSE_PASS '+[IO.Path]::GetFileName($f))}
 else{Write-Output ('PARSE_FAIL '+[IO.Path]::GetFileName($f)+' count='+$e.Count);$e|Select-Object -First 8|ForEach-Object{$_.Message}}
}
$m=[regex]::Match($enc,'(?s)\$payload\s*=\s*@''\s*(.*?)\s*''@')
$decoded=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.Groups[1].Value -replace '\s','')))
if($decoded -ceq [IO.File]::ReadAllText($p)){Write-Output 'ENCODED_PARITY_PASS'}else{Write-Output 'ENCODED_PARITY_FAIL'}
