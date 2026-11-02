YT COURSE DOWNLOADER PRO — v3 (SPEED + STABILITY FIX)
=====================================================

v3.1: if the save drive has less than $MinimumFreeGB (8 GB) free, the script now says so clearly and asks for a folder on another drive (e.g. E:\YT-Courses) instead of silently stopping. yt-dlp -U output is shown live.

WHAT CHANGED IN v3 (read this first)
------------------------------------
1. WHY IT WAS SLOW: --concurrent-fragments only speeds up streams that YouTube serves in many small fragments. A 720p video is usually ONE big file, so the old "speed 8/16" setting did nothing. On top of that, new yt-dlp needs a JavaScript runtime (Deno or Node); without it YouTube throttles the file to ~400-500 KB/s. v3 fixes both: it checks for Deno/Node (offers a one-time winget install of Deno), and downloads with aria2c (many connections on one file) when available, else yt-dlp's chunked downloader. --throttled-rate re-extracts the link automatically if YouTube throttles mid-download.
2. WHY IT STOPPED AFTER THE FIRST VIDEO: in Windows PowerShell 5.1, $ErrorActionPreference='Stop' turns any yt-dlp WARNING (stderr text) captured with 2>&1 into a fatal error. The old preflight did exactly that, so the script jumped to its cleanup and exited. v3 runs native tools through a safe wrapper and the preflight is OFF by default (one YouTube request fewer per video).
3. WINDOW NO LONGER VANISHES: after finishing (or on any error) the window stays open INSIDE your save folder. Type exit to close it.
4. FEWER REQUESTS: the HTML notes (.info.json) are now written by the same yt-dlp call that downloads the video. Notes names now match the video file name. Subtitles use en,en-orig only (set $DownloadSubtitles = $false at the top to skip them).
5. H.264 preferred ($PreferH264): AV1 files (the f398 stream in your screenshot) are heavy to play on a Latitude 5580. The 720p cap still applies; a warning is printed if the final file is lower than requested.
6. yt-dlp is updated automatically at start ($AutoUpdateYtDlp).

HONEST LIMIT: nothing can exceed your internet line speed. Once throttling is removed, 720p of a long course is still a 1-2 GB download per video.

If a previous run left files like "... [720p].f398" or "...f140.m4a.part", leave them in the same folder: --continue resumes them.

OLDER NOTES (v2) — kept for reference
-------------------------------------


WHAT THIS VERSION FIXES
-----------------------
1. The previous script displayed the chosen speed value but did not pass it to yt-dlp. This version passes --concurrent-fragments with the selected number (default 8, allowed 1–16). This can help for fragmented streams. It cannot exceed the connection/server limit; lower it to 2–4 if HTTP 429 appears.
2. Audio is not merged at the end of the entire batch. yt-dlp handles each link in turn: it downloads that video's selected video stream, downloads its audio stream if separate, then FFmpeg merges them before yt-dlp finishes that link and continues to the next URL.
3. A file named like video.f398.mp4 is a temporary video-only stream. It will be silent until its matching audio stream finishes and FFmpeg merges it. Wait for a final file like video [720p].mp4. Do not judge a download by opening the .fNNN.mp4 file while it is being processed.
4. HTML pages now include an “Open PowerShell for this video” button. A one-time user-scope protocol setup is required so a local browser page can request Windows to open the helper. The browser/Windows can still show an “Open external app?” confirmation; choose Open.

FILES
-----
- yt-course-downloader-pro.ps1 — main readable/editable downloader.
- yt-course-downloader-pro-encoded.ps1 — Base64 companion. Encoding is not encryption.
- yt-course-downloader-pro-gui.cmd — easy guided launcher (double-click).
- Install-YT-Course-Protocol.cmd — run once to enable the HTML -> PowerShell button.
- Uninstall-YT-Course-Protocol.cmd — optional, removes only the custom link registration and installed helper scripts.
- ProtocolHandler.ps1 — validates the browser link, opens a folder picker, asks for quality/speed and confirmation, then runs the downloader.
- README.txt — this guide.

SIMPLE FIRST SETUP
------------------
1. Extract the entire ZIP into a new folder. Do not take out only one script; keep the companion files together.
2. Double-click Install-YT-Course-Protocol.cmd and type Y when asked. It installs helper scripts under %LOCALAPPDATA%\YT Course Downloader and creates a browser link for the current Windows user only. No administrator password is required.
3. Open the video's “Notes & Links.html” file and click “Open PowerShell for this video”. If Windows/browser asks whether to open the downloader, choose Open.
4. In PowerShell, the video link is already filled in. You may paste more YouTube links, one per prompt. Press Enter on an empty prompt when finished.
5. Choose the save folder, quality and speed. Check the summary, then press Enter or type Y to start; N cancels.
6. To use the old guided workflow instead, double-click yt-course-downloader-pro-gui.cmd.

