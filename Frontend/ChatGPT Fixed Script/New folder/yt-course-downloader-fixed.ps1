#requires -Version 5.1
<#
YT-DLP Course Downloader + HTML Notes
-------------------------------------
Readable, editable PowerShell script.

Before running:
1. Edit $Quality (720 or 1080) and the URLs in $Links below.
2. Open PowerShell in this folder and run:
   .\yt-course-downloader-fixed.ps1

Features:
- Downloads one or more videos or playlists.
- Enforces a maximum video height of 720p or 1080p.
- Resumes partial downloads and keeps a download archive.
- Downloads English subtitles when available, converts them to SRT and attempts to embed them.
- Adds chapters, source/playlist links, channel, duration, description and a re-download command to HTML notes.
- Adds a collapsible usage/troubleshooting accordion to newly generated and existing HTML notes.
- Checks free disk space before the large video download step.
- Does not automatically delete partial video files.
#>

$ErrorActionPreference = 'Stop'

# ========================= USER SETTINGS =========================
$Quality = 720  # Use 720 or 1080. This is a maximum height, not a guaranteed exact resolution.
$Links = @(
    "https://youtube.com/playlist?list=PLxf3-FrL8GzQcrbIJJaAxuRvxgYSSRcBT&si=Y791CWIj2UX6SHY9",
    "",
    ""
)
$ConcurrentFragments = 6 # 1-8 recommended. Higher is not always faster.
$MinimumFreeGB = 4       # Download step pauses below this free-space amount.
# =================================================================

$OutputDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$OutputTemplate = Join-Path $OutputDirectory '%(playlist_index&{} - |)s%(title)s.%(ext)s'
$ArchivePath = Join-Path $OutputDirectory 'downloaded_history.txt'
$LogPath = Join-Path $OutputDirectory 'yt-dlp-course-downloader.log'

function Write-Status {
    param(
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory=$true)][string]$Message
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] [$Level] $Message"
    try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
    switch ($Level) {
        'OK'    { Write-Host $Message -ForegroundColor Green }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        default { Write-Host $Message -ForegroundColor Cyan }
    }
}

