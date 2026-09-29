#!/usr/bin/env bash
# Transcribe an audio or video file, save the transcript to disk and print
# a short summary (path, size, preview) instead of the transcript itself.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: transcribe.sh <media-file> [--lang pt] [--format txt|srt|vtt]
                     [--backend auto|mlx|groq] [--model ID] [--out DIR]
  --lang     ISO-639-1 language code (default: pt)
  --format   txt (default), srt or vtt
  --backend  auto (default): mlx if installed, else groq if GROQ_API_KEY is set
  --out      output directory (default: $SUN_AGENT_OUT/transcripts)
EOF
  exit 2
}

die() { echo "error: $*" >&2; exit 1; }

input=""
lang="pt"
format="txt"
backend="auto"
model="${SUN_TRANSCRIBE_MODEL:-}"
out_dir="${SUN_AGENT_OUT:-$PWD/.sun-agent}/transcripts"

while [ $# -gt 0 ]; do
  case "$1" in
    --lang|--format|--backend|--model|--out)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --lang) lang="$2" ;;
        --format) format="$2" ;;
        --backend) backend="$2" ;;
        --model) model="$2" ;;
        --out) out_dir="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage ;;
    -*) die "unknown option $1" ;;
    *)
      [ -z "$input" ] || die "only one file per call"
      input="$1"
      shift
      ;;
  esac
done

[ -n "$input" ] || usage
[ -f "$input" ] || die "file not found: $input"
case "$format" in
  txt|srt|vtt) ;;
  *) die "unknown format '$format'" ;;
esac
case "$backend" in
  auto|mlx|groq) ;;
  *) die "unknown backend '$backend'" ;;
esac

if [ "$backend" = "auto" ]; then
  if command -v mlx_whisper >/dev/null 2>&1; then
    backend="mlx"
  elif [ -n "${GROQ_API_KEY:-}" ]; then
    backend="groq"
  else
    die "no backend available. Local: install mlx-whisper and ffmpeg. Hosted: set GROQ_API_KEY."
  fi
fi

mkdir -p "$out_dir"
name=$(basename "$input")
base="${name%.*}"
out="$out_dir/$base.$format"
log="$out_dir/$base.log"

run_mlx() {
  command -v mlx_whisper >/dev/null 2>&1 || die "mlx_whisper not found (pip install mlx-whisper)"
  command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found (mlx_whisper needs it to decode audio)"
  [ -n "$model" ] || model="mlx-community/whisper-large-v3-turbo"
  if ! mlx_whisper "$input" --model "$model" --language "$lang" \
      --output-dir "$out_dir" --output-name "$base" --output-format "$format" \
      --verbose False > "$log" 2>&1; then
    echo "error: mlx_whisper failed" >&2
    tail -n 5 "$log" >&2
    exit 1
  fi
  [ -s "$out" ] || die "mlx_whisper produced no output at $out"
}

# jq program that renders verbose_json segments as txt, srt or vtt.
render='
def pad(n): tostring | (n - length) as $k | if $k > 0 then ("0" * $k) + . else . end;
def ts(sep): ((. * 1000) | round) as $ms
  | "\($ms / 3600000 | floor | pad(2)):\(($ms % 3600000) / 60000 | floor | pad(2)):\(($ms % 60000) / 1000 | floor | pad(2))\(sep)\($ms % 1000 | pad(3))";
if $format == "txt" then (.text // "" | ltrimstr(" "))
elif $format == "srt" then
  [ (.segments // []) | to_entries[]
    | "\(.key + 1)\n\(.value.start | ts(",")) --> \(.value.end | ts(","))\n\(.value.text | ltrimstr(" "))\n" ]
  | join("\n")
else
  "WEBVTT\n\n" + ([ (.segments // [])[]
    | "\(.start | ts(".")) --> \(.end | ts("."))\n\(.text | ltrimstr(" "))\n" ]
  | join("\n"))
end'

run_groq() {
  [ -n "${GROQ_API_KEY:-}" ] || die "GROQ_API_KEY is not set"
  command -v curl >/dev/null 2>&1 || die "curl not found"
  command -v jq >/dev/null 2>&1 || die "jq not found"
  [ -n "$model" ] || model="whisper-large-v3-turbo"
  base_url="${GROQ_BASE_URL:-https://api.groq.com/openai/v1}"
  max_mb="${SUN_GROQ_MAX_MB:-25}"

  send="$input"
  size_mb=$(( ($(wc -c < "$input" | tr -d ' ') + 1048575) / 1048576 ))
  if [ "$size_mb" -gt "$max_mb" ]; then
    command -v ffmpeg >/dev/null 2>&1 \
      || die "file is ${size_mb}MB, over the ${max_mb}MB upload limit, and ffmpeg is not installed to compress it"
    send="$out_dir/$base.upload.mp3"
    if ! ffmpeg -y -loglevel error -i "$input" -vn -ac 1 -ar 16000 -b:a 32k "$send" > "$log" 2>&1; then
      echo "error: ffmpeg could not compress the file" >&2
      tail -n 5 "$log" >&2
      exit 1
    fi
    size_mb=$(( ($(wc -c < "$send" | tr -d ' ') + 1048575) / 1048576 ))
    [ "$size_mb" -le "$max_mb" ] \
      || die "file is still ${size_mb}MB after compression; split it (ffmpeg -f segment) and transcribe each part"
  fi

  json="$out_dir/$base.json"
  # curl -F treats , and ; as separators unless the path is quoted.
  quoted=$(printf '%s' "$send" | sed 's/\\/\\\\/g; s/"/\\"/g')
  code=$(curl -sS --max-time 900 -o "$json" -w '%{http_code}' \
    -H "Authorization: Bearer $GROQ_API_KEY" \
    -F "file=@\"$quoted\"" \
    -F "model=$model" \
    -F "language=$lang" \
    -F "response_format=verbose_json" \
    "$base_url/audio/transcriptions" 2> "$log") || {
      echo "error: request to Groq failed" >&2
      tail -n 3 "$log" >&2
      exit 1
    }
  if [ "$code" != "200" ]; then
    msg=$(jq -r '.error.message // empty' "$json" 2>/dev/null || true)
    rm -f "$json"
    die "Groq returned HTTP $code${msg:+: $msg}"
  fi
  jq -r --arg format "$format" "$render" "$json" > "$out"
  duration=$(jq -r '.duration // empty' "$json")
  rm -f "$json"
  [ "$send" = "$input" ] || rm -f "$send"
  [ -s "$out" ] || die "transcript is empty (no speech detected?)"
}

duration=""
case "$backend" in
  mlx) run_mlx ;;
  groq) run_groq ;;
esac
rm -f "$log"

chars=$(wc -c < "$out" | tr -d ' ')
echo "file: $out"
echo "backend: $backend ($model)"
[ -z "$duration" ] || echo "duration: ${duration}s"
echo "size: $chars chars (~$((chars / 4)) tokens)"
echo "preview: $(head -c 300 "$out" | tr '\n' ' ')"
