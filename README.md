# sun-agent

Caixa de ferramentas para agentes construídos com o Claude Agent SDK. O
repositório contém só as ferramentas; o agente fica em outro projeto e
carrega este como plugin.

O objetivo é dar capacidade ao agente gastando poucos tokens:

- cada ferramenta é uma **skill**: só nome e descrição ficam no contexto,
  o resto carrega quando o agente decide usar;
- cada skill chama um **script** que grava o resultado em arquivo e
  devolve caminho, tamanho e um resumo curto;
- trabalho pesado de leitura vai para um **modelo barato**.

## Skills

| Skill | O que faz | Precisa de |
|---|---|---|
| `web-fetch` | Baixa uma página como markdown limpo | `npx` (defuddle) ou `curl` (Jina Reader) |
| `transcribe` | Transcreve áudio ou vídeo para txt, srt ou vtt | `mlx_whisper` + `ffmpeg`, ou `GROQ_API_KEY` |
| `delegate` | Entrega uma sub-tarefa sobre arquivos a um modelo barato | `ANTHROPIC_API_KEY`, ou Ollama local |

Subagente incluído: `worker`, que roda em Haiku para tarefas mecânicas com
várias etapas.

Todos os scripts precisam de `bash`, `curl` e `jq`.

## Usar no Agent SDK

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: "Transcreva reuniao.m4a e liste as decisões tomadas",
  options: {
    plugins: [{ type: "local", path: "/caminho/absoluto/para/sun-agent" }],
    allowedTools: ["Skill", "Bash", "Read", "Grep", "Glob"],
    env: { ...process.env, SUN_AGENT_OUT: "/caminho/para/saida" },
  },
})) {
  if (message.type === "system" && message.subtype === "init") {
    console.log(message.plugins, message.skills);
  }
}
```

```python
from claude_agent_sdk import query, ClaudeAgentOptions

options = ClaudeAgentOptions(
    plugins=[{"type": "local", "path": "/caminho/absoluto/para/sun-agent"}],
    allowed_tools=["Skill", "Bash", "Read", "Grep", "Glob"],
)
```

Desative as ferramentas embutidas que fazem o mesmo trabalho, senão o
modelo prefere elas à skill. No teste com Haiku, o `WebFetch` embutido foi
escolhido no lugar de `web-fetch` até ser desativado:

```typescript
options: {
  disallowedTools: ["WebFetch", "WebSearch"],
}
```

Um caminho de plugin que não existe é ignorado sem erro. Confira na
mensagem `init` se `sun-agent` aparece em `plugins` e se as skills
aparecem como `sun-agent:web-fetch`, `sun-agent:transcribe` e
`sun-agent:delegate`.

Para testar no Claude Code:

```bash
claude --plugin-dir /caminho/para/sun-agent
```

## Configuração

As chaves chegam aos scripts pelo ambiente do agente. Veja
[.env.example](.env.example) para a lista completa. Nenhuma é obrigatória:
cada skill informa o que falta quando não encontra um backend.

Os resultados são gravados em `$SUN_AGENT_OUT`, ou em `./.sun-agent` no
diretório de trabalho do agente quando a variável não está definida.

## Privacidade

Cada skill tem um caminho local e um hospedado. O hospedado envia dados a
terceiros:

| Skill | Local | Hospedado |
|---|---|---|
| `web-fetch` | `--backend defuddle` | Jina Reader recebe a URL |
| `transcribe` | `--backend mlx` | Groq recebe o áudio |
| `delegate` | `--backend ollama` | Anthropic recebe o texto |

## Criar uma skill nova

1. Crie `skills/<nome>/SKILL.md` e `skills/<nome>/scripts/<nome>.sh`.
2. No `SKILL.md`, a `description` diz o que a skill faz e quando usar, com
   o caso principal primeiro. O corpo fica curto: comando, opções, como
   consumir o resultado, limites.
3. Referencie o script com `${CLAUDE_SKILL_DIR}/scripts/<nome>.sh` no corpo
   e em `allowed-tools`.
4. O script segue o contrato:
   - grava o resultado em arquivo e imprime caminho, tamanho e prévia;
   - erros em uma linha, em `stderr`, com código de saída diferente de zero;
   - nunca corta a entrada em silêncio: recusa e diz como dividir;
   - não depende de outros arquivos do repositório.
5. Valide com `claude plugin validate .`.

## Pesquisa

[docs/pesquisa.md](docs/pesquisa.md) reúne o levantamento de ferramentas
por categoria, os mecanismos de economia de tokens e os alertas de licença
e de serviços descontinuados.

## Estado dos testes

| Skill | Como foi testada |
|---|---|
| `web-fetch` | Páginas reais, com os dois backends, e uma execução completa pelo agente em Haiku |
| `transcribe` | Servidor simulado do Groq e `mlx_whisper` simulado; ainda não rodou com áudio real |
| `delegate` | Servidor simulado da Anthropic e do Ollama; ainda não rodou com modelo real |
