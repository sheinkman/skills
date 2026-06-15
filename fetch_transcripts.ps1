# fetch_transcripts.ps1 — Windows/PowerShell version of the transcript downloader.
#
# WHY: the cloud environment Claude runs in blocks YouTube, so the captions must be
# downloaded from your own computer. This script needs NOTHING pre-installed — it
# downloads a single self-contained yt-dlp.exe, pulls every transcript as .srt, then
# offers to push them back to the branch so Claude can read them.
#
# HOW TO RUN (in PowerShell, from inside the cloned "skills" folder):
#   powershell -ExecutionPolicy Bypass -File fetch_transcripts.ps1

$work = "_transcripts"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# ---- get yt-dlp.exe (self-contained, no Python needed) ----------------------
$ytdlp = Join-Path (Get-Location) "yt-dlp.exe"
if (-not (Test-Path $ytdlp)) {
    Write-Host "Downloading yt-dlp.exe ..."
    $url = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
    Invoke-WebRequest -Uri $url -OutFile $ytdlp
}
Write-Host ("yt-dlp version: " + (& $ytdlp --version))

# ---- sources from the task --------------------------------------------------
$urls = @(
    "https://www.youtube.com/playlist?list=PL0GUZtUkX6t4JrdjOoAF2ayH-ksVtgpqy",  # Greg Dev Stuff - Tactics RPG (grid)
    "https://www.youtube.com/playlist?list=PLsg5Z44PDzwTF9Bo0aDU7PeV_6Djz86dm",  # includes video T3Zg9oa3jNg
    "https://www.youtube.com/playlist?list=PL-hj540P5Q1hLK7NS5fTSNYoNJpPWSL24",  # inventory system
    "https://www.youtube.com/watch?v=ezlkGhFBrmg",
    "https://www.youtube.com/watch?v=GYFnyiwa9iw",
    "https://www.youtube.com/watch?v=xY01G5UWISg",
    "https://www.youtube.com/watch?v=WbZpj8WcjN0",
    "https://www.youtube.com/watch?v=zEfBPmPDUVc",
    "https://www.youtube.com/watch?v=u5TRDRx9xIE",
    "https://www.youtube.com/watch?v=mONHucoYASU"
)

$ytArgs = @(
    "--write-auto-subs", "--write-subs", "--sub-langs", "en.*",
    "--skip-download", "--convert-subs", "srt", "--ignore-errors",
    "-o", "$work/%(playlist_title|standalone)s/%(playlist_index|0)02d-%(title)s.%(ext)s"
)

foreach ($u in $urls) {
    Write-Host ""
    Write-Host ">>> $u"
    & $ytdlp @ytArgs $u
}

# ---- report -----------------------------------------------------------------
$srt = Get-ChildItem -Recurse -Path $work -Filter *.srt -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "============================================================"
Write-Host (" Downloaded {0} transcript files:" -f $srt.Count)
Write-Host "============================================================"
$srt | ForEach-Object { Write-Host $_.FullName }
if ($srt.Count -eq 0) {
    Write-Host "WARNING: nothing downloaded. If you saw 'Sign in to confirm you're not a bot',"
    Write-Host "install deno (https://docs.deno.com) and re-run this script."
}

# ---- offer to push back -----------------------------------------------------
Write-Host ""
$ans = Read-Host "Push these transcripts back to the branch so Claude can read them? (y/N)"
if ($ans -eq "y" -or $ans -eq "Y") {
    git add $work
    git commit -m "Add downloaded YouTube transcripts for nogrid-tactics-combat"
    git push -u origin claude/optimistic-euler-u43gc8
    Write-Host "Pushed. Now tell Claude: 'transcripts are pushed, continue.'"
} else {
    Write-Host "Skipped. To push later, run:  git add $work ; git commit -m transcripts ; git push"
}