function Get-InfoValue {
    param([object]$Info, [string]$Name)
    if ($null -eq $Info) { return $null }
    $property = $Info.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-VideoUrl {
    param([object]$Info)
    $url = Get-InfoValue $Info 'webpage_url'
    if ($url -and ([string]$url -match '^https?://')) { return [string]$url }

    $id = Get-InfoValue $Info 'id'
    if ($id) { return "https://www.youtube.com/watch?v=$id" }
    return 'https://www.youtube.com/'
}

function Get-RealPlaylistUrl {
    param([object]$Info)

    $url = Get-InfoValue $Info 'playlist_webpage_url'
    if ($url -and ([string]$url -match '^https?://(www\.)?youtube\.com/playlist\?list=')) {
        return [string]$url
    }

    $playlistId = Get-InfoValue $Info 'playlist_id'
    $videoId = Get-InfoValue $Info 'id'
    if ($playlistId -and $playlistId -ne $videoId -and ([string]$playlistId -notmatch '^ytsearch')) {
        return "https://www.youtube.com/playlist?list=$playlistId"
    }
    return $null
}

function Get-ReDownloadCommand {
    param(
        [Parameter(Mandatory=$true)][string]$VideoUrl,
        [int]$SelectedQuality = 720,
        [int]$Fragments = 4
    )

    # A separate output filename avoids overwriting the existing download.
    return ('yt-dlp -N {0} --continue --retries 5 --fragment-retries 10 --retry-sleep 2 --file-access-retries 3 -f "bv*[height<={1}]+ba/b[height<={1}]" -S "ext:mp4:m4a,+size,+br" --merge-output-format mp4 --embed-chapters --write-subs --write-auto-subs --sub-langs "en.*,en" --convert-subs srt --embed-subs -o "%(title)s (re-download) [%(id)s].%(ext)s" "{2}"' -f $Fragments, $SelectedQuality, $VideoUrl)
}

function Get-HelpAccordionHtml {
    param(
        [int]$SelectedQuality = 720,
        [int]$Fragments = 4,
        [double]$RequiredFreeGB = 4
    )

    return @"
<details id="download-help" style="margin-top:18px;background:#fff;border:1px solid #cbd5e1;border-radius:8px;padding:14px;">
  <summary style="cursor:pointer;font-weight:700;color:#1d4ed8;">📘 Open download steps, quality/speed settings and troubleshooting</summary>
  <div style="margin-top:12px;">
    <h3>1. Copy and run the re-download command</h3>
    <p>Click the <b>Copy command</b> button beside the command above. Open PowerShell in this video folder, paste with <b>Ctrl+V</b>, then press <b>Enter</b>. You can also select the command text and press <b>Ctrl+C</b> manually.</p>
    <p>To open PowerShell in this folder: open the folder in File Explorer, click the address bar, type <code>powershell</code>, and press Enter. Alternatively, open PowerShell and run <code>cd "C:\Users\User\Desktop\full-stack-web-development-learning\Frontend"</code>.</p>
    <h3>2. Change video quality</h3>
    <p>The current script setting is <code>`$Quality = $SelectedQuality</code>. Use <code>720</code> for a smaller download or <code>1080</code> for higher detail and larger files. For the command above, change both occurrences of <code>height&lt;=$SelectedQuality</code> to <code>height&lt;=1080</code> or <code>height&lt;=720</code> if you want a different limit. Higher resolution does not guarantee better source quality.</p>
    <h3>3. Adjust download speed carefully</h3>
    <p>The script currently uses <code>-N $Fragments</code> concurrent fragments. In the main script, change <code>`$ConcurrentFragments = $Fragments</code> to a value from <code>1</code> to <code>8</code>. Try <code>4</code> first; <code>6</code> or <code>8</code> may help on a fast connection, but can also trigger YouTube rate limiting (HTTP 429). This setting cannot make the internet connection itself faster.</p>
    <h3>4. If “No space left on device” appears</h3>
    <p>The script skips the large download step when the output drive has less than <code>$RequiredFreeGB GB</code> free. Free space on the drive that holds this folder and retry. Incomplete files often end in <code>.part</code>. Do not delete them if you want to attempt a resume. Old partial files made with a different format/quality may not be reusable; inspect them before deciding whether to remove them.</p>
    <h3>5. If subtitles fail with HTTP 429</h3>
    <p>HTTP 429 means the server is temporarily rate-limiting requests. The video may still download while subtitles fail. Reduce concurrency to <code>2</code> or <code>4</code>, wait before retrying, and try again later. English subtitles are included only when YouTube provides them.</p>
    <h3>6. If a video is missing or only a .part file exists</h3>
    <p>A <code>.part</code> file is an incomplete download and is not a finished, playable video. Verify free space, confirm <code>yt-dlp --version</code> and <code>ffmpeg -version</code> work in PowerShell, then rerun <code>.\yt-course-downloader-fixed.ps1</code>. The download archive skips items already recorded as completed.</p>
    <h3>7. Required tools</h3>
    <p>Both <code>yt-dlp</code> and <code>FFmpeg</code> should be installed and available in PATH. Official references:
       <a href="https://github.com/yt-dlp/yt-dlp#installation" target="_blank" rel="noopener noreferrer">yt-dlp installation</a> and
       <a href="https://ffmpeg.org/download.html" target="_blank" rel="noopener noreferrer">FFmpeg downloads</a>.</p>
    <p><b>Privacy/safety note:</b> the “encoded” companion script is Base64-encoded, not encrypted. Prefer the readable script when you need to inspect or edit settings.</p>
  </div>
</details>
"@
}

function Get-CopyButtonScript {
    return @'
<script>
function copyDownloadCommand() {
  const command = document.getElementById("redownload-command");
  const status = document.getElementById("copy-status");
  if (!command) return;
  const text = command.innerText || command.textContent || "";
  const fallback = () => {
    const area = document.createElement("textarea");
    area.value = text;
    area.style.position = "fixed";
    area.style.left = "-9999px";
    document.body.appendChild(area);
    area.select();
    let copied = false;
    try { copied = document.execCommand("copy"); } catch (e) {}
    area.remove();
    if (status) status.textContent = copied ? "Copied." : "Select the command and press Ctrl+C.";
  };
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text)
      .then(() => { if (status) status.textContent = "Copied."; })
      .catch(fallback);
  } else {
    fallback();
  }
}
</script>
'@
}

