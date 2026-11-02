#requires -Version 5.1
<#
YT Course Downloader — Final Repair Build
- Maximum-quality selection: choose the best available height at or below the user's limit.
- Downloads source video/audio streams and merges them with FFmpeg; no video re-encoding.
- Uses HTTP range chunks (10 MiB) plus concurrent DASH/HLS fragments; speed still depends on the network/source.
- Creates HTML notes atomically so a disk-space error cannot truncate an existing notes file.
- Always reports the result and waits before closing unless -NoPause is explicitly passed by a wrapper.
#>
[CmdletBinding()]
param(
    [switch]$Gui,
    [switch]$NoPause,
    [string]$OutputDirectoryOverride,
    [string[]]$LinksOverride,
    [int]$QualityOverride = 0,
    [int]$ConcurrentFragmentsOverride = 0,
    [string]$CompanionSourceDirectoryOverride
)

$ErrorActionPreference = 'Stop'
$Quality = 720
$Links = @(
    'https://youtu.be/3LRZRSIh_KE?si=MHiZQRsJhakDlAE3',
    'https://youtu.be/IdlF1zsUN3M?si=WHUeQ-w2j_wPRKs8',
    'https://youtu.be/FxgM9k1rg0Q?si=pTO9Z1bw5kYryNjH'
)
$ConcurrentFragments = 8
$MinimumFreeGB = 4
$HttpChunkSize = '10M'
$OutputDirectory = if ($OutputDirectoryOverride) { $OutputDirectoryOverride } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$CompanionSourceDirectory = if ($CompanionSourceDirectoryOverride) { $CompanionSourceDirectoryOverride } elseif ($PSScriptRoot) { $PSScriptRoot } else { $OutputDirectory }
if ($QualityOverride -ge 144 -and $QualityOverride -le 4320) { $Quality = $QualityOverride }
if ($ConcurrentFragmentsOverride -ge 1 -and $ConcurrentFragmentsOverride -le 16) { $ConcurrentFragments = $ConcurrentFragmentsOverride }
if ($LinksOverride -and $LinksOverride.Count -gt 0) { $Links = @($LinksOverride) }
$RunStartTime = Get-Date
$ScriptFilePath = if ($PSCommandPath) { $PSCommandPath } else { $null }
$RunStarted = $false
$RunFailed = $false
$HadDownloadErrors = $false
$LogPath = Join-Path $OutputDirectory 'yt-dlp-course-downloader.log'

function Set-RunPaths {
    if (-not (Test-Path -LiteralPath $script:OutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $script:OutputDirectory -Force | Out-Null
    }
    $script:LogPath = Join-Path $script:OutputDirectory 'yt-dlp-course-downloader.log'
    $script:ArchivePath = Join-Path $script:OutputDirectory ("downloaded_history_upto{0}p.txt" -f $script:Quality)
    # Playlist folder -> video folder -> media, HTML notes and optional SRT.
    $script:MetadataTemplate = Join-Path $script:OutputDirectory ("%(playlist_title|Videos)s/%(title)s/%(title)s [%(height)sp].%(ext)s")
    $script:DownloadTemplate = Join-Path $script:OutputDirectory '%(playlist_title|Videos)s/%(title)s/%(title)s [%(height)sp].%(ext)s'
    $script:FormatSelector = 'bv*[height<={0}]+ba/b[height<={0}]' -f $script:Quality
    $script:FormatSort = "res:$($script:Quality),ext:mp4:m4a"
}

function Write-Status {
    param([ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO', [Parameter(Mandatory=$true)][string]$Message)
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
    switch ($Level) {
        'OK'    { Write-Host $Message -ForegroundColor Green }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        default { Write-Host $Message -ForegroundColor Cyan }
    }
}

function Write-AtomicText {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content)
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temp, $Content, ([System.Text.UTF8Encoding]::new($false)))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($temp, $Path, $null)
        } else {
            [System.IO.File]::Move($temp, $Path)
        }
    } catch {
        try { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } } catch {}
        throw
    }
}

function Test-YouTubeLink {
    param([string]$Candidate)
    try {
        $u = [Uri]$Candidate
        if ($u.Scheme -ne 'https') { return $false }
        $h = $u.Host.ToLowerInvariant()
        return ($h -eq 'youtu.be' -or $h -eq 'youtube.com' -or $h.EndsWith('.youtube.com'))
    } catch { return $false }
}

function Get-InfoValue {
    param([object]$Info, [string]$Name)
    if ($null -eq $Info) { return $null }
    $p = $Info.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value }
    return $null
}

function Get-VideoUrl {
    param([object]$Info)
    $url = Get-InfoValue $Info 'webpage_url'
    if ($url -and ([string]$url -match '^https://')) { return [string]$url }
    $id = Get-InfoValue $Info 'id'
    if ($id) { return "https://www.youtube.com/watch?v=$id" }
    return 'https://www.youtube.com/'
}

function Get-PlaylistUrl {
    param([object]$Info)
    $url = Get-InfoValue $Info 'playlist_webpage_url'
    if ($url -and ([string]$url -match '^https://(www\.)?youtube\.com/playlist\?list=')) { return [string]$url }
    $playlistId = Get-InfoValue $Info 'playlist_id'
    $videoId = Get-InfoValue $Info 'id'
    if ($playlistId -and $playlistId -ne $videoId -and ([string]$playlistId -notmatch '^ytsearch')) { return "https://www.youtube.com/playlist?list=$playlistId" }
    return $null
}

