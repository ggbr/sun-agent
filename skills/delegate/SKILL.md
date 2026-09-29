---
name: delegate
description: Hand a self-contained sub-task over text files to a cheaper model and get back only the short answer. Use to summarize, extract fields, classify, translate or answer a question about a long file, page or transcript (resumir, extrair, classificar) without reading it into context.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/delegate.sh *)
---

# delegate

Nothing runs until you call the script. Run it with Bash, passing the
instruction and the input files. It sends them to a cheap model in a single
call and prints the answer, so you pay context only for the answer:

```bash
${CLAUDE_SKILL_DIR}/scripts/delegate.sh "<instruction>" <file> [<file> ...]
```

Pipe command output with `-`:

```bash
git log --since=1.week | ${CLAUDE_SKILL_DIR}/scripts/delegate.sh "List the user-facing changes, one line each" -
```

## Writing the instruction

The other model sees only the instruction and the files, nothing from this
conversation. Say what you want back and in what shape:

- Good: `"List every deadline mentioned, as 'date - what - who'. If none, say 'none'."`
- Weak: `"Summarize this."`

Ask for the shortest output that still answers the question; its answer
lands in your context.

## Options

| Option | Use |
|---|---|
| `--max-tokens N` | Cap on the answer length. Default 4000. |
| `--out FILE` | Save the answer to a file and print only path, size and preview. Use when the result is long or is itself an artifact. |
| `--backend anthropic` | Claude Haiku through the API. Needs `ANTHROPIC_API_KEY`. |
| `--backend ollama` | Local model, free, nothing leaves the machine. Needs a running Ollama and `SUN_DELEGATE_OLLAMA_MODEL` or `--model`. |
| `--model ID` | Override the model. |

Default `auto` uses `anthropic` when the key is set, otherwise `ollama`.

## When to use something else

- The task needs tools, several steps or judgement across files: use the
  `worker` subagent, which runs a full agent loop on a cheap model.
- The file is small (under ~2000 tokens): just read it.
- The decision matters and a wrong answer is costly: read the relevant
  part yourself. Treat delegated answers as a fast first pass.

## Limits

- Text input only. Convert documents and transcribe media first.
- Input over 400000 chars is refused, never truncated. Split the file and
  delegate each part, then delegate the merge of the partial answers.
