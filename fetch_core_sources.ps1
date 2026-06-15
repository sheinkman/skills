# fetch_core_sources.ps1 — extra captions for the "engine-independent core" task.
#
# These are the architecture sources (Code Monkey TBS overview + git-amend's
# state-machine / command / service-locator videos). ezlkGhFBrmg (XCOM in 25h) is
# already in _transcripts, so it's not repeated here.
#
# RUN (in PowerShell, from inside the cloned "skills" folder):
#   powershell -ExecutionPolicy Bypass -File fetch_core_sources.ps1

$work = "_sources"
New-Item -ItemType Directory -Force -Path $work | Out-Null

$ytdlp = Join-Path (Get-Location) "yt-dlp.exe"
if (-not (Test-Path $ytdlp)) {
    Write-Host "Downloading yt-dlp.exe ..."
    Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $ytdlp
}

$common = @(
    "--write-auto-subs", "--write-subs", "--sub-langs", "en.*",
    "--skip-download", "--ignore-errors",
    "--sleep-requests", "1", "--sleep-subtitles", "1",
    "--retries", "10", "--extractor-retries", "5",
    "-o", "$work/%(uploader)s/%(title)s.%(ext)s"
)

# 1) Code Monkey - Turn-Based Strategy course overview
Write-Host ">>> Code Monkey TBS overview"
& $ytdlp @common "https://www.youtube.com/watch?v=QDr_pjzedv0"

# 2) git-amend - only the state-machine / command / service-locator videos.
#    --match-title filters by title so we don't pull the whole channel.
Write-Host ">>> git-amend (state machine / command / service locator)"
& $ytdlp @common --match-title "(?i)(state machine|command pattern|service locator)" `
    "https://www.youtube.com/@git-amend/videos"

$found = Get-ChildItem -Recurse -Path $work -Include *.vtt,*.srt -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("Downloaded {0} caption files into {1}:" -f $found.Count, $work)
$found | ForEach-Object { Write-Host $_.FullName }

Write-Host ""
$ans = Read-Host "Push these back to the branch so Claude can read them? (y/N)"
if ($ans -eq "y" -or $ans -eq "Y") {
    git add $work
    git commit -m "Add caption sources for engine-independent core task"
    git push -u origin claude/optimistic-euler-u43gc8
    Write-Host "Pushed. Tell Claude: 'core sources pushed'."
} else {
    Write-Host "Skipped. To push later:  git add $work ; git commit -m core-sources ; git push"
}