function New-VideoNotesHtml {
    param(
        [Parameter(Mandatory=$true)][object]$Info,
        [Parameter(Mandatory=$true)][string]$HtmlPath,
        [Parameter(Mandatory=$true)][string]$DisplayTitle
    )

    $videoUrl = Get-VideoUrl $Info
    $safeVideoUrl = [System.Net.WebUtility]::HtmlEncode($videoUrl)
    $channelValue = Get-InfoValue $Info 'uploader'
    if (-not $channelValue) { $channelValue = Get-InfoValue $Info 'channel' }
    if (-not $channelValue) { $channelValue = 'N/A' }
    $channel = [System.Net.WebUtility]::HtmlEncode([string]$channelValue)

    $duration = Get-InfoValue $Info 'duration_string'
    if (-not $duration) {
        $durationSeconds = Get-InfoValue $Info 'duration'
        if ($null -ne $durationSeconds) {
            $duration = [TimeSpan]::FromSeconds([double]$durationSeconds).ToString('hh\:mm\:ss')
        } else { $duration = 'N/A' }
    }
    $duration = [System.Net.WebUtility]::HtmlEncode([string]$duration)

    $playlistHtml = ''
    $playlistUrl = Get-RealPlaylistUrl $Info
    if ($playlistUrl) {
        $safePlaylistUrl = [System.Net.WebUtility]::HtmlEncode($playlistUrl)
        $playlistTitle = Get-InfoValue $Info 'playlist_title'
        if (-not $playlistTitle) { $playlistTitle = 'Open YouTube playlist' }
        $safePlaylistTitle = [System.Net.WebUtility]::HtmlEncode([string]$playlistTitle)
        $playlistHtml = "<div style='margin-top:8px;'><b>📂 Full Playlist Link:</b> <a href='$safePlaylistUrl' target='_blank' rel='noopener noreferrer' style='color:#0284c7;font-weight:700;'>$safePlaylistTitle</a></div>"
    }

    $chaptersHtml = ''
    $chapters = Get-InfoValue $Info 'chapters'
    if ($chapters) {
        $chapterRows = foreach ($chapter in $chapters) {
            $seconds = [int][math]::Floor([double]$chapter.start_time)
            $timestamp = [TimeSpan]::FromSeconds($seconds).ToString('hh\:mm\:ss')
            $chapterTitle = [System.Net.WebUtility]::HtmlEncode([string]$chapter.title)
            $chapterUrl = [System.Net.WebUtility]::HtmlEncode("$videoUrl&t=${seconds}s")
            "<li><a href='$chapterUrl' target='_blank' rel='noopener noreferrer' style='color:#2563eb;font-weight:600;text-decoration:none;'>[$timestamp]</a> $chapterTitle</li>"
        }
        $chaptersHtml = "<div style='background:#fff;padding:18px;border-radius:8px;border:1px solid #e2e8f0;margin-bottom:18px;'><h3 style='margin-top:0;'>⏱️ Video Chapters (click to jump on YouTube)</h3><ul style='line-height:1.8;margin:0;padding-left:20px;'>$($chapterRows -join '')</ul></div>"
    }

    $description = [string](Get-InfoValue $Info 'description')
    $safeDescription = [System.Net.WebUtility]::HtmlEncode($description)
    $linkedDescription = [regex]::Replace(
        $safeDescription,
        '(https?://[^\s<"]+)',
        '<a href="$1" target="_blank" rel="noopener noreferrer" style="color:#2563eb;font-weight:600;">$1</a>'
    )

    $command = Get-ReDownloadCommand -VideoUrl $videoUrl -SelectedQuality $Quality -Fragments $ConcurrentFragments
    $safeCommand = [System.Net.WebUtility]::HtmlEncode($command)
    $safeTitle = [System.Net.WebUtility]::HtmlEncode($DisplayTitle)
    $helpAccordion = Get-HelpAccordionHtml -SelectedQuality $Quality -Fragments $ConcurrentFragments -RequiredFreeGB $MinimumFreeGB
    $copyScript = Get-CopyButtonScript

    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$safeTitle</title>
</head>
<body style="font-family:Segoe UI,Arial,sans-serif;max-width:920px;margin:25px auto;padding:20px;background:#f8fafc;color:#0f172a;line-height:1.7;">
<h2 style="margin-top:0;border-bottom:2px solid #cbd5e1;padding-bottom:10px;">$safeTitle</h2>
<div style="background:#eff6ff;padding:16px;border-radius:8px;border:1px solid #bfdbfe;margin-bottom:18px;">
  <div><b>▶️ Direct Video Link:</b> <a href="$safeVideoUrl" target="_blank" rel="noopener noreferrer" style="color:#1d4ed8;font-weight:700;">$safeVideoUrl</a></div>
  $playlistHtml
  <div style="margin-top:8px;"><b>👤 Channel:</b> $channel &nbsp;|&nbsp; <b>⏳ Duration:</b> $duration</div>
  <div style="margin-top:10px;font-size:13px;background:#1e293b;color:#f8fafc;padding:8px 12px;border-radius:6px;font-family:Consolas,monospace;overflow-wrap:anywhere;">
    <b>🔄 Re-Download Command:</b><br>
    <code id="redownload-command" style="white-space:normal;">$safeCommand</code>
    <button type="button" onclick="copyDownloadCommand()" style="margin-left:8px;padding:5px 9px;cursor:pointer;">Copy command</button>
    <span id="copy-status" aria-live="polite"></span>
  </div>
</div>
$chaptersHtml
<div style="white-space:pre-wrap;overflow-wrap:anywhere;background:#fff;padding:20px;border-radius:8px;border:1px solid #e2e8f0;font-size:15px;">$linkedDescription</div>
$helpAccordion
$copyScript
</body>
</html>
"@

    Set-Content -LiteralPath $HtmlPath -Value $html -Encoding UTF8
}

