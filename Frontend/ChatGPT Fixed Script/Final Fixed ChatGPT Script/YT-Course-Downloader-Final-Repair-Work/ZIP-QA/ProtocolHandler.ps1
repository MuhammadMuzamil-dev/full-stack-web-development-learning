#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$RequestUri)
$ErrorActionPreference = 'Stop'
function Test-YouTubeLink([string]$Candidate) {
    try { $u=[Uri]$Candidate; if($u.Scheme -ne 'https'){return $false}; $h=$u.Host.ToLowerInvariant(); return ($h -eq 'youtu.be' -or $h -eq 'youtube.com' -or $h.EndsWith('.youtube.com')) } catch { return $false }
}
function Parse-Query([string]$Query) {
    $d=@{}; foreach($part in ($Query.TrimStart('?') -split '&')) { if(-not $part){continue}; $p=$part.IndexOf('='); if($p -lt 0){$k=$part;$v=''}else{$k=$part.Substring(0,$p);$v=$part.Substring($p+1)}; $k=[Uri]::UnescapeDataString($k.Replace('+',' ')); $v=[Uri]::UnescapeDataString($v.Replace('+',' ')); $d[$k]=$v }; return $d
}
try {
    $uri=[Uri]$RequestUri
    if($uri.Scheme -ne 'ytcourse' -or $uri.Host -ne 'download'){throw 'This link is not recognized. Open it from a Notes & Links page.'}
    $q=Parse-Query $uri.Query; $video=[string]$q['url']
    if(-not (Test-YouTubeLink $video)){throw 'Only HTTPS links from youtube.com or youtu.be are allowed.'}
    $title=[string]$q['title']; if(-not $title){$title='your chosen video'}
    $quality=720; $n=0; if([int]::TryParse([string]$q['quality'],[ref]$n) -and $n -ge 144 -and $n -le 4320){$quality=$n}
    $fragments=8; $n=0; if([int]::TryParse([string]$q['fragments'],[ref]$n) -and $n -ge 1 -and $n -le 16){$fragments=$n}
    $downloader=Join-Path $PSScriptRoot 'yt-course-downloader-final.ps1'
    if(-not (Test-Path -LiteralPath $downloader -PathType Leaf)){throw 'The downloader file is missing. Run Install-YT-Course-Protocol.cmd again from the extracted ZIP.'}
    Write-Host 'YT Course Downloader — opened from the HTML page' -ForegroundColor Cyan
    Write-Host ('Video: '+$title) -ForegroundColor Cyan
    Write-Host 'The link is checked. Nothing downloads until you confirm.' -ForegroundColor Green
    $links=[System.Collections.Generic.List[string]]::new(); $links.Add($video)
    while($true){$extra=(Read-Host 'Optional: paste another YouTube link, or press Enter to continue').Trim(); if([string]::IsNullOrWhiteSpace($extra)){break}; if(Test-YouTubeLink $extra){if(-not $links.Contains($extra)){$links.Add($extra)}}else{Write-Host 'That link was not added. Use an HTTPS YouTube link.' -ForegroundColor Yellow}}
    Add-Type -AssemblyName System.Windows.Forms
    $picker=New-Object System.Windows.Forms.FolderBrowserDialog; $picker.Description='Choose where to save the videos.'; $picker.ShowNewFolderButton=$true
    $default=Join-Path ([Environment]::GetFolderPath('MyVideos')) 'YT Courses'; if(-not (Test-Path -LiteralPath $default)){New-Item -ItemType Directory -Path $default -Force | Out-Null}; $picker.SelectedPath=$default
    if($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){Write-Host 'Folder choice cancelled. Nothing was downloaded.' -ForegroundColor Yellow; return}
    $folder=$picker.SelectedPath
    $qIn=Read-Host "Maximum quality in pixels [$quality] (e.g. 480, 720, 1080; lower quality is picked automatically if needed)"; if($qIn){$n=0;if(-not [int]::TryParse($qIn,[ref]$n) -or $n -lt 144 -or $n -gt 4320){throw 'Quality must be 144 to 4320.'};$quality=$n}
    $sIn=Read-Host "Parallel fragments 1-16 [$fragments] (try 8 first)"; if($sIn){$n=0;if(-not [int]::TryParse($sIn,[ref]$n) -or $n -lt 1 -or $n -gt 16){throw 'Speed setting must be 1 to 16.'};$fragments=$n}
    Write-Host ''; Write-Host "Save folder: $folder"; Write-Host "Links: $($links.Count)"; Write-Host "Maximum quality: ${quality}p"; Write-Host "Parallel fragments: $fragments; HTTP chunk size: 10M"; Write-Host 'The final MP4 is available after its audio finishes and FFmpeg merges the streams.' -ForegroundColor Cyan
    $confirm=Read-Host 'Press Enter or type Y to start; N cancels'; if($confirm -and $confirm.Trim() -notmatch '^(?i)y(es)?$'){Write-Host 'Cancelled. Nothing was downloaded.' -ForegroundColor Yellow; return}
    $runParameters=@{ OutputDirectoryOverride=$folder; LinksOverride=[string[]]$links.ToArray(); QualityOverride=$quality; ConcurrentFragmentsOverride=$fragments; CompanionSourceDirectoryOverride=$PSScriptRoot; NoPause=$true }
    & $downloader @runParameters
} catch { Write-Host ('Could not start the downloader: '+$_.Exception.Message) -ForegroundColor Red } finally { Write-Host ''; Read-Host 'Press Enter to close this window' | Out-Null }
