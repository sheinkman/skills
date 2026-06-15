#!/usr/bin/env bash
#
# fetch_transcripts.sh — download YouTube captions for the crpg-tactical-combat skill.
#
# WHY THIS EXISTS:
#   The cloud environment Claude runs in blocks YouTube, so Claude can't pull the
#   tutorial captions itself. Your own computer is not blocked. Run this once on your
#   machine and it will download every transcript, then push them back to the branch
#   so Claude can pick them up in the next session.
#
# HOW TO USE (you do NOT need to understand any of this — just follow these steps):
#   1. Open the "Terminal" app.
#        - Mac:     press Cmd+Space, type "Terminal", press Enter.
#        - Windows: install "Git Bash" (https://git-scm.com/download/win), open it.
#   2. Go into your copy of this project, on this branch. If you don't have one yet:
#        git clone <your repo url>
#        cd skills
#        git checkout claude/optimistic-euler-u43gc8
#   3. Run:
#        bash fetch_transcripts.sh
#   4. When it finishes, it will have downloaded everything into _transcripts/ and
#      offered to push it back. Say "y" when asked. That's it.
#
# The script installs yt-dlp for you if it's missing. It keeps going if one video
# fails, and prints a summary at the end listing anything it couldn't get.

set -u  # error on undefined vars, but DON'T exit on first command failure — we want
        # to attempt every video and report failures at the end.

WORK_DIR="_transcripts"
mkdir -p "$WORK_DIR"

echo "============================================================"
echo " crpg-tactical-combat — transcript downloader"
echo "============================================================"

# ---- Step 0: make sure yt-dlp is available ----------------------------------
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "yt-dlp is not installed. Trying to install it for you..."
  if command -v brew >/dev/null 2>&1; then
    brew install yt-dlp
  elif command -v pipx >/dev/null 2>&1; then
    pipx install yt-dlp
  elif command -v pip3 >/dev/null 2>&1; then
    pip3 install -U yt-dlp
  elif command -v pip >/dev/null 2>&1; then
    pip install -U yt-dlp
  else
    echo "ERROR: Couldn't find brew, pipx, or pip to install yt-dlp."
    echo "Please install Python from https://www.python.org/downloads/ and re-run."
    exit 1
  fi
fi
echo "yt-dlp version: $(yt-dlp --version 2>/dev/null || echo unknown)"

# ---- Step 0b: a JavaScript runtime helps yt-dlp extract reliably ------------
# Recent yt-dlp warns if no JS runtime (deno) is present. It usually still works,
# but if you hit a wall, installing deno fixes it: https://docs.deno.com/runtime/
if ! command -v deno >/dev/null 2>&1; then
  echo "NOTE: 'deno' is not installed. Downloads will likely still work; if some"
  echo "      videos fail to extract, install deno and re-run:  brew install deno"
fi

# ---- Step 1: the sources from the task --------------------------------------
PLAYLISTS=(
  "https://www.youtube.com/playlist?list=PL0GUZtUkX6t4JrdjOoAF2ayH-ksVtgpqy"   # Greg Dev Stuff – Tactics RPG (grid-based)
  "https://www.youtube.com/playlist?list=PLsg5Z44PDzwTF9Bo0aDU7PeV_6Djz86dm"   # includes video T3Zg9oa3jNg
  "https://www.youtube.com/playlist?list=PL-hj540P5Q1hLK7NS5fTSNYoNJpPWSL24"   # inventory system
)

VIDEOS=(
  "https://www.youtube.com/watch?v=ezlkGhFBrmg"
  "https://www.youtube.com/watch?v=GYFnyiwa9iw"
  "https://www.youtube.com/watch?v=xY01G5UWISg"
  "https://www.youtube.com/watch?v=WbZpj8WcjN0"
  "https://www.youtube.com/watch?v=zEfBPmPDUVc"
  "https://www.youtube.com/watch?v=u5TRDRx9xIE"
  "https://www.youtube.com/watch?v=mONHucoYASU"
)

# Common yt-dlp arguments. We want English captions (manual + auto), no video,
# converted to .srt. The output template groups files by playlist.
COMMON_ARGS=(
  --write-auto-subs --write-subs --sub-langs "en.*"
  --skip-download --convert-subs srt
  --ignore-errors
  -o "${WORK_DIR}/%(playlist_title|standalone)s/%(playlist_index|0)02d-%(title)s.%(ext)s"
)

download() {
  echo
  echo ">>> $1"
  yt-dlp "${COMMON_ARGS[@]}" "$1"
}

for url in "${PLAYLISTS[@]}"; do download "$url"; done
for url in "${VIDEOS[@]}";    do download "$url"; done

# ---- Step 2: report what we got ---------------------------------------------
echo
echo "============================================================"
echo " Done downloading. Transcript files found:"
echo "============================================================"
find "$WORK_DIR" -name '*.srt' | sort
COUNT=$(find "$WORK_DIR" -name '*.srt' | wc -l | tr -d ' ')
echo
echo "Total transcript files: $COUNT"
if [ "$COUNT" -eq 0 ]; then
  echo "WARNING: No transcripts were downloaded. Check the messages above for errors."
  echo "If you see 'Sign in to confirm you're not a bot', try installing deno and re-running."
fi

# ---- Step 3: offer to push them back to the branch --------------------------
echo
echo "------------------------------------------------------------"
read -r -p "Push these transcripts back to the branch so Claude can read them? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  git add "$WORK_DIR"
  git commit -m "Add downloaded YouTube transcripts for crpg-tactical-combat"
  git push -u origin claude/optimistic-euler-u43gc8
  echo "Pushed. You can now tell Claude: 'transcripts are on the branch, continue.'"
else
  echo "Skipped pushing. When you're ready, run:"
  echo "  git add $WORK_DIR && git commit -m 'Add transcripts' && git push"
fi