function Export-NotesFromInfoFiles {
    $infoFiles = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.info.json' -File -ErrorAction SilentlyContinue)
    foreach ($infoFile in $infoFiles) {
        try {
            $info = Get-Content -LiteralPath $infoFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $baseName = $infoFile.Name -replace '\.info\.json$', ''
            $htmlPath = Join-Path $infoFile.DirectoryName "$baseName - Notes & Links.html"
            New-VideoNotesHtml -Info $info -HtmlPath $htmlPath -DisplayTitle $baseName
            # Delete metadata only after HTML generation succeeded.
            Remove-Item -LiteralPath $infoFile.FullName -Force -ErrorAction Stop
            Write-Status -Level 'OK' -Message "Created/updated HTML notes: $([System.IO.Path]::GetFileName($htmlPath))"
        } catch {
            Write-Status -Level 'WARN' -Message "Could not convert '$($infoFile.Name)' to HTML notes. Metadata file was kept. Details: $($_.Exception.Message)"
        }
    }
}

function Add-HelpAccordionToExistingHtml {
    $htmlFiles = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '* - Notes & Links.html' -File -ErrorAction SilentlyContinue)
    foreach ($htmlFile in $htmlFiles) {
        try {
            $html = Get-Content -LiteralPath $htmlFile.FullName -Raw -Encoding UTF8
            $changed = $false

            # Upgrade the old command in existing HTML files to use a real resolution cap and a non-overwriting output name.
            $urlMatch = [regex]::Match($html, '(?is)Direct Video Link:</b>\s*<a href=[''"]([^''"]+)[''"]')
            if ($urlMatch.Success) {
                $videoUrl = [System.Net.WebUtility]::HtmlDecode($urlMatch.Groups[1].Value)
                if ($videoUrl -match '^https?://') {
                    $command = Get-ReDownloadCommand -VideoUrl $videoUrl -SelectedQuality $Quality -Fragments $ConcurrentFragments
                    $safeCommand = [System.Net.WebUtility]::HtmlEncode($command)
                    $commandPattern = [regex]::new('(?is)(<b>[^<]*Re-Download Command:</b>\s*)(.*?)(</div>)')
                    $commandMatch = $commandPattern.Match($html)
                    if ($commandMatch.Success) {
                        $replacement = $commandMatch.Groups[1].Value +
                            "<br><code id='redownload-command' style='white-space:normal;overflow-wrap:anywhere;'>$safeCommand</code> " +
                            "<button type='button' onclick='copyDownloadCommand()' style='margin-left:8px;padding:5px 9px;cursor:pointer;'>Copy command</button> " +
                            "<span id='copy-status' aria-live='polite'></span>" +
                            $commandMatch.Groups[3].Value
                        $html = $html.Substring(0, $commandMatch.Index) + $replacement + $html.Substring($commandMatch.Index + $commandMatch.Length)
                        $changed = $true
                    }
                }
            }

            if ($html -notmatch 'id=["'']download-help["'']') {
                $help = Get-HelpAccordionHtml -SelectedQuality $Quality -Fragments $ConcurrentFragments -RequiredFreeGB $MinimumFreeGB
                $bodyIndex = $html.LastIndexOf('</body>', [System.StringComparison]::OrdinalIgnoreCase)
                if ($bodyIndex -ge 0) {
                    $html = $html.Insert($bodyIndex, "`r`n$help`r`n")
                } else {
                    $html += "`r`n$help`r`n"
                }
                $changed = $true
            }

            if ($html -notmatch 'function copyDownloadCommand') {
                $copyScript = Get-CopyButtonScript
                $bodyIndex = $html.LastIndexOf('</body>', [System.StringComparison]::OrdinalIgnoreCase)
                if ($bodyIndex -ge 0) {
                    $html = $html.Insert($bodyIndex, "`r`n$copyScript`r`n")
                } else {
                    $html += "`r`n$copyScript`r`n"
                }
                $changed = $true
            }

            if ($changed) {
                Set-Content -LiteralPath $htmlFile.FullName -Value $html -Encoding UTF8
                Write-Status -Level 'OK' -Message "Added/updated the accordion and command in: $($htmlFile.Name)"
            }
        } catch {
            Write-Status -Level 'WARN' -Message "Could not update existing HTML '$($htmlFile.Name)': $($_.Exception.Message)"
        }
    }
}

