YT COURSE DOWNLOADER — FINAL REPAIR BUILD
========================================

WHAT THIS FIXES
- Uses the best available quality at or below the selected maximum. Example: maximum 720p picks 720p when available, otherwise 480p, 360p, 240p, etc. It never deliberately chooses above the limit.
- Adds --http-chunk-size 10M for supported HTTP streams and passes the selected parallel-fragment count to yt-dlp. This can help when a server throttles long requests, but does not guarantee a speed or bypass your internet/server limits.
- Waits at the end when run directly, so errors remain visible. The .cmd launcher also keeps the console open.
- Downloads video and audio streams and lets FFmpeg merge them into the final MP4. A temporary file ending .f398.mp4 may have no audio; do not treat it as the finished video. Wait for the matching audio stream and merge to finish.
- Checks final MP4 dimensions and whether an audio track exists when ffprobe is available.
- Writes HTML notes to a temporary file and atomically replaces the destination. If the disk is full during writing, the existing HTML file should remain intact rather than being truncated to 0 bytes.
- Keeps partial .part files for possible resume; it never auto-deletes partial downloads.
- HTML notes include direct video link, valid playlist link when available, chapters, clickable description URLs, a copyable re-download command, a collapsible simple guide, an AI helper panel, and an HTML-to-PowerShell button.

OPTION A — EASY LAUNCHER
1. Extract the complete ZIP to a new folder.
2. Double-click yt-course-downloader-final-gui.cmd.
3. Choose the save folder.
4. Paste one YouTube link per line; press Enter on an empty line when finished.
5. Enter maximum quality (e.g. 720) and parallel fragment count (try 8).
6. Read the summary and press Enter or Y to begin. The window remains open at the end.

OPTION B — RUN THE READABLE SCRIPT IN POWERSHELL
1. Open the folder containing yt-course-downloader-final.ps1.
2. Click the folder address bar, type powershell, and press Enter.
3. Type this command and press Enter:
   .\yt-course-downloader-final.ps1
4. The script asks no extra questions unless you use -Gui. It uses the default links at the top of the script. To change them, edit $Links near the top.
5. The script pauses at the end so you can read any error. In a PowerShell window you opened yourself, it will not close that window.

To use the guided mode directly from PowerShell:
   .\yt-course-downloader-final.ps1 -Gui

HTML BUTTON SETUP (OPTIONAL; ONE TIME)
1. Keep the complete ZIP extracted in one folder.
2. Double-click Install-YT-Course-Protocol.cmd and type Y.
3. Open a generated Notes & Links HTML file and click the green "Open PowerShell for this video" button.
4. If Chrome asks to open the downloader, approve it.
5. Choose a save folder, set quality/speed, and confirm. The browser itself does not submit anything to an AI or start a download without this separate consent step.
6. To remove the feature, run Uninstall-YT-Course-Protocol.cmd. It removes the current-user link registration and installed helper files only. It does not delete videos or HTML notes.

QUALITY
The number is a maximum height, not an instruction to upscale. For maximum 720p, the downloader selects the best available stream up to 720p. If the source only has 360p, the best available 360p is used. A video cannot gain source detail that YouTube does not provide.

SPEED
The script passes the selected value to --concurrent-fragments (used for DASH/HLS fragments) and uses 10M HTTP range chunks for supported HTTP streams. yt-dlp documents HTTP chunking as experimental. Actual speed depends on connection, YouTube's stream/format and server behavior. If HTTP 429 occurs, wait and lower parallelism to 2-4. Do not keep raising the setting to try to bypass throttling.

AUDIO
A separate video-only file such as "title [720p].f398.mp4" is an intermediate stream when its paired audio is not complete. Wait for yt-dlp's merge message and open the final "title [720p].mp4". The final validation checks for both video and audio stream when ffprobe is installed.

DISK SPACE AND RESUME
Minimum free space before each link defaults to 4 GB. At startup, the script also checks that yt-dlp and FFmpeg can launch. If yt-dlp reports “Failed to extract unicodedata.pyd”, check free space and write access for the Windows %TEMP% folder; if there is plenty of free space and the message repeats, update or reinstall yt-dlp. Very long/high-bitrate videos can need more. If the script stops for space, free disk space and rerun using the same output folder and same quality. It keeps .part files. A different selected format may require a fresh partial download; inspect before deleting anything. Atomic HTML writes prevent a failed write from first truncating an existing notes file.