QUALITY
-------
The quality number is a MAXIMUM. For 720, it chooses 720p if available; otherwise it chooses the highest available lower resolution. It will not select above the maximum. The main selector is equivalent to:
  bv[height<=720]+ba/b[height<=720]
The final filename shows the actual selected height, such as [720p] or [480p]. The format preflight is simulated before the large download, so the tool can display the selected height before it downloads.

AUDIO / MERGE / SPEED
---------------------
- Video and audio may be separate YouTube streams. They are downloaded separately, then FFmpeg merges them for that video. The merge does not wait for the whole list to finish.
- Do not open `.fNNN.mp4` or `.fNNN.m4a` files as completed outputs. They are intermediate streams. Wait for the final `[720p].mp4` file and the success line from the final media check.
- Speed is controlled by `--concurrent-fragments` now. Try 8; up to 16 is available, but higher concurrency can trigger rate limits and cannot make a slow internet connection faster.
- The PS Output.txt supplied for the previous run showed the first 1.08 GiB video stream taking 40:27 at about 467 KiB/s, after which a 625.90 MiB audio stream began. That output did not yet show the final merge. This large total size and sequential audio stream are the reason the video looked silent during the download; the visible speed option was also not being passed to yt-dlp in that release.
- This version does not re-encode video. It keeps the downloaded video stream and merges audio; no artificial low-bitrate preference is applied. File size depends on YouTube's stream bitrate and duration. 720p with no re-encoding can be much larger than 144p.
- A smaller file made with HandBrake/FFmpeg means re-encoding and can lose detail. Keep the original and save the compressed copy under a different name.

BROWSER-TO-POWERSHELL SECURITY MODEL
------------------------------------
A plain HTML file cannot silently run arbitrary local commands. This package provides a custom Windows URL protocol named `ytcourse://` instead. After you run Install-YT-Course-Protocol.cmd once, clicking the HTML link asks Windows/browser to start the registered handler. The handler then:
- accepts only HTTPS URLs from youtube.com or youtu.be;
- uses a folder picker instead of an arbitrary output path from HTML;
- asks for quality and fragment-concurrency values within a fixed range;
- displays a summary and requires a clear confirmation before downloading;
- runs the installed main script with a link passed as an argument, not as an assembled shell command;
- installs at HKCU (the current Windows user) and does not change machine-wide execution policy.
This is not encryption and not a substitute for reviewing code. The setup uses a process-scoped PowerShell execution-policy argument because it launches a local helper; that is not a permanent system policy change. Do not register/open protocols from unknown sources.

AI HELP
-------
The HTML page includes ChatGPT, Gemini and Claude choices. It opens your selected AI site and attempts to copy the page text, links, main script and companion helper sources. You must paste the copied text into the AI chat yourself and press Enter. Nothing is sent until you do. Browser isolation prevents the local file from automatically typing or pressing Send inside another site's chat box.

REQUIRED TOOLS
--------------
yt-dlp and FFmpeg must be available in PowerShell PATH; ffprobe is recommended for checking final output. Test in PowerShell:
  yt-dlp --version
  ffmpeg -version
  ffprobe -version

Official references:
- yt-dlp installation: https://github.com/yt-dlp/yt-dlp#installation
- yt-dlp format selector/sorting: https://github.com/yt-dlp/yt-dlp#format-selection
- FFmpeg: https://ffmpeg.org/download.html
- HandBrake downloads: https://handbrake.fr/downloads.php
- HandBrake CLI: https://handbrake.fr/docs/en/latest/cli/command-line-reference.html
- HandBrake quality: https://handbrake.fr/docs/en/latest/workflow/adjust-quality.html

TEST STATUS
-----------
This bundle received static source checks, command-propagation checks, HTTPS YouTube URI allowlist checks, HTML ID/href checks, JavaScript syntax checks, encoded/readable payload parity checks, and ZIP integrity checks. Format behavior is grounded in the earlier non-downloading simulations recorded in this conversation (the three provided URLs selected 720p, and the test cap of 719 selected 480p for Part 1). The new speed parameter is present in the real download command. PowerShell syntax parsing and full runtime tests were not performed because PowerShell is not available in the build environment; no live download was run for this build, and no running download or other PC file was changed. Test one video to completion first; verify the final MP4 height and audio stream with ffprobe before starting the full course list.
