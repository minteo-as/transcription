#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   ./transcribe_chunks.sh input.m4a output.txt /path/to/model.bin [chunk_seconds] [language] [prompt]
#
# Example:
#   cd JuraLyd
#   ./transcribe_chunks.sh 26-09-2026/forelaesning.m4a 26-09-2026/output.txt ~/models/whisper/ggml-large-v3-turbo.bin 300 da "Dette er en forelæsning i jura på Syddansk Universitet. Studerende stiller spørgsmål undervejs."
#
# Notes:
# - chunk_seconds defaults to 300 (5 minutes)
# - language defaults to auto
# - prompt defaults to "Dette er en forelæsning i jura på Syddansk Universitet. Studerende stiller spørgsmål undervejs."
# - whisper-cli must be available in PATH
# - ffmpeg must be available in PATH

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 input.m4a output.txt model.bin [chunk_seconds] [language] [prompt]" >&2
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"
MODEL_FILE="$3"
CHUNK_SECONDS="${4:-300}"
LANGUAGE="${5:-auto}"
PROMPT="${6:-Dette er en juridisk forelæsning om juridisk metode, jus, faktum, subsumption, culpa, adekvans, realkreditor, debitor.}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: input file not found: $INPUT_FILE" >&2
  exit 1
fi

if [[ ! -f "$MODEL_FILE" ]]; then
  echo "Error: model file not found: $MODEL_FILE" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg not found in PATH" >&2
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "Error: whisper-cli not found in PATH" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
STEM="${BASENAME%.*}"
WORKDIR="$(dirname "$INPUT_FILE")/${STEM}_chunks_work"

mkdir -p "$WORKDIR/chunks" "$WORKDIR/text"

cleanup_partial() {
  echo "Script interrupted. Partial files are in: $WORKDIR" >&2
}
trap cleanup_partial INT TERM

format_hhmmss() {
  local total="$1"
  local h=$(( total / 3600 ))
  local m=$(( (total % 3600) / 60 ))
  local s=$(( total % 60 ))
  printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

echo "Splitting audio into ${CHUNK_SECONDS}-second chunks..."
ffmpeg -hide_banner -loglevel error \
  -i "$INPUT_FILE" \
  -af "highpass=f=80,lowpass=f=8000" \
  -f segment \
  -segment_time "$CHUNK_SECONDS" \
  -c:a pcm_s16le \
  -ar 16000 \
  -ac 1 \
  "$WORKDIR/chunks/chunk_%04d.wav"

shopt -s nullglob
CHUNKS=( "$WORKDIR"/chunks/chunk_*.wav )
shopt -u nullglob

if [[ ${#CHUNKS[@]} -eq 0 ]]; then
  echo "Error: no chunks were created" >&2
  exit 1
fi

: > "$OUTPUT_FILE"

echo "Created ${#CHUNKS[@]} chunks"
echo "Starting transcription..."

index=0
for chunk in "${CHUNKS[@]}"; do
  start_sec=$(( index * CHUNK_SECONDS ))
  end_sec=$(( start_sec + CHUNK_SECONDS ))
  start_ts="$(format_hhmmss "$start_sec")"
  end_ts="$(format_hhmmss "$end_sec")"

  chunk_name="$(basename "$chunk" .wav)"
  chunk_txt="$WORKDIR/text/${chunk_name}.txt"

  echo "[$((index + 1))/${#CHUNKS[@]}] Transcribing ${chunk_name} (${start_ts} -> ${end_ts})"

  if [[ "$LANGUAGE" == "auto" ]]; then
    whisper-cli \
      -m "$MODEL_FILE" \
      -f "$chunk" \
      -otxt \
      -of "$WORKDIR/text/${chunk_name}" \
      -bs 5 \
      --temperature 0 \
      --vad \
      --vad-model "$HOME/models/whisper/ggml-silero-v6.2.0.bin"
  else
    whisper-cli \
      -m "$MODEL_FILE" \
      -f "$chunk" \
      -l "$LANGUAGE" \
      --prompt "$PROMPT" \
      -otxt \
      -of "$WORKDIR/text/${chunk_name}" \
      -bs 5 \
      --temperature 0 \
      --vad \
      --vad-model "$HOME/models/whisper/ggml-silero-v6.2.0.bin"
  fi

  {
    echo "===== CHUNK $((index + 1)) | ${start_ts} -> ${end_ts} ====="
    cat "$chunk_txt"
    echo
    echo
  } >> "$OUTPUT_FILE"

  index=$((index + 1))
done

echo "Done."
echo "Transcript written to: $OUTPUT_FILE"
echo "Intermediate files kept in: $WORKDIR"
