#!/usr/bin/env bash
# Fetch a web page as clean markdown, save it to disk and print a short
# summary (path, size, heading outline) instead of the page itself.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: fetch.sh <url> [--backend auto|defuddle|jina] [--out DIR] [--outline N]
  --backend  auto (default): defuddle locally, then Jina Reader if that fails
  --out      output directory (default: $SUN_AGENT_OUT/web or ./.sun-agent/web)
  --outline  max headings to list (default: 25, 0 disables)
EOF
  exit 2
}

die() { echo "error: $*" >&2; exit 1; }

url=""
backend="auto"
out_dir="${SUN_AGENT_OUT:-$PWD/.sun-agent}/web"
outline=25

while [ $# -gt 0 ]; do
  case "$1" in
    --backend|--out|--outline)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --backend) backend="$2" ;;
        --out) out_dir="$2" ;;
        --outline) outline="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage ;;
    -*) die "unknown option $1" ;;
    *)
      [ -z "$url" ] || die "only one url per call"
      url="$1"
      shift
      ;;
  esac
done

[ -n "$url" ] || usage
case "$url" in
  http://*|https://*) ;;
  *) die "url must start with http:// or https://" ;;
esac
case "$backend" in
  auto|defuddle|jina) ;;
  *) die "unknown backend '$backend'" ;;
esac
case "$outline" in
  ''|*[!0-9]*) die "--outline must be a number" ;;
esac

mkdir -p "$out_dir"
slug=$(printf '%s' "$url" | sed -E 's#^https?://##; s#[^A-Za-z0-9._-]+#-#g; s#^-+##; s#-+$##' | cut -c1-80)
hash=$(printf '%s' "$url" | cksum | cut -d' ' -f1)
file="$out_dir/${slug:-page}-$hash.md"
log="$file.log"

# A page with almost no text usually means it needs JavaScript or blocked us.
min_chars=200

has_content() {
  [ -s "$file" ] && [ "$(wc -c < "$file" | tr -d ' ')" -ge "$min_chars" ]
}

fetch_defuddle() {
  command -v npx >/dev/null 2>&1 || { echo "npx not found" > "$log"; return 1; }
  npx -y defuddle parse "$url" --md -o "$file" > "$log" 2>&1 || return 1
  has_content
}

fetch_jina() {
  command -v curl >/dev/null 2>&1 || { echo "curl not found" > "$log"; return 1; }
  if [ -n "${JINA_API_KEY:-}" ]; then
    curl -fsSL --max-time 90 -H "Authorization: Bearer $JINA_API_KEY" \
      -o "$file" "https://r.jina.ai/$url" 2> "$log" || return 1
  else
    curl -fsSL --max-time 90 -o "$file" "https://r.jina.ai/$url" 2> "$log" || return 1
  fi
  has_content
}

used=""
case "$backend" in
  defuddle) fetch_defuddle && used="defuddle" ;;
  jina) fetch_jina && used="jina" ;;
  auto)
    if fetch_defuddle; then
      used="defuddle"
    elif fetch_jina; then
      used="jina"
    fi
    ;;
esac

if [ -z "$used" ]; then
  echo "error: could not fetch $url (backend: $backend)" >&2
  [ -s "$log" ] && tail -n 3 "$log" >&2
  rm -f "$file" "$log"
  exit 1
fi
rm -f "$log"

chars=$(wc -c < "$file" | tr -d ' ')
lines=$(wc -l < "$file" | tr -d ' ')
echo "file: $file"
echo "backend: $used"
echo "size: $chars chars (~$((chars / 4)) tokens), $lines lines"
if [ "$outline" -gt 0 ]; then
  # Headings of level 1-3, skipping fenced code blocks (where "# " is a comment).
  headings=$(awk -v max="$outline" '
    /^(```|~~~)/ { fence = !fence; next }
    !fence && /^#+ / {
      match($0, /^#+/)
      if (RLENGTH <= 3) { print NR ":" substr($0, 1, 90); if (++n >= max) exit }
    }' "$file")
  if [ -n "$headings" ]; then
    echo "outline (line: heading):"
    printf '%s\n' "$headings" | sed 's/^/  /'
  fi
fi
