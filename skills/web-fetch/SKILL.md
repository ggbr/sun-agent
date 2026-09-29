---
name: web-fetch
description: Fetch a web page as clean markdown saved to disk, returning only the file path, size and heading outline. Use to read an article, documentation page or any URL (ler página, abrir link, baixar site) without loading the whole page into context.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/fetch.sh *)
---

# web-fetch

Nothing is fetched until you run the script. Run it now with Bash, passing
the URL:

```bash
${CLAUDE_SKILL_DIR}/scripts/fetch.sh "<url>"
```

It saves the page as markdown and prints only this summary, so the page
text stays out of the context until you read part of it:

```
file: ./.sun-agent/web/<slug>.md
backend: defuddle
size: 12840 chars (~3210 tokens), 214 lines
outline (line: heading):
  1: # Title
  37: ## Section
```

## Reading the result

- Look for what you need with `rg -n "<term>" <file>`, then Read only that
  range (offset/limit). Use the outline line numbers to jump to a section.
- Read the whole file only when it is small (under ~2000 tokens).
- For a long page where you need a summary or an extraction, hand the file
  to the `delegate` skill instead of reading it.

## Options

| Option | Use |
|---|---|
| `--backend defuddle` | Local extraction only. Nothing leaves the machine except the page request. |
| `--backend jina` | Jina Reader (`r.jina.ai`), renders JavaScript. Sends the URL to a third party. |
| `--out DIR` | Output directory. |
| `--outline N` | Max headings listed (0 disables). |

Default `auto` tries defuddle first and falls back to Jina when the page
comes back empty. Use `--backend defuddle` for internal or private URLs.

## Limits

- One URL per call.
- Pages behind a login are not supported; use a browser skill for those.
- PDFs and office files are not web pages; use a document-ingest tool.
