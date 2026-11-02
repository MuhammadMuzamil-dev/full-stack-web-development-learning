#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$RequestUri)
$ErrorActionPreference = 'Stop'

function Read-ProtocolQuery {
    param([string]$Query)
    $result = @{}
    foreach ($part in ($Query.TrimStart('?') -split '&')) {
        if (-not $part) { continue }
        $pos = $part.IndexOf('=')
        if ($pos -lt 0) { $key = $part; $value = '' }
        else { $key = $part.Substring(0,$pos); $value = $part.Substring($pos+1) }
        $key = [Uri]::UnescapeDataString($key.Replace('+',' '))
        $value = [Uri]::UnescapeDataString($value.Replace('+',' '))
        $result[$key] = $value
    }
    return $result
}

function Test-AllowedYouTubeUrl {
    param([string]$Candidate)
    try {
        $u = [Uri]$Candidate
        if ($u.Scheme -ne 'https') { return $false }
        $h = $u.Host.ToLowerInvariant()
        return ($h -eq 'youtu.be' -or $h -eq 'youtube.com' -or $h.EndsWith('.youtube.com'))
    } catch { return $false }
}

function Read-YouTubeLink {
    param([string]$PromptText)
    while ($true) {
        $candidate = (Read-Host $PromptText).Trim()
        if (Test-AllowedYouTubeUrl $candidate) { return $candidate }
        Write-Host 'That does not look like a secure YouTube link. Copy it again from YouTube Share > Copy link.' -ForegroundColor Yellow
    }
}

try {
    $parsedRequest = [Uri]$RequestUri
    if ($parsedRequest.Scheme -ne 'ytcourse' -or $parsedRequest.Host -ne 'download') {
        throw 'This downloader link is not recognized. Open it from a Notes & Links HTML page.'
    }
    $query = Read-ProtocolQuery $parsedRequest.Query
    $videoUrl = [string]$query['url']
    if (-not (Test-AllowedYouTubeUrl $videoUrl)) {
        throw 'For safety, this button accepts only HTTPS links from youtube.com or youtu.be.'
    }
    $displayTitle = [string]$query['title']
    if ([string]::IsNullOrWhiteSpace($displayTitle)) { $displayTitle = 'the selected YouTube video' }
    $quality = 720
    $requestedQuality = 0
    if ([int]::TryParse([string]$query['quality'], [ref]$requestedQuality) -and $requestedQuality -ge 144 -and $requestedQuality -le 4320) { $quality = $requestedQuality }
    $fragments = 8
    $requestedFragments = 0
    if ([int]::TryParse([string]$query['fragments'], [ref]$requestedFragments) -and $requestedFragments -ge 1 -and $requestedFragments -le 16) { $fragments = $requestedFragments }

    $downloaderPath = Join-Path $PSScriptRoot 'yt-course-downloader-pro.ps1'
    if (-not (Test-Path -LiteralPath $downloaderPath -PathType Leaf)) { throw 'The installed downloader script is missing. Run Install-YT-Course-Protocol.cmd again from the extracted ZIP.' }

    $links = [System.Collections.Generic.List[string]]::new()
    $links.Add($videoUrl)
    Write-Host ''
    Write-Host 'YT Course Downloader — opened from your HTML page' -ForegroundColor Cyan
    Write-Host ('Video: ' + $displayTitle) -ForegroundColor Cyan
    Write-Host 'The video link was checked. Nothing downloads until you confirm at the end.' -ForegroundColor Green
    while ($true) {
        $extra = (Read-Host 'Optional: paste another secure YouTube link, or press Enter to continue').Trim()
        if ([string]::IsNullOrWhiteSpace($extra)) { break }
        if (Test-AllowedYouTubeUrl $extra) {
            if (-not $links.Contains($extra)) { $links.Add($extra) }
        } else {
            Write-Host 'That link was not added. Use an https://youtube.com or https://youtu.be link.' -ForegroundColor Yellow
        }
    }

    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Choose where to save the video files.'
    $picker.ShowNewFolderButton = $true
    $defaultFolder = Join-Path ([Environment]::GetFolderPath('MyVideos')) 'YT Courses'
    if (-not (Test-Path -LiteralPath $defaultFolder)) { New-Item -ItemType Directory -Path $defaultFolder -Force | Out-Null }
    $picker.SelectedPath = $defaultFolder
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host 'Folder selection cancelled. Nothing was downloaded.' -ForegroundColor Yellow
        exit 0
    }
    $saveFolder = $picker.SelectedPath

    $qualityInput = Read-Host ("Maximum quality in pixels [$quality]; press Enter to keep it")
    if (-not [string]::IsNullOrWhiteSpace($qualityInput)) {
        $parsed = 0
        if (-not [int]::TryParse($qualityInput, [ref]$parsed) -or $parsed -lt 144 -or $parsed -gt 4320) { throw 'Quality must be a number from 144 to 4320, such as 480, 720 or 1080.' }
        $quality = $parsed
    }
    $speedInput = Read-Host ("Speed setting 1-16 [$fragments]; press Enter to keep it")
    if (-not [string]::IsNullOrWhiteSpace($speedInput)) {
        $parsedSpeed = 0
        if (-not [int]::TryParse($speedInput, [ref]$parsedSpeed) -or $parsedSpeed -lt 1 -or $parsedSpeed -gt 16) { throw 'Speed setting must be a number from 1 to 16.' }
        $fragments = $parsedSpeed
    }

    Write-Host ''
    Write-Host 'Please check:' -ForegroundColor Cyan
    Write-Host ('Save folder: ' + $saveFolder)
    Write-Host ('Links: ' + $links.Count)
    Write-Host ("Maximum quality: ${quality}p; if missing, the highest lower quality will be used.")
    Write-Host ('Concurrent fragments: ' + $fragments)
    Write-Host 'Each final MP4 is created after its audio finishes and FFmpeg merges the streams.' -ForegroundColor Cyan
    $confirm = Read-Host 'Press Enter or type Y to start; type N to cancel'
    if (-not [string]::IsNullOrWhiteSpace($confirm) -and $confirm.Trim() -notmatch '^(?i)y(es)?$') {
        Write-Host 'Cancelled. Nothing was downloaded.' -ForegroundColor Yellow
        exit 0
    }

    $arguments = @{
        OutputDirectoryOverride = $saveFolder
        LinksOverride = [string[]]$links.ToArray()
        QualityOverride = $quality
        ConcurrentFragmentsOverride = $fragments
        NoPause = $true
    }
    & $downloaderPath @arguments
    if (-not $?) { Write-Host 'The downloader reported a problem. Read the messages above and the log in the save folder.' -ForegroundColor Yellow }
} catch {
    Write-Host ('Could not start the downloader: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    Write-Host ''
    Read-Host 'Press Enter to close this window' | Out-Null
}
