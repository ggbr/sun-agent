#!/usr/bin/env bash
# Hand a self-contained sub-task (summarize, extract, classify, translate)
# over one or more text files to a cheaper model and print only its answer.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: delegate.sh "<instruction>" [file ... | -] [--backend auto|anthropic|ollama]
                   [--model ID] [--max-tokens N] [--out FILE]
  file         text files given to the model as input; "-" reads stdin
  --backend    auto (default): anthropic if ANTHROPIC_API_KEY is set, else ollama
  --max-tokens cap on the answer length (default: 4000)
  --out        write the answer to FILE and print only path, size and preview
EOF
  exit 2
}

die() { echo "error: $*" >&2; exit 1; }

instruction=""
backend="auto"
model=""
max_tokens=4000
out=""
files=()

while [ $# -gt 0 ]; do
  case "$1" in
    --backend|--model|--max-tokens|--out)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --backend) backend="$2" ;;
        --model) model="$2" ;;
        --max-tokens) max_tokens="$2" ;;
        --out) out="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage ;;
    -) files+=("-"); shift ;;
    -*) die "unknown option $1" ;;
    *)
      if [ -z "$instruction" ]; then instruction="$1"; else files+=("$1"); fi
      shift
      ;;
  esac
done

[ -n "$instruction" ] || usage
case "$backend" in
  auto|anthropic|ollama) ;;
  *) die "unknown backend '$backend'" ;;
esac
case "$max_tokens" in
  ''|*[!0-9]*) die "--max-tokens must be a number" ;;
esac
command -v curl >/dev/null 2>&1 || die "curl not found"
command -v jq >/dev/null 2>&1 || die "jq not found"

if [ "$backend" = "auto" ]; then
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    backend="anthropic"
  elif [ -n "${SUN_DELEGATE_OLLAMA_MODEL:-}" ]; then
    backend="ollama"
  else
    die "no backend available. Set ANTHROPIC_API_KEY, or SUN_DELEGATE_OLLAMA_MODEL to use a local Ollama model."
  fi
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/delegate.XXXXXX")
trap 'rm -rf "$work"' EXIT
prompt="$work/prompt.txt"
printf '%s\n' "$instruction" > "$prompt"

for f in ${files[@]+"${files[@]}"}; do
  if [ "$f" = "-" ]; then
    label="stdin"
    src="$work/stdin.txt"
    cat > "$src"
  else
    [ -f "$f" ] || die "file not found: $f"
    label="$f"
    src="$f"
  fi
  [ -s "$src" ] || die "input is empty: $label"
  grep -Iq . "$src" || die "not a text file: $label (convert documents or transcribe media first)"
  {
    printf '\n<file path="%s">\n' "$label"
    cat "$src"
    printf '\n</file>\n'
  } >> "$prompt"
done

# Refuse oversized input rather than cutting it: a silently truncated file
# gives a confident answer about a document the model never fully saw.
max_chars="${SUN_DELEGATE_MAX_CHARS:-400000}"
chars=$(wc -c < "$prompt" | tr -d ' ')
[ "$chars" -le "$max_chars" ] \
  || die "input is $chars chars, over the $max_chars limit. Split it (split -l 2000 FILE part-) and delegate each part."

system="You are a worker handling one sub-task for another agent. Reply with the requested result only: no preamble, no restating the task, no closing remarks. Be as brief as the task allows. If the input does not contain what is asked, say so in one line."
body="$work/body.json"
resp="$work/resp.json"
answer="$work/answer.txt"

call() {
  # call <url> [curl args...] -> writes $resp, dies on transport or HTTP error
  local url="$1" code
  shift
  code=$(curl -sS --max-time 600 -o "$resp" -w '%{http_code}' \
    -H "content-type: application/json" "$@" --data-binary "@$body" "$url" 2> "$work/curl.err") \
    || die "request failed: $(tail -n 1 "$work/curl.err")"
  if [ "$code" != "200" ]; then
    local msg
    msg=$(jq -r 'if (.error | type) == "object" then "\(.error.type): \(.error.message)" else (.error // empty) end' "$resp" 2>/dev/null || true)
    die "HTTP $code${msg:+ - $msg}"
  fi
}

note=""
case "$backend" in
  anthropic)
    [ -n "${ANTHROPIC_API_KEY:-}" ] || die "ANTHROPIC_API_KEY is not set"
    [ -n "$model" ] || model="${SUN_DELEGATE_MODEL:-claude-haiku-4-5}"
    jq -n --arg model "$model" --argjson max "$max_tokens" --arg system "$system" \
      --rawfile prompt "$prompt" \
      '{model: $model, max_tokens: $max, system: $system,
        messages: [{role: "user", content: $prompt}]}' > "$body"
    call "${ANTHROPIC_BASE_URL:-https://api.anthropic.com}/v1/messages" \
      -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01"
    stop=$(jq -r '.stop_reason // empty' "$resp")
    [ "$stop" != "refusal" ] || die "the model declined this request"
    jq -r '[.content[]? | select(.type == "text") | .text] | join("")' "$resp" > "$answer"
    usage_in=$(jq -r '.usage.input_tokens // "?"' "$resp")
    usage_out=$(jq -r '.usage.output_tokens // "?"' "$resp")
    [ "$stop" != "max_tokens" ] || note="answer was cut at --max-tokens $max_tokens; raise it and run again"
    ;;
  ollama)
    [ -n "$model" ] || model="${SUN_DELEGATE_OLLAMA_MODEL:-}"
    [ -n "$model" ] || die "no Ollama model: pass --model or set SUN_DELEGATE_OLLAMA_MODEL"
    host="${OLLAMA_HOST:-http://localhost:11434}"
    case "$host" in
      http://*|https://*) ;;
      *) host="http://$host" ;;
    esac
    jq -n --arg model "$model" --argjson max "$max_tokens" --arg system "$system" \
      --rawfile prompt "$prompt" \
      '{model: $model, system: $system, prompt: $prompt, stream: false,
        options: {num_predict: $max}}' > "$body"
    call "${host%/}/api/generate"
    jq -r '.response // ""' "$resp" > "$answer"
    usage_in=$(jq -r '.prompt_eval_count // "?"' "$resp")
    usage_out=$(jq -r '.eval_count // "?"' "$resp")
    [ "$(jq -r '.done_reason // empty' "$resp")" != "length" ] \
      || note="answer was cut at --max-tokens $max_tokens; raise it and run again"
    ;;
esac

[ -s "$answer" ] && grep -q '[^[:space:]]' "$answer" || die "the model returned an empty answer"

if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  cp "$answer" "$out"
  size=$(wc -c < "$out" | tr -d ' ')
  echo "file: $out"
  echo "size: $size chars (~$((size / 4)) tokens)"
  echo "preview: $(head -c 300 "$out" | tr '\n' ' ')"
else
  cat "$answer"
fi
echo "[delegate] backend=$backend model=$model tokens_in=$usage_in tokens_out=$usage_out" >&2
[ -z "$note" ] || echo "[delegate] warning: $note" >&2