function Get-ReDownloadCommand {
    param([Parameter(Mandatory=$true)][string]$VideoUrl)
    return ('yt-dlp --http-chunk-size {0} --concurrent-fragments {1} --continue --retries 5 --fragment-retries 10 --retry-sleep 2 --file-access-retries 3 -f "{2}" --format-sort-force -S "{3}" --merge-output-format mp4 --embed-chapters --no-overwrites -o "%(title)s [%(height)sp].%(ext)s" "{4}"' -f $HttpChunkSize, $ConcurrentFragments, $FormatSelector, $FormatSort, $VideoUrl)
}

function Get-DownloadJsAndCss {
@'
<script>
function statusText(message) { const s = document.getElementById('copy-status'); if (s) s.textContent = message; }
function copyTextSafe(text, done) {
  const fallback = () => {
    const area = document.createElement('textarea'); area.value = text; area.style.position='fixed'; area.style.left='-9999px';
    document.body.appendChild(area); area.select(); let ok=false; try { ok=document.execCommand('copy'); } catch(e) {} area.remove(); done(ok);
  };
  if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(()=>done(true)).catch(()=>fallback());
  else fallback();
}
function copyDownloadCommand() {
  const c=document.getElementById('redownload-command'); if(!c) return;
  copyTextSafe(c.innerText || c.textContent || '', ok=>statusText(ok?'Command copied. Paste it into PowerShell and press Enter.':'Copy was blocked. Select the command and press Ctrl+C.'));
}
function jumpToCommand() {
  const c=document.getElementById('download-command-card'), t=document.getElementById('command-toast'); if(!c) return;
  c.scrollIntoView({behavior:'smooth',block:'center'}); c.classList.remove('command-highlight'); void c.offsetWidth; c.classList.add('command-highlight');
  if(t){t.textContent='Copy this command to download the video. To choose a different video, replace only the YouTube link at the end.';t.style.display='block';}
  window.setTimeout(()=>{c.classList.remove('command-highlight');if(t)t.style.display='none';},4500);
}
function copyPageContextForAI() {
  const chosen=document.getElementById('ai-tool'); const target=chosen?chosen.value:'chatgpt';
  const sites={chatgpt:'https://chatgpt.com/',gemini:'https://gemini.google.com/',claude:'https://claude.ai/'};
  const pageText=document.body.innerText || '';
  const links=Array.from(document.querySelectorAll('a[href]')).map(a=>(a.innerText||a.href)+' — '+a.href).join('\n');
  const source=document.getElementById('ai-embedded-script');
  const guide='You are helping me understand and troubleshoot my local YouTube course downloader. Read the context below first. Explain the problem in simple steps. Do not claim a script was tested unless its test result is included. Do not tell me to delete partial downloads unless you first explain the consequences.\n\nHTML PAGE TEXT:\n'+pageText+'\n\nLINKS:\n'+links+'\n\nREADABLE POWERSHELL SOURCE:\n'+(source?source.value:'The source script was not embedded in this HTML file.');
  window.open(sites[target]||sites.chatgpt,'_blank','noopener');
  copyTextSafe(guide,ok=>{const s=document.getElementById('ai-status');if(s)s.textContent=ok?'Page guide, links and script copied. Switch to the new AI tab, click its message box, press Ctrl+V, then Enter.':'Clipboard was blocked. Use the text box below: click inside, press Ctrl+A, Ctrl+C, then paste it into the AI tab.';});
}
</script>
<style>
.command-highlight{animation:cmdPulse 1s ease-in-out 2;box-shadow:0 0 0 4px #fbbf24!important}
@keyframes cmdPulse{0%,100%{background:#1e293b}50%{background:#164e63}}
#command-toast{display:none;position:sticky;top:8px;z-index:8;margin:8px 0;padding:10px 14px;border-radius:8px;background:#fef3c7;color:#92400e;border:1px solid #f59e0b;font-weight:700}
</style>
'@
}

function Get-HelpAccordionHtml {
@"
<div id="command-toast" role="status" aria-live="polite"></div>
<details id="download-help" style="margin-top:18px;background:#fff;border:1px solid #cbd5e1;border-radius:9px;padding:14px;">
<summary style="cursor:pointer;font-weight:700;color:#1d4ed8;">📘 Click to open the simple step-by-step guide</summary>
<div style="margin-top:12px;">
<h3>1. Download this video with the command above</h3>
<p>Click <b>Copy command</b>. Open PowerShell, paste with <b>Ctrl+V</b>, and press <b>Enter</b>. The command already contains this video's link.</p>
<p><button type="button" onclick="jumpToCommand()">⬆ Go back to the command</button></p>
<p>For a different video, open it on YouTube, click <b>Share</b>, then <b>Copy link</b>. Replace only the final YouTube link in the command. Keep the other words unchanged.</p>
<h3>2. What does video quality mean?</h3>
<p>The number is the <b>maximum video height</b>. If you choose ${Quality}p, the downloader uses ${Quality}p when available. If not, it chooses the best quality below it. For example, if 720p is missing but 480p exists, it uses 480p. It will never deliberately pick a higher resolution than your limit.</p>
<p>The selected resolution is shown before the download starts. The finished file name shows the actual height, such as <code>[720p]</code> or <code>[480p]</code>.</p>
<h3>3. Open PowerShell from this page</h3>
<ol>
<li>First time only: open the folder where you extracted this ZIP.</li>
<li>Double-click <code>Install-YT-Course-Protocol.cmd</code> and type <code>Y</code>.</li>
<li>Return to this HTML page and click the green <b>Open PowerShell for this video</b> button.</li>
<li>If the browser asks whether to open the downloader, choose <b>Open</b>.</li>
<li>Choose where to save the video, check the quality and speed, then press Enter or type <code>Y</code>.</li>
</ol>
<p>If this button does not open PowerShell, use <code>yt-course-downloader-final-gui.cmd</code> in the extracted ZIP folder. To remove the HTML launch feature later, run <code>Uninstall-YT-Course-Protocol.cmd</code>.</p>
<h3>4. Speed setting</h3>
<p>The chosen number controls the number of video pieces that can be downloaded in parallel when the stream type supports it. The script also uses 10 MB HTTP range chunks for supported direct HTTP streams. Try <code>8</code> first; if YouTube shows HTTP 429, wait and try <code>2</code> or <code>4</code>. This cannot exceed your internet speed or the server's limits.</p>
<h3>5. Why can the temporary MP4 have no sound?</h3>
<p>Some YouTube videos have separate video and audio streams. A file such as <code>.f398.mp4</code> is an unfinished intermediate video-only file. The downloader must finish the matching audio file and then FFmpeg merges them. Wait for the merge message and open the final file named like <code>[720p].mp4</code>, not the temporary <code>.f398.mp4</code>.</p>
<h3>6. File size and quality</h3>
<p>This downloader does not re-encode the video, so it preserves the selected source video stream. Clear 720p videos can be much larger than blurry 144p copies. Reducing a 1 GB file to 150 MB while promising no visible quality loss is not guaranteed. Optional HandBrake compression can reduce size but may reduce fine detail.</p>
<h3>7. If something goes wrong</h3>
<ul>
<li><b>“No space left on device”:</b> stop adding more videos until you have freed space; do not delete files ending in <code>.part</code> if you hope to resume them.</li>
<li><b>HTTP 429 for subtitles:</b> the video/audio download should continue first. Subtitles are optional and requested separately; if they are rate-limited, the finished video remains usable. Wait before trying subtitles again.</li>
<li><b>HTTP 429 for video/audio:</b> wait before retrying, and lower the speed setting to 2–4.</li>
<li><b>Only a .part file exists:</b> the download is unfinished. Keep the file and rerun the script with the same quality and output folder to attempt resume.</li>
<li><b>No sound:</b> wait for audio download and FFmpeg merge to finish; check that the final MP4—not the temporary video-only stream—has an audio track.</li>
<li><b>PowerShell closes too soon:</b> use the provided .cmd launcher, or open PowerShell in the video folder and run the script command from the guide. This build pauses before closing when run directly.</li>
</ul>
<h3>8. Required free tools</h3>
<p>This tool needs <a href="https://github.com/yt-dlp/yt-dlp" target="_blank" rel="noopener noreferrer">yt-dlp</a> and <a href="https://ffmpeg.org/download.html" target="_blank" rel="noopener noreferrer">FFmpeg</a>. Optional video compression: <a href="https://handbrake.fr/docs/en/latest/cli/command-line-reference.html" target="_blank" rel="noopener noreferrer">HandBrake command-line guide</a>.</p>
</div>
</details>
"@
}

function Get-AiHelpHtml {
    $source = ''
    try { if ($script:ScriptFilePath -and (Test-Path -LiteralPath $script:ScriptFilePath -PathType Leaf)) { $source = Get-Content -LiteralPath $script:ScriptFilePath -Raw -Encoding UTF8 } } catch {}
    $escapedSource = [System.Net.WebUtility]::HtmlEncode($source)
@"
<section id="ai-help-card" style="margin-top:20px;background:#f5f3ff;border:1px solid #ddd6fe;border-radius:9px;padding:15px;">
<h3 style="margin-top:0;">🤖 Need help? Ask an AI tool</h3>
<p>Choose ChatGPT, Gemini or Claude. The tool opens in a new tab and this page's words, links and readable script are copied. In the new tab, click the message box, press <b>Ctrl+V</b>, then press Enter. Nothing is sent automatically.</p>
<label for="ai-tool"><b>Choose an AI website:</b></label>
<select id="ai-tool" style="margin:6px;padding:7px;"><option value="chatgpt">ChatGPT</option><option value="gemini">Gemini</option><option value="claude">Claude</option></select>
<button type="button" onclick="copyPageContextForAI()" style="padding:8px 12px;cursor:pointer;">Open AI + copy this page</button>
<p id="ai-status" aria-live="polite" style="font-size:13px;"></p>
<details><summary style="cursor:pointer;">Manual copy if the button cannot copy</summary><p>Click inside the box, press <b>Ctrl+A</b>, then <b>Ctrl+C</b>. Open the AI tab, click its message box, press <b>Ctrl+V</b>, then Enter.</p><textarea id="ai-manual-context" rows="5" style="width:98%;"></textarea></details>
<textarea id="ai-embedded-script" style="display:none;">$escapedSource</textarea>
</section>
<script>
(function(){const a=document.getElementById('ai-manual-context');if(a){const s=document.getElementById('ai-embedded-script');a.value='Help me understand this YouTube course downloader. Explain problems simply, and do not claim unverified tests.\n\n'+(document.body.innerText||'')+'\n\nREADABLE SCRIPT:\n'+(s?s.value:'Not embedded');}})();
</script>
"@
}

function Get-NativeLaunchHtml {
    param([string]$VideoUrl, [string]$DisplayTitle)
    $uri = 'ytcourse://download?url=' + [Uri]::EscapeDataString($VideoUrl) + '&quality=' + $Quality + '&fragments=' + $ConcurrentFragments + '&title=' + [Uri]::EscapeDataString($DisplayTitle)
    $safeUri = [System.Net.WebUtility]::HtmlEncode($uri)
    $safeTitle = [System.Net.WebUtility]::HtmlEncode($DisplayTitle)
@"
<section id="native-launch-card" style="margin-top:14px;background:#f0fdf4;border:1px solid #bbf7d0;padding:14px;border-radius:9px;">
<h3 style="margin-top:0;">🖥️ Download from this page</h3>
<p>Video: <b>$safeTitle</b></p>
<p>After one-time setup, click below. If your browser asks to open the downloader, choose <b>Open</b>.</p>
<a href="$safeUri" style="display:inline-block;padding:9px 13px;border-radius:6px;background:#15803d;color:#fff;font-weight:700;text-decoration:none;">Open PowerShell for this video</a>
</section>
"@
}

function New-VideoNotesHtml {
    param([Parameter(Mandatory=$true)][object]$Info, [Parameter(Mandatory=$true)][string]$HtmlPath, [string]$DisplayTitle)
    $videoUrl = Get-VideoUrl $Info
    if (-not (Test-YouTubeLink $videoUrl)) { $videoUrl = 'https://www.youtube.com/' }
    if ([string]::IsNullOrWhiteSpace($DisplayTitle)) { $DisplayTitle = [string](Get-InfoValue $Info 'title') }
    $safeTitle = [System.Net.WebUtility]::HtmlEncode($DisplayTitle)
    $safeUrl = [System.Net.WebUtility]::HtmlEncode($videoUrl)
    $channel = [System.Net.WebUtility]::HtmlEncode([string](Get-InfoValue $Info 'uploader'))
    $duration = Get-InfoValue $Info 'duration_string'; if (-not $duration) { $duration = 'N/A' }
    $safeDuration = [System.Net.WebUtility]::HtmlEncode([string]$duration)
    $playlistHtml = ''
    $playlistUrl = Get-PlaylistUrl $Info
    if ($playlistUrl) {
        $safePlaylist = [System.Net.WebUtility]::HtmlEncode($playlistUrl)
        $playlistTitle = Get-InfoValue $Info 'playlist_title'; if (-not $playlistTitle) { $playlistTitle = 'YouTube Playlist' }
        $safePlaylistTitle = [System.Net.WebUtility]::HtmlEncode([string]$playlistTitle)
        $playlistHtml = "<div style='margin-top:8px;'><b>Full playlist:</b> <a href='$safePlaylist' target='_blank' rel='noopener noreferrer'>$safePlaylistTitle</a></div>"
    }
    $chaptersHtml = ''
    $chapters = Get-InfoValue $Info 'chapters'
    if ($chapters) {
        $rows = foreach ($ch in $chapters) {
            $seconds = [int][math]::Floor([double]$ch.start_time)
            $time = '{0:00}:{1:00}:{2:00}' -f [math]::Floor($seconds/3600), ([math]::Floor($seconds/60) % 60), ($seconds % 60)
            $safeCh = [System.Net.WebUtility]::HtmlEncode([string]$ch.title)
            $timeUrl = [System.Net.WebUtility]::HtmlEncode(($videoUrl + '&t=' + $seconds + 's'))
            "<li><a href='$timeUrl' target='_blank' rel='noopener noreferrer'>[$time]</a> $safeCh</li>"
        }
        $chaptersHtml = "<section style='background:#fff;padding:16px;border-radius:8px;border:1px solid #e2e8f0;margin-bottom:16px;'><h3>Video chapters (click to jump)</h3><ul>$($rows -join '')</ul></section>"
    }
    $description = [System.Net.WebUtility]::HtmlEncode([string](Get-InfoValue $Info 'description'))
$description = [regex]::Replace($description, '(https?://[^\\s<]+)', '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>')
    $command = [System.Net.WebUtility]::HtmlEncode((Get-ReDownloadCommand -VideoUrl $videoUrl))
    $nativeHtml = Get-NativeLaunchHtml -VideoUrl $videoUrl -DisplayTitle $DisplayTitle
    $helpHtml = Get-HelpAccordionHtml
    $aiHtml = Get-AiHelpHtml
    $jsCss = Get-DownloadJsAndCss
    $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>$safeTitle - Notes & Links</title></head>
<body style="font-family:Segoe UI,Arial,sans-serif;max-width:950px;margin:24px auto;padding:20px;background:#f8fafc;color:#0f172a;line-height:1.7;">
<h2 style="border-bottom:2px solid #cbd5e1;padding-bottom:10px;">$safeTitle</h2>
<div style="background:#eff6ff;padding:16px;border-radius:9px;border:1px solid #bfdbfe;margin-bottom:18px;">
<div><b>Direct video link:</b> <a href="$safeUrl" target="_blank" rel="noopener noreferrer">$safeUrl</a></div>
$playlistHtml
<div style="margin-top:8px;"><b>Channel:</b> $channel &nbsp;|&nbsp; <b>Duration:</b> $safeDuration</div>
<div id="download-command-card" style="margin-top:12px;font-size:13px;background:#1e293b;color:#f8fafc;padding:10px 12px;border-radius:7px;font-family:Consolas,monospace;overflow-wrap:anywhere;">
<b>Re-download command (maximum $($Quality)p):</b><br><code id="redownload-command" style="white-space:normal;overflow-wrap:anywhere;">$command</code><br>
<button type="button" onclick="copyDownloadCommand()" style="margin-top:8px;padding:7px 10px;cursor:pointer;">Copy command</button> <span id="copy-status" aria-live="polite"></span>
<div style="margin-top:8px;font-family:Segoe UI,Arial,sans-serif;font-size:12px;">To download a different video, replace only the last YouTube URL. Run this command in the folder where you want to save the file.</div>
</div></div>
$nativeHtml
$chaptersHtml
<div style="white-space:pre-wrap;overflow-wrap:anywhere;background:#fff;padding:20px;border-radius:8px;border:1px solid #e2e8f0;font-size:15px;">$description</div>
$helpHtml
$aiHtml
$jsCss
</body></html>
"@
    Write-AtomicText -Path $HtmlPath -Content $html
}

function Export-NotesFromInfoFiles {
    $files = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.info.json' -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        try {
            $info = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $baseName = $file.Name -replace '\.info\.json$',''
            $htmlPath = Join-Path $file.DirectoryName ($baseName + ' - Notes & Links.html')
            New-VideoNotesHtml -Info $info -HtmlPath $htmlPath -DisplayTitle ([string](Get-InfoValue $info 'title'))
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            Write-Status -Level 'OK' -Message "Created or repaired HTML notes: $([IO.Path]::GetFileName($htmlPath))"
        } catch {
            Write-Status -Level 'WARN' -Message "Could not make notes from '$($file.Name)'. Original metadata has been kept. $($_.Exception.Message)"
        }
    }
}

function Test-UsableFormat {
    param([Parameter(Mandatory=$true)][string]$Url)
    Write-Status -Level 'INFO' -Message "Checking available quality at or below ${Quality}p: $Url"
    $lines = @(& yt-dlp --simulate --no-warnings --format $FormatSelector --format-sort-force --format-sort $FormatSort --print 'SELECTED_FORMAT_OK::%(height)s::%(format_id)s::%(title)s' $Url 2>&1)
    $code = $LASTEXITCODE
    $found = $false
    foreach ($line in $lines) {
        $s = [string]$line
        if ($s -match 'SELECTED_FORMAT_OK::(\d+)::([^:]+)::(.*)$') {
            $found = $true; $h = [int]$Matches[1]; $fmt = $Matches[2]; $title = $Matches[3]
            if ($h -gt $Quality) { Write-Status -Level 'ERROR' -Message "Safety check rejected $h p, which is above the limit."; return $false }
            if ($h -lt $Quality) { Write-Status -Level 'WARN' -Message "${Quality}p is not available. Highest lower quality selected: ${h}p — $title (format $fmt)." }
            else { Write-Status -Level 'OK' -Message "Selected quality: ${h}p — $title (format $fmt)." }
        } elseif ($s -match '(?i)ERROR:|not available|requested format') {
            Write-Status -Level 'WARN' -Message $s
        }
    }
    if (-not $found -or $code -ne 0) {
        Write-Status -Level 'ERROR' -Message 'Could not confirm a usable video format. This link will be skipped; no low-quality surprise download will start.'
        return $false
    }
    return $true
}

function Test-FreeSpace {
    param([string]$Folder)
    try {
        $root = [IO.Path]::GetPathRoot($Folder)
        $driveName = $root.Substring(0,1)
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        $freeBytes = [double]$drive.Free
        $freeGB = [math]::Round($freeBytes / 1GB, 2)
        if ($freeGB -lt $MinimumFreeGB) {
            Write-Status -Level 'ERROR' -Message "Not enough free space: $freeGB GB available; at least $MinimumFreeGB GB is required before the next long download. Free space, then rerun to resume the .part files."
            return $false
        }
        Write-Status -Level 'INFO' -Message "Free space before this link: $freeGB GB (safety minimum $MinimumFreeGB GB)."
        return $true
    } catch {
        Write-Status -Level 'WARN' -Message "Could not check free disk space automatically: $($_.Exception.Message)"
        return $true
    }
}

function Add-OptionalSubtitles {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][datetime]$StartedAt
    )
    # Subtitles are deliberately a separate, non-blocking request. YouTube HTTP 429s
    # must never prevent the actual video/audio streams from downloading.
    Write-Status -Level 'INFO' -Message "Optional step: requesting English subtitles separately for $Url. If YouTube rate-limits them, the video remains downloaded."
    $subtitleTemplate = $DownloadTemplate
    $subtitleArgs = @(
        '--skip-download', '--no-warnings', '--ignore-errors', '--no-write-playlist-metafiles',
        '--write-subs', '--write-auto-subs', '--sub-langs', 'en.*,en', '--convert-subs', 'srt',
        '--format', $FormatSelector, '--format-sort-force', '--format-sort', $FormatSort,
        '--output', $subtitleTemplate, $Url
    )
    & yt-dlp @subtitleArgs
    $subtitleExit = $LASTEXITCODE

    $subtitleFiles = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.srt' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $StartedAt.AddSeconds(-2) })
    if ($subtitleFiles.Count -eq 0) {
        if ($subtitleExit -ne 0) {
            Write-Status -Level 'WARN' -Message "English subtitles were unavailable or rate-limited (exit code $subtitleExit). Video/audio result is not affected; no subtitle file was found."
        } else {
            Write-Status -Level 'INFO' -Message 'No English subtitle file was produced. The video/audio result is not affected.'
        }
        return
    }

    foreach ($subtitle in $subtitleFiles) {
        # yt-dlp normally names a converted English subtitle: "title [720p].en.srt".
        $subtitleStem = [IO.Path]::GetFileNameWithoutExtension($subtitle.Name) -replace '\.[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*$',''
        $candidateVideo = Join-Path $subtitle.DirectoryName ($subtitleStem + '.mp4')
        if (-not (Test-Path -LiteralPath $candidateVideo -PathType Leaf)) { continue }
        $videoFile = Get-Item -LiteralPath $candidateVideo
        if ($videoFile.LastWriteTime -lt $StartedAt.AddSeconds(-2)) { continue }

        $tempVideo = Join-Path $OutputDirectory ('.' + $videoFile.BaseName + '.subtitles-' + [Guid]::NewGuid().ToString('N') + '.tmp.mp4')
        try {
            Write-Status -Level 'INFO' -Message "Subtitles found. Attempting to add them to '$($videoFile.Name)' without re-encoding its video or audio."
            & ffmpeg -hide_banner -loglevel error -y -i $videoFile.FullName -i $subtitle.FullName `
                -map 0:v:0 -map '0:a?' -map 1:0 -map_metadata 0 -map_chapters 0 `
                -c:v copy -c:a copy -c:s mov_text -metadata:s:s:0 language=eng -movflags +faststart $tempVideo
            $ffmpegExit = $LASTEXITCODE
            if ($ffmpegExit -eq 0 -and (Test-Path -LiteralPath $tempVideo -PathType Leaf) -and (Get-Item -LiteralPath $tempVideo).Length -gt 1MB) {
                [IO.File]::Replace($tempVideo, $videoFile.FullName, $null)
                Write-Status -Level 'OK' -Message "English subtitles added to '$($videoFile.Name)'. Video and audio streams were copied, not re-encoded."
            } else {
                Write-Status -Level 'WARN' -Message "Could not embed subtitles in '$($videoFile.Name)' (FFmpeg exit $ffmpegExit). The original video is kept unchanged; subtitle file remains available."
            }
        } catch {
            Write-Status -Level 'WARN' -Message "Subtitle embedding failed safely for '$($videoFile.Name)': $($_.Exception.Message). Original video is kept."
        } finally {
            if (Test-Path -LiteralPath $tempVideo) { Remove-Item -LiteralPath $tempVideo -Force -ErrorAction SilentlyContinue }
        }
    }
    if ($subtitleExit -ne 0) {
        Write-Status -Level 'WARN' -Message "Subtitle service reported exit code $subtitleExit. Any completed video/audio file remains usable."
    }
}

