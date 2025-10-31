#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# yt music/video downloader + embed artwork/tags/lyrics (best-effort)
# Requires: yt-dlp ffmpeg jq
# Optional (music mode): eyeD3

usage() {
  cat <<EOF
Usage: $0 [-m|--music] [-v|--video] <URL> [outdir]
  -m, --music    Download audio (MP3), embed artwork/tags/lyrics (default)
  -v, --video    Download video (MP4), capped at 1080p
If neither -m nor -v is given, music mode is used.
EOF
  exit 1
}

# parse flags
MODE="music"
while [[ $# -gt 0 && "$1" =~ ^- ]]; do
  case "$1" in
    -m|--music) MODE="music"; shift ;;
    -v|--video) MODE="video"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ "$#" -lt 1 ]; then usage; fi

URL="$1"
OUTDIR="${2:-.}"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

# basic deps
reqs=(yt-dlp ffmpeg jq)
for cmd in "${reqs[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Please install: $cmd"; exit 2; }
done

case "$MODE" in
  music)
    # eyeD3 is optional (we fall back to ffmpeg)
    if ! command -v eyeD3 >/dev/null 2>&1; then
      echo "Warning: eyeD3 not found — will try ffmpeg fallback for tags/artwork/lyrics."
    fi

    # Download audio-only. Keep info json + thumbnail + auto-sub if any (lrc).
    yt-dlp --no-playlist \
      -f "bestaudio" -x --audio-format mp3 --audio-quality 0 \
      --add-metadata --write-info-json --write-thumbnail \
      --write-auto-sub --sub-lang "en" --convert-subs "lrc" \
      -o "%(title)s.%(ext)s" \
      "$URL"

    # pick newest info.json robustly
    infos=( *.info.json )
    if [ "${#infos[@]}" -eq 0 ]; then
      echo "No .info.json found — download likely failed."
      exit 3
    fi
    newest=""
    newest_mtime=0
    for f in "${infos[@]}"; do
      m=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
      if [ "$m" -gt "$newest_mtime" ]; then newest_mtime=$m; newest="$f"; fi
    done
    info="$newest"
    base="${info%.info.json}"
    mp3="${base}.mp3"
    [ -f "$mp3" ] || { echo "MP3 missing: $mp3"; exit 4; }

    # Thumbnail handling: prefer jpg/jpeg, else convert png/webp -> cover.jpg; if conversion fails, allow original image for ffmpeg
    thumb=""
    for f in "${base}".*.jpg "${base}".*.jpeg; do
      [ -f "$f" ] && { thumb="$f"; break; }
    done

    if [ -z "$thumb" ]; then
      for p in "${base}".*.png; do
        [ -f "$p" ] || continue
        tmp="${base}.cover.jpg"
        if ffmpeg -y -i "$p" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" "$tmp" >/dev/null 2>&1; then
          thumb="$tmp"; break
        else
          rm -f -- "$tmp"; thumb=""; break
        fi
      done
    fi

    if [ -z "$thumb" ]; then
      for w in "${base}".*.webp; do
        [ -f "$w" ] || continue
        tmp="${base}.cover.jpg"
        if ffmpeg -y -i "$w" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" "$tmp" >/dev/null 2>&1; then
          thumb="$tmp"; break
        else
          # if conversion fails, still let ffmpeg embed original webp (it can transcode)
          thumb="$w"; break
        fi
      done
    fi

    # Lyrics: prefer auto-sub .lrc (strip timestamps), else try info.json fields (lyrics or description)
    lyricsfile=""
    lrcs=( "${base}".*.lrc )
    if [ "${#lrcs[@]}" -gt 0 ]; then
      raw="${lrcs[0]}"
      lyricsfile="${base}.lyrics.txt"
      sed -E 's/\[[0-9:.]+\]//g' "$raw" | sed '/^[[:space:]]*$/d' > "$lyricsfile"
    else
      if jq -r '.lyrics // .lyrics_text // empty' "$info" | grep -q .; then
        lyricsfile="${base}.lyrics.txt"
        jq -r '.lyrics // .lyrics_text // empty' "$info" > "$lyricsfile"
      else
        desc=$(jq -r '.description // empty' "$info")
        if [ -n "$desc" ] && [ "${#desc}" -gt 200 ]; then
          lyricsfile="${base}.lyrics.txt"
          printf '%s\n' "$desc" > "$lyricsfile"
        fi
      fi
    fi

    # Read metadata safely
    artist=$(jq -r '.artist // .uploader // empty' "$info")
    title=$(jq -r '.title // empty' "$info")
    album=$(jq -r '.album // empty' "$info")
    date=$(jq -r '.release_date // .upload_date // empty' "$info")
    track=$(jq -r '.track_number // .track // empty' "$info")
    genre=$(jq -r '.genre // empty' "$info")

    # Build eyeD3 args, avoid passing non-numeric track
    ed3args=(--to-v2.3)
    [ -n "$artist" ] && ed3args+=(-a "$artist")
    [ -n "$title" ]  && ed3args+=(-t "$title")
    [ -n "$album" ]  && ed3args+=(-A "$album")
    if [[ -n "$track" && "$track" =~ ^[0-9]+([/][0-9]+)?$ ]]; then
      ed3args+=(-n "$track")
    fi
    [ -n "$date" ]   && ed3args+=(-D "$date")
    [ -n "$genre" ]  && ed3args+=(-g "$genre")
    ed3args+=("$mp3")

    # Try eyeD3 (proper tags). Print minimal info so you know what happens.
    echo "Trying eyeD3 tagging..."
    set +e
    rc_tags=0
    rc_image=0
    rc_lyrics=0
    if command -v eyeD3 >/dev/null 2>&1; then
      eyeD3 "${ed3args[@]}" --remove-v1 >/dev/null 2>&1
      rc_tags=$?
      if [ -n "$thumb" ]; then
        eyeD3 --add-image="$thumb":FRONT_COVER "$mp3" >/dev/null 2>&1
        rc_image=$?
      fi
      if [ -n "$lyricsfile" ]; then
        eyeD3 --add-lyrics="$lyricsfile" "$mp3" >/dev/null 2>&1
        rc_lyrics=$?
      fi
    else
      rc_tags=1
    fi
    rc=$((rc_tags + rc_image + rc_lyrics))
    set -e

    if [ "$rc" -eq 0 ]; then
      echo "eyeD3: tags OK."
    else
      echo "eyeD3 failed or unavailable (rc=$rc) — falling back to ffmpeg for embedding (will show ffmpeg output)."
      tmpout="${base}.withmeta.mp3"
      ffargs=( -y -i "$mp3" )
      if [ -n "$thumb" ]; then
        ffargs+=( -i "$thumb" -map 0:a -map 1:v -c:a copy -c:v mjpeg )
      else
        ffargs+=( -map 0 -c copy )
      fi
      [ -n "$title" ]  && ffargs+=( -metadata title="$title" )
      [ -n "$artist" ] && ffargs+=( -metadata artist="$artist" )
      [ -n "$album" ]  && ffargs+=( -metadata album="$album" )
      [ -n "$date" ]   && ffargs+=( -metadata date="$date" )
      if [[ "$track" =~ ^[0-9]+([/][0-9]+)?$ ]]; then ffargs+=( -metadata track="$track" ); fi
      [ -n "$genre" ]  && ffargs+=( -metadata genre="$genre" )
      if [ -n "$lyricsfile" ] && [ -f "$lyricsfile" ]; then
        mapfile -t _lines < "$lyricsfile"
        if [ "${#_lines[@]}" -gt 0 ]; then
          lyricsmeta=$(printf '%s\n' "${_lines[@]}" | sed 's/"/'\''/g')
          ffargs+=( -metadata lyrics="$lyricsmeta" )
        fi
        unset _lines
      fi
      ffargs+=( -id3v2_version 3 "$tmpout" )
      if ! ffmpeg "${ffargs[@]}"; then
        echo "ffmpeg embedding failed — leaving original MP3 as-is."
      else
        mv -f "$tmpout" "$mp3"
      fi
    fi

    echo "Final file: $mp3"
    [ -n "$thumb" ] && echo "Cover used: $thumb"
    [ -n "$lyricsfile" ] && echo "Lyrics file used: $lyricsfile"

    # cleanup: remove only files related to this download except the final mp3
    shopt -s nullglob
    for f in "${base}".*; do
      [ "$f" = "$mp3" ] && continue
      rm -f -- "$f"
    done

    echo "Done. Kept: $mp3"
    ;;

  video)
    echo "Downloading video (best up to 1080p)..."
    # prefer bestvideo up to 1080 + best audio, fallback to best[height<=1080], then best
    yt-dlp --no-playlist \
      -f "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best" \
      --merge-output-format mp4 \
      --add-metadata \
      -o "%(title)s.%(ext)s" \
      "$URL"

    # report most recent file
    newest_file=$(ls -t | head -n1 || true)
    echo "Done. Kept: ${newest_file:-(none)}"
    ;;

  *)
    echo "Invalid mode: $MODE"
    usage
    ;;
esac