try {
    if ($Quality -ne 720 -and $Quality -ne 1080) {
        throw 'Quality must be 720 or 1080.'
    }
    if ($ConcurrentFragments -lt 1 -or $ConcurrentFragments -gt 8) {
        throw 'ConcurrentFragments must be between 1 and 8.'
    }

    if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
        throw 'yt-dlp was not found in PATH. Run "yt-dlp --version" in PowerShell and install it if needed.'
    }

    $ffmpegAvailable = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)
    if (-not $ffmpegAvailable) {
        Write-Status -Level 'WARN' -Message 'FFmpeg was not found in PATH. Notes can still be generated, but video/audio merging and subtitle embedding may fail.'
    }

    $activeLinks = @($Links | Where-Object {
        $_ -and ([string]$_).Trim() -and ([string]$_ -notmatch '^LINK_\d+$')
    })

    # 1. For local videos missing notes, search YouTube by filename.
    # Search results are best-effort and may not be the exact source video.
    $localVideos = @(Get-ChildItem -LiteralPath $OutputDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @('.mp4','.mkv','.webm') -and $_.Length -gt 1MB })

    foreach ($videoFile in $localVideos) {
        $expectedHtml = Join-Path $OutputDirectory "$($videoFile.BaseName) - Notes & Links.html"
        if (-not (Test-Path -LiteralPath $expectedHtml)) {
            $searchQuery = ($videoFile.BaseName -replace '(?i)\bfixed\b', '' -replace '[_]+', ' ').Trim()
            if ($searchQuery) {
                Write-Status -Level 'INFO' -Message "Searching YouTube metadata for local video: $($videoFile.Name)"
                $localInfoTemplate = Join-Path $OutputDirectory "$($videoFile.BaseName).%(ext)s"
                try {
                    & yt-dlp --skip-download --write-info-json --no-write-playlist-metafiles --ignore-errors --no-warnings -o $localInfoTemplate "ytsearch1:$searchQuery"
                    if ($LASTEXITCODE -ne 0) {
                        Write-Status -Level 'WARN' -Message "Metadata search returned exit code $LASTEXITCODE for '$($videoFile.Name)'."
                    }
                } catch {
                    Write-Status -Level 'WARN' -Message "Metadata search failed for '$($videoFile.Name)': $($_.Exception.Message)"
                }
            }
        }
    }

    # 2. Fetch lightweight metadata first so HTML notes can be created even when the drive lacks space for video files.
    foreach ($link in $activeLinks) {
        Write-Status -Level 'INFO' -Message "Fetching metadata and chapters for: $link"
        try {
            & yt-dlp --skip-download --write-info-json --no-write-playlist-metafiles --ignore-errors --no-warnings -o $OutputTemplate $link
            if ($LASTEXITCODE -ne 0) {
                Write-Status -Level 'WARN' -Message "Metadata fetch returned exit code $LASTEXITCODE for URL: $link"
            }
        } catch {
            Write-Status -Level 'WARN' -Message "Metadata fetch failed for URL '$link': $($_.Exception.Message)"
        }
    }

    # 3. Create notes now, before attempting large downloads.
    Export-NotesFromInfoFiles
    Add-HelpAccordionToExistingHtml

    # 4. Check free space before downloading large video streams.
    if ($activeLinks.Count -gt 0) {
        $driveName = ([System.IO.Path]::GetPathRoot($OutputDirectory)).Substring(0,1)
        $drive = Get-PSDrive -Name $driveName
        $freeGB = [math]::Round(($drive.Free / 1GB), 2)

        if ($freeGB -lt $MinimumFreeGB) {
            Write-Status -Level 'WARN' -Message "Skipping video downloads: only $freeGB GB free; at least $MinimumFreeGB GB is configured as the safety threshold. HTML notes were created/updated first."
            Write-Status -Level 'WARN' -Message 'Free disk space, then rerun this script. Existing .part files were not deleted.'
        } elseif (-not $ffmpegAvailable) {
            Write-Status -Level 'WARN' -Message 'Video download was skipped because FFmpeg is not available. Install FFmpeg, ensure ffmpeg.exe is in PATH, then rerun.'
        } else {
            Write-Status -Level 'INFO' -Message "Starting download at maximum $Quality-pixel height, with $ConcurrentFragments concurrent fragments. Free space: $freeGB GB."
            try {
                & yt-dlp `
                    --newline `
                    --continue `
                    --retries 5 `
                    --fragment-retries 10 `
                    --retry-sleep 2 `
                    --file-access-retries 3 `
                    --ignore-errors `
                    --download-archive $ArchivePath `
                    --no-write-playlist-metafiles `
                    --embed-chapters `
                    --write-subs `
                    --write-auto-subs `
                    --sub-langs 'en.*,en' `
                    --convert-subs srt `
                    --embed-subs `
                    --format "bv*[height<=$Quality]+ba/b[height<=$Quality]" `
                    --format-sort 'ext:mp4:m4a,+size,+br' `
                    --merge-output-format mp4 `
                    --trim-filenames 160 `
                    --output $OutputTemplate `
                    $activeLinks

                $downloadExitCode = $LASTEXITCODE
                if ($downloadExitCode -eq 0) {
                    Write-Status -Level 'OK' -Message 'yt-dlp finished without reporting a command-level error.'
                } else {
                    Write-Status -Level 'WARN' -Message "yt-dlp ended with exit code $downloadExitCode. Some videos/subtitles may have failed; review the console output and log."
                }
            } catch {
                Write-Status -Level 'ERROR' -Message "Download step failed: $($_.Exception.Message)"
            } finally {
                # Keep notes generation independent from video/subtitle download success.
                Export-NotesFromInfoFiles
                Add-HelpAccordionToExistingHtml
            }
        }
    } else {
        Write-Status -Level 'INFO' -Message 'No active download links were configured. Existing HTML notes were still checked for the accordion.'
    }
} catch {
    Write-Status -Level 'ERROR' -Message $_.Exception.Message
} finally {
    # This also runs after errors so any metadata JSON already written can still become HTML notes.
    Export-NotesFromInfoFiles
    Add-HelpAccordionToExistingHtml
    Write-Status -Level 'INFO' -Message "Finished. Output folder: $OutputDirectory"
    Write-Status -Level 'INFO' -Message "Log file: $LogPath"
}