function Test-FinalVideos {
    if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
        Write-Status -Level 'WARN' -Message 'ffprobe was not found, so automatic video/audio verification is unavailable.'
        return
    }
    $files = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.mp4' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $RunStartTime -and $_.Name -match '\[\d+p\]\.mp4$' -and $_.Name -notmatch '\.f\d+\.mp4$' })
    foreach ($file in $files) {
        try {
            $raw = & ffprobe -v error -show_entries stream=codec_type,width,height,codec_name -of json $file.FullName 2>$null
            $obj = ($raw -join "`n") | ConvertFrom-Json
            $streams = @($obj.streams)
            $v = @($streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1)
            $a = @($streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1)
            if ($v.Count -eq 0) { Write-Status -Level 'ERROR' -Message "No video stream detected in '$($file.Name)'. File kept for inspection."; continue }
            $height = [int]$v[0].height; $width = [int]$v[0].width
            if ($height -le $Quality) { Write-Status -Level 'OK' -Message "Video check passed: '$($file.Name)' is ${width}x${height}." }
            else { Write-Status -Level 'ERROR' -Message "Video check failed: '$($file.Name)' is ${width}x${height}, above your ${Quality}p maximum. File kept for inspection." }
            if ($a.Count -eq 0) { Write-Status -Level 'ERROR' -Message "No audio track found in '$($file.Name)'. Do not treat it as finished." }
            else { Write-Status -Level 'OK' -Message "Audio track verified in '$($file.Name)' ($($a[0].codec_name))." }
        } catch { Write-Status -Level 'WARN' -Message "Could not verify '$($file.Name)': $($_.Exception.Message)" }
    }
}

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
try {
    Set-RunPaths
    if ($Quality -lt 144 -or $Quality -gt 4320) { throw 'Quality must be from 144 to 4320.' }
    if ($ConcurrentFragments -lt 1 -or $ConcurrentFragments -gt 16) { throw 'Speed setting must be from 1 to 16.' }

    if ($Gui) {
        try { Add-Type -AssemblyName System.Windows.Forms } catch { throw 'Windows folder picker could not load. Run on Windows PowerShell 5.1.' }
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Step 1: Choose the folder where the videos should be saved.'
        $picker.ShowNewFolderButton = $true
        if (Test-Path -LiteralPath $OutputDirectory -PathType Container) { $picker.SelectedPath = $OutputDirectory }
        if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw [System.OperationCanceledException]::new('Folder selection cancelled; nothing was downloaded.') }
        $OutputDirectory = $picker.SelectedPath
        Set-RunPaths
        $entered = [System.Collections.Generic.List[string]]::new()
        Write-Host ''
        Write-Host 'Step 2: Paste YouTube links one by one. Press Enter on an empty line when finished.' -ForegroundColor Cyan
        while ($true) {
            $candidate = (Read-Host 'YouTube link').Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) { break }
            if (-not (Test-YouTubeLink $candidate)) { Write-Host 'That link was not accepted. Use https://youtube.com or https://youtu.be, without quotation marks.' -ForegroundColor Yellow; continue }
            if (-not $entered.Contains($candidate)) { $entered.Add($candidate) }
        }
        if ($entered.Count -gt 0) { $Links = @($entered.ToArray()) }
        elseif (-not $Links -or $Links.Count -eq 0) { throw 'No video links were provided.' }
        else { Write-Host 'No new links were added, so the sample links written in the script will be used.' -ForegroundColor Yellow }

        $q = Read-Host "Step 3: Maximum quality in pixels [$Quality] (examples: 360, 480, 720, 1080)"
        if (-not [string]::IsNullOrWhiteSpace($q)) { $n=0; if (-not [int]::TryParse($q,[ref]$n) -or $n -lt 144 -or $n -gt 4320) { throw 'Enter a number from 144 to 4320.' }; $Quality=$n }
        $s = Read-Host "Step 4: Speed setting 1-16 [$ConcurrentFragments] (try 8 first)"
        if (-not [string]::IsNullOrWhiteSpace($s)) { $n=0; if (-not [int]::TryParse($s,[ref]$n) -or $n -lt 1 -or $n -gt 16) { throw 'Enter a number from 1 to 16.' }; $ConcurrentFragments=$n }
        Set-RunPaths
        Write-Host ''
        Write-Host 'Please check your choices:' -ForegroundColor Cyan
        Write-Host "Save folder: $OutputDirectory"
        Write-Host "Links: $($Links.Count)"
        Write-Host "Maximum quality: ${Quality}p; if missing, the highest available lower quality is used."
        Write-Host "Parallel fragments: $ConcurrentFragments; HTTP range chunk size: $HttpChunkSize"
        Write-Host 'The video is not re-encoded. Audio is joined after its stream finishes. Subtitles are optional and requested separately after each successful video download.'
        $confirm = Read-Host 'Press Enter or type Y to start; type N to cancel'
        if (-not [string]::IsNullOrWhiteSpace($confirm) -and $confirm.Trim() -notmatch '^(?i)y(es)?$') { throw [System.OperationCanceledException]::new('Cancelled before download; nothing was downloaded.') }
    }

    Set-RunPaths
    $activeLinks = @($Links | Where-Object { $_ -and ([string]$_).Trim() -and ([string]$_ -notmatch '^LINK_\d+$') })
    if ($activeLinks.Count -eq 0) { throw 'No usable links were provided. Add links near the top of the script or use the guided launcher.' }
    foreach ($url in $activeLinks) { if (-not (Test-YouTubeLink $url)) { throw "This is not an accepted HTTPS YouTube link: $url" } }
    $activeLinks = @(Resolve-ChannelAndPlaylistLinks -InputLinks $activeLinks)
    if ($activeLinks.Count -eq 0) { throw 'No downloadable links were selected.' }
    if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) { throw 'yt-dlp was not found. Install it and check with: yt-dlp --version' }
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw 'FFmpeg was not found. It is needed to merge separate video and audio streams. Check with: ffmpeg -version' }
    $ytVersionOutput = (& yt-dlp --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "yt-dlp exists but failed its startup test: $ytVersionOutput. Check free space in %TEMP%, then update/reinstall yt-dlp if the problem repeats." }
    $ffmpegVersionOutput = (& ffmpeg -version 2>&1 | Select-Object -First 1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg exists but failed its startup test: $ffmpegVersionOutput. Reinstall FFmpeg if the problem repeats." }
    Write-Status -Level 'INFO' -Message "Tool startup checks passed: yt-dlp $ytVersionOutput; $ffmpegVersionOutput"

    $RunStarted = $true
    Write-Status -Level 'INFO' -Message "Starting run: $($activeLinks.Count) link(s); maximum ${Quality}p; parallel fragments $ConcurrentFragments; HTTP chunks $HttpChunkSize."
    Write-Status -Level 'INFO' -Message 'Speed note: range chunks can help with supported HTTP streams; parallel fragments help HLS/DASH streams. Neither setting can exceed your internet connection or the server limit.'

    # Make metadata and notes first. Write the HTML atomically so an error never truncates an existing file.
    foreach ($url in $activeLinks) {
        Write-Status -Level 'INFO' -Message "Reading title, chapters and description: $url"
        & yt-dlp --skip-download --no-warnings --write-info-json --no-write-playlist-metafiles --windows-filenames --format $FormatSelector --format-sort-force --format-sort $FormatSort --output $MetadataTemplate $url
        if ($LASTEXITCODE -ne 0) { Write-Status -Level 'WARN' -Message "Metadata could not be fully read for this link (exit code $LASTEXITCODE): $url" }
        Export-NotesFromInfoFiles
    }

    # Create notes/subtitles for existing complete video files if their notes are missing; skip fragments and .part files.
    $localVideos = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @('.mp4','.mkv','.webm') -and $_.Length -gt 1MB -and $_.BaseName -notmatch '\.f\d+$' })
    foreach ($videoFile in $localVideos) {
        $expectedHtml = Join-Path $videoFile.DirectoryName ($videoFile.BaseName + ' - Notes & Links.html')
        if (-not (Test-Path -LiteralPath $expectedHtml) -and $videoFile.Name -notmatch '\.f\d+\.(mp4|mkv|webm)$') {
            $query = ($videoFile.BaseName -replace '(?i)\bfixed\b','' -replace '[_]+',' ').Trim()
            if ($query) {
                Write-Status -Level 'INFO' -Message "Looking up notes/subtitles for existing video: $($videoFile.Name)"
                & yt-dlp --skip-download --no-warnings --write-info-json --no-write-playlist-metafiles --write-subs --write-auto-subs --sub-langs 'en.*' --convert-subs srt --ignore-errors --windows-filenames --output $MetadataTemplate ("ytsearch1:$query")
                Export-NotesFromInfoFiles
            }
        }
    }

    foreach ($url in $activeLinks) {
        if (-not (Test-UsableFormat -Url $url)) { $HadDownloadErrors = $true; continue }
        if (-not (Test-FreeSpace -Folder $OutputDirectory)) { $HadDownloadErrors = $true; break }
        Write-Status -Level 'INFO' -Message "Downloading this video and its audio streams now. Do not open a .fNNN.mp4 file; it is only a temporary video stream."
        $downloadStartedAt = Get-Date
        $downloadArgs = @(
            '--newline',
            '--http-chunk-size', $HttpChunkSize,
            '--concurrent-fragments', [string]$ConcurrentFragments,
            '--continue', '--retries', '5', '--fragment-retries', '10', '--retry-sleep', '2', '--file-access-retries', '3',
            '--no-write-playlist-metafiles', '--download-archive', $ArchivePath, '--no-overwrites',
            # Do not request subtitles in this command: a subtitle HTTP 429 can abort yt-dlp before video starts.
            # Download video + audio first; subtitle work is attempted separately after success.
            '--embed-chapters',
            '--format', $FormatSelector, '--format-sort-force', '--format-sort', $FormatSort,
            '--merge-output-format', 'mp4', '--windows-filenames', '--output', $DownloadTemplate,
            $url
        )
        Write-Status -Level 'INFO' -Message "Command settings: --http-chunk-size $HttpChunkSize; --concurrent-fragments $ConcurrentFragments; maximum ${Quality}p."
        & yt-dlp @downloadArgs
        $downloadExit = $LASTEXITCODE
        if ($downloadExit -eq 0) {
            Write-Status -Level 'OK' -Message "yt-dlp completed the video/audio download for: $url"
            # Subtitle requests run only after video/audio finished. Any 429 is a warning, not a failed download.
            try { Add-OptionalSubtitles -Url $url -StartedAt $downloadStartedAt } catch {
                Write-Status -Level 'WARN' -Message "Optional subtitle step failed but will not cancel the completed video/audio: $($_.Exception.Message)"
            }
        } else {
            $HadDownloadErrors = $true
            Write-Status -Level 'ERROR' -Message "yt-dlp ended with exit code $downloadExit for this link. Video/audio may be partial; files are kept for resume."
        }
        Test-FinalVideos
        Export-NotesFromInfoFiles
    }
} catch {
    if ($_.Exception -is [System.OperationCanceledException]) {
        Write-Status -Level 'WARN' -Message $_.Exception.Message
    } else {
        $RunFailed = $true
        Write-Status -Level 'ERROR' -Message $_.Exception.Message
        Write-Host 'The script will stay open so you can read this message.' -ForegroundColor Yellow
    }
} finally {
    if ($RunStarted) {
        try { Export-NotesFromInfoFiles } catch { Write-Status -Level 'WARN' -Message "Final notes pass failed safely: $($_.Exception.Message)" }
        try { Test-FinalVideos } catch { Write-Status -Level 'WARN' -Message "Final media check failed: $($_.Exception.Message)" }
        Write-Status -Level 'INFO' -Message "Output folder: $OutputDirectory"
        Write-Status -Level 'INFO' -Message "Archive: $ArchivePath"
        Write-Status -Level 'INFO' -Message "Log: $LogPath"
        if ($RunFailed -or $HadDownloadErrors) { Write-Status -Level 'WARN' -Message 'This run had an error or skipped link. Read the messages and the log above; .part files have not been deleted.' }
        else { Write-Status -Level 'OK' -Message 'Run ended without a reported downloader error. Check the final MP4 and the audio-track message before using it.' }
    }
    if (-not $NoPause) {
        Write-Host ''
        try { Read-Host 'Press Enter to close this window (your files will be kept)' | Out-Null } catch {}
    }
}
