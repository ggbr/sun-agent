---
name: transcribe
description: Transcribe an audio or video file to text or subtitles (txt, srt, vtt) saved to disk, returning only the file path, size and a short preview. Use for speech-to-text, meeting recordings, voice messages, subtitles (transcrever áudio, legendas).
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/transcribe.sh *)
---

# transcribe

Nothing is transcribed until you run the script. Run it now with Bash,
passing the media file:

```bash
${CLAUDE_SKILL_DIR}/scripts/transcribe.sh "<file>" --lang pt --format txt
```

It writes the transcript to a file and prints only this summary, so the
transcript stays out of the context until you read part of it:

```
file: ./.sun-agent/transcripts/<name>.txt
backend: mlx (mlx-community/whisper-large-v3-turbo)
size: 8420 chars (~2105 tokens)
preview: Bom dia a todos, vamos começar...
```

## Options

| Option | Use |
|---|---|
| `--lang CODE` | ISO-639-1 language of the speech. Default `pt`. |
| `--format txt\|srt\|vtt` | `txt` for reading, `srt`/`vtt` for subtitles with timestamps. |
| `--backend mlx` | Local, free, Apple Silicon. Needs `mlx_whisper` and `ffmpeg`. |
| `--backend groq` | Hosted, needs `GROQ_API_KEY`. Uploads the audio to Groq. |
| `--model ID` | Override the model. |
| `--out DIR` | Output directory. |

Default `auto` uses `mlx` when installed, otherwise `groq`. Use
`--backend mlx` when the recording is confidential.

## Using the result

- Search the transcript with `rg -n "<term>" <file>` and Read only that range.
- For a summary, action items or an extraction from a long transcript,
  hand the file to the `delegate` skill instead of reading it.

## Limits

- One file per call. No speaker diarization.
- Groq accepts flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, webm. Files over
  the upload limit (25 MB, `SUN_GROQ_MAX_MB` to change) are compressed with
  `ffmpeg` first; without `ffmpeg` the script stops and says so.
- To transcribe a video from a URL, download it first (for example with
  `yt-dlp -x`) and pass the local file.