FILE SIZE VS QUALITY
The source video is not re-encoded, so there is no added re-encoding loss. The file size is determined by the selected source stream. Compressing 1 GB to 150 MB while guaranteeing that fine text/details never change is not possible in general. HandBrake compression is optional and may reduce fine detail.

TOOLS
- yt-dlp: https://github.com/yt-dlp/yt-dlp
- FFmpeg: https://ffmpeg.org/download.html
- HandBrake CLI (optional compression): https://handbrake.fr/docs/en/latest/cli/command-line-reference.html

AI HELPER
The HTML opens ChatGPT, Gemini or Claude and copies the page text, links and embedded readable script to the clipboard. Because websites do not let a local HTML page secretly control their chat input, you paste with Ctrl+V and press Enter yourself. The page does not auto-submit your context.

ENCODED SCRIPT
The encoded companion has the same readable script inside Base64. Base64 is encoding, not encryption. Prefer the readable file for troubleshooting and changes.

TEST LIMITS
The bundle should be syntax-checked on Windows PowerShell 5.1 and tested with a small video before downloading long courses. This release was statically checked in the build environment; no live full-course download was performed by the bundle builder. Always review the on-screen logs, final file name, dimensions and audio-track check.


SUBTITLE ERROR FIX (THIS BUILD)
The main video/audio command no longer requests or embeds subtitles before downloading. After a successful video/audio merge, a separate best-effort English subtitle request is made. An HTTP 429 here is a warning only and does not change the video download result. If an English SRT is available, FFmpeg attempts to embed it by copying the existing video/audio streams (no re-encoding). If captions are rate-limited, no subtitle may be added, but the final MP4 should still have its audio.

 
LATEST REPAIR — 24 OCTOBER 2026
===============================

WHAT CHANGED IN THIS REPAIR
- Fixed PowerShell syntax problems found in the HTML notes section.
- The readable PowerShell script and encoded companion now match exactly.
- Each playlist video is saved in its own folder:
  Save folder\Playlist name\Video title\
- A single video is saved in:
  Save folder\Videos\Video title\
- The video, HTML notes and available SRT subtitle are kept together in that video folder.
- Metadata, subtitle and final audio/video checks now search inside subfolders too.
- The subtitle step is still optional. If YouTube returns HTTP 429 for captions, the video/audio result is not marked failed just because captions failed.
- Channel links now offer Videos, Playlists, Courses, Shorts, Live streams or All downloadable sections. For Playlists, the script lists the playlists first and lets you choose numbers or all.
- When the script sees a channel's Home or Community area, it explains that those are not video download lists. Community posts are not downloaded.
- If Node.js is already installed, the downloader asks yt-dlp to use it. The script does not install software automatically.

IMPORTANT TEST STATUS
- Windows PowerShell parser checks passed for the main script, encoded companion, protocol handler, installer and uninstaller.
- Encoded companion parity check passed: decoding it produces the exact readable script.
- Static feature checks passed for the channel workflow and folder template.
- A full live YouTube playlist/channel download test has NOT been performed in this repair run. Test with one short, public video first, then a small playlist before starting a many-hour course.
- No script can guarantee that YouTube will serve every item: private/deleted/age-restricted videos, rate limits, network drops, storage space, or unavailable captions can still cause individual failures. The log identifies failures and partial files are retained for resume.
- The channel's Home and Community content is not a downloadable video list. Channel tabs exposed by yt-dlp can vary; if YouTube does not expose a section, the script may be unable to enumerate it.

SAFE TEST
1. Extract this ZIP into a new folder.
2. Double-click yt-course-downloader-final-gui.cmd.
3. Choose a save folder and paste ONE short public YouTube video link.
4. Choose 720 as the maximum quality and keep speed at 4 or 8.
5. Wait for the final video/audio check. Open the final MP4, not any temporary .fNNN.mp4 file.
6. Confirm that the video plays with sound and that its folder contains the HTML notes and, if captions are available, an SRT file.
7. Only after this succeeds, test a small playlist. Large 10-hour videos can take a long time and require substantial disk space.

 
LIVE FORMAT CHECK (NO MEDIA DOWNLOADED)
- Ran yt-dlp simulation/format selection for the three sample links from the previous run.
- All three returned a usable 720p video+audio format: format 398+140.
- This checks YouTube extraction and quality selection only. It does not prove that a long download, FFmpeg merge, SRT retrieval or channel enumeration will finish successfully.
