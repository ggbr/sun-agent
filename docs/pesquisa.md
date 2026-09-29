# Pesquisa: ferramentas e economia de tokens

Levantamento feito em 29/09/2026 para orientar o que entra neste repositório.

**Como ler as tabelas.** "Principal" é a escolha recomendada para um agente
que precisa gastar poucos tokens; "Alternativas" são opções válidas para
casos específicos. Preços e benchmarks mudam rápido e parte deles veio de
fontes secundárias: confira na página do fornecedor antes de fixar qualquer
valor em código. A seção [Não verificado](#não-verificado) lista o que ficou
em aberto.

## 1. Princípios

1. **Skill + script em vez de MCP.** De cada skill, só o nome e a descrição
   ficam no contexto. O corpo do `SKILL.md` carrega quando o agente decide
   usar, e o código do script nunca entra no contexto, só a saída dele.
2. **Script grava em arquivo e devolve resumo.** Caminho, tamanho e um
   índice ou prévia. O agente busca com `rg` e lê só o trecho necessário.
3. **Scripts parametrizados.** O modelo passa argumentos, não escreve
   código. É isso que torna viável usar modelos pequenos.
4. **Trabalho pesado vai para modelo barato.** Resumir, extrair e
   classificar arquivos longos não precisa do modelo principal.
5. **MCP só quando não existe CLI.** E, nesse caso, com carregamento adiado
   das definições ou chamado pelo shell.

## 2. Mecanismos do Claude Code e do Agent SDK

Itens desta seção foram conferidos na documentação oficial
(`code.claude.com/docs`), salvo indicação em contrário.

### Skills

- Arquivo `SKILL.md` com frontmatter YAML. Todos os campos são opcionais;
  `description` é o recomendado, porque é ele que o modelo usa para decidir
  quando carregar a skill.
- `description` + `when_to_use` são cortados em 1.536 caracteres na
  listagem. A listagem inteira tem orçamento de 1% da janela de contexto;
  ao estourar, descrições das skills menos usadas são removidas.
- Campos úteis para custo: `model` (troca o modelo enquanto a skill está
  ativa), `effort`, `context: fork` (roda a skill em subagente isolado),
  `allowed-tools` (pré-aprova ferramentas), `disable-model-invocation`.
- `${CLAUDE_SKILL_DIR}` é substituído no corpo do `SKILL.md` e nas regras
  de `allowed-tools`. Usar a mesma variável nos dois lugares permite rodar
  o script da skill sem pedido de permissão.
- Essas variáveis **não** existem no ambiente dos comandos que o agente
  roda pelo Bash. Só valem como substituição de texto no markdown.

### Plugins

- Manifesto em `.claude-plugin/plugin.json`; só `name` é obrigatório.
  Os demais arquivos ficam na raiz do plugin: `skills/`, `agents/`,
  `hooks/hooks.json`, `.mcp.json`.
- Componentes são prefixados pelo nome do plugin: `sun-agent:web-fetch`.
- Um `CLAUDE.md` na raiz do plugin não é carregado como contexto.
- A pasta `bin/` coloca executáveis no `PATH` do Bash, mas plugins com
  essa pasta não são instalados no claude.ai nem no Cowork.
- Validação: `claude plugin validate <pasta>`.

### Carregar no Agent SDK

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: "...",
  options: {
    plugins: [{ type: "local", path: "/caminho/para/sun-agent" }],
  },
})) {
  if (message.type === "system" && message.subtype === "init") {
    console.log(message.plugins, message.skills);
  }
}
```

- `type` precisa ser `"local"`. Caminhos relativos resolvem a partir de
  `cwd`; o SDK não expande `~`.
- Um caminho inexistente é ignorado sem erro. Confira `plugins` e
  `plugin_errors` na mensagem `init`.
- A opção `skills` restringe o que o modelo pode invocar: lista de nomes
  (`"sun-agent:web-fetch"`), `"all"` ou `[]`.

### Subagentes

- Arquivo markdown em `agents/` com frontmatter: `name`, `description`,
  `tools`, `model` (`haiku`, `sonnet`, `opus`, ID completo ou `inherit`),
  `maxTurns`, `skills`, `effort`.
- O subagente começa com contexto próprio; o agente principal recebe só a
  resposta final.
- Em subagentes de plugin, `hooks`, `mcpServers` e `permissionMode` são
  ignorados.

### MCP

- A busca de ferramentas adia o carregamento das definições e é controlada
  por `ENABLE_TOOL_SEARCH`. A saída das ferramentas continua entrando no
  contexto.
- `MAX_MCP_OUTPUT_TOKENS` limita a saída de ferramentas MCP.
- Alternativa: chamar o servidor pelo shell com `mcporter`, `mcp-cli` ou
  `mcptools`, sem carregar nenhuma definição.

### API

- **Cache de prompt:** leitura de cache custa cerca de 0,1× do preço de
  entrada. Funciona por prefixo: qualquer byte alterado invalida tudo o
  que vem depois. Manter prompt de sistema e lista de ferramentas estáveis.
- **Batch:** 50% de desconto para trabalho que não é interativo.
- **Preços por milhão de tokens (entrada / saída):** Haiku 4.5 $1 / $5,
  Sonnet 5.5 $2 / $10, Opus 5.5 $4 / $20, Fable 5.1 $10 / $50.

## 3. Catálogo

### Navegador

| Ferramenta | Tipo | Licença | Observação |
|---|---|---|---|
| **agent-browser** (vercel-labs) | CLI | Apache-2.0 | Principal. Snapshot de acessibilidade com referências curtas (`click @e2`), headless, sessões e perfis persistentes. |
| Playwright CLI (microsoft/playwright-cli) | CLI + skill | Apache-2.0 | Alternativa. Grava snapshots em disco e devolve o caminho. |
| Playwright MCP | MCP | Apache-2.0 | Snapshot completo a cada ação. O próprio README recomenda a CLI para agentes. |
| Chrome DevTools MCP | MCP | Apache-2.0 | Melhor para depurar console, rede e performance. `--slim` reduz para 3 ferramentas. |
| browser-use | Lib + CLI | MIT | A lib roda um segundo LLM. A CLI se conecta a um Chrome aberto e mantém logins. |
| Stagehand, Skyvern | SDK / plataforma | MIT / AGPL-3.0 | Evitar: cada ação chama um segundo LLM. |
| Steel | Servidor | Apache-2.0 | Só infraestrutura de navegador. |

### Página para markdown

| Ferramenta | Tipo | Licença / preço | Observação |
|---|---|---|---|
| **defuddle** (kepano) | CLI | MIT | Principal. Local, extrai só o conteúdo. Não renderiza JavaScript. |
| Jina Reader (`r.jina.ai`) | API | Gratuito com limite | Alternativa. Renderiza JavaScript; envia a URL a terceiros. |
| Crawl4AI | Lib + CLI | Apache-2.0 | Precisa de Chromium. Bom para rastrear várias páginas. |
| Firecrawl | API + CLI | AGPL-3.0 / pago | Rastreamento e extração estruturada. |
| trafilatura | CLI Python | Apache-2.0 | Boa remoção de boilerplate. |
| Scrapling, ScrapeGraphAI | Lib | BSD / MIT | ScrapeGraphAI usa um LLM por extração. |

No teste feito aqui com a mesma página de documentação, o defuddle gerou
11.378 caracteres e o Jina Reader 20.281, porque o Jina inclui o menu de
navegação.

### Busca na web

| Ferramenta | Preço | Observação |
|---|---|---|
| **Brave Search API** | $5 por mil; crédito mensal gratuito | Principal. Índice próprio, `curl` + `jq`. |
| Tavily | Mil créditos grátis por mês | Alternativa. Já devolve conteúdo extraído. |
| Serper | A partir de $0,30 por mil | Mais barato em volume. |
| Exa | Crédito mensal gratuito | Busca semântica. |
| SearXNG | Gratuito, self-hosted | AGPL-3.0. |
| Busca embutida da Anthropic | $10 por mil + tokens | Sem chave extra; resultados entram no contexto. |

### Acesso a APIs

| Ferramenta | Tipo | Observação |
|---|---|---|
| **curl + jq** | CLI | Principal. Zero definições de ferramenta; `jq` corta os campos. |
| restish | CLI | Descobre a API a partir do OpenAPI, perfis de autenticação. |
| mcporter, mcp-cli, mcptools | CLI | Chamam servidores MCP pelo shell. |
| Composio, Arcade, Pipedream | Hospedado | OAuth gerenciado para muitos SaaS. |
| 1Password `op run`, Doppler, sops | CLI | Segredos injetados no subprocesso, fora do contexto. |

### Redução de saída

| Ferramenta | Tipo | Observação |
|---|---|---|
| **rtk** | Proxy + hook | Apache-2.0. Reescreve comandos comuns para saída curta. |
| jq, ripgrep, fd, ast-grep | CLI | Filtros básicos. |
| repomix, code2prompt | CLI | Empacotam repositórios com contagem de tokens. |
| context-mode | MCP + hooks | Elastic License v2, que não é open source. |

### Transcrição

| Ferramenta | Tipo | Preço | Observação |
|---|---|---|---|
| **mlx-whisper** | CLI local | MIT | Principal no Mac. SRT, VTT e JSON. Sem diarização. |
| whisper.cpp | CLI local | MIT | Principal no Linux. |
| **Groq Whisper** | API | $0,04/h (turbo) | Principal hospedado. Limite de 25 MB no plano gratuito. |
| parakeet-mlx | CLI local | Apache-2.0 | Mais rápido; erro em português um pouco maior que o Whisper. |
| WhisperX | CLI | BSD | Diarização. No Mac roda só em CPU. |
| Voxtral Mini Transcribe | API | $0,18/h | Diarização e timestamps por palavra. |
| ElevenLabs Scribe v2 | API | $0,22/h | Diarização. |
| Deepgram, AssemblyAI, Gladia | API | $0,15 a $0,61/h | Têm créditos iniciais. |

### Voz

| Ferramenta | Tipo | Observação |
|---|---|---|
| **edge-tts** | CLI | Principal. Gratuito, vozes pt-BR. Endpoint não oficial da Microsoft. |
| Kokoro, Piper | Local | Alternativas offline com vozes pt-BR. Piper é GPL-3. |
| Chatterbox | Local | MIT, clonagem de voz. |
| ElevenLabs, Gemini TTS, OpenAI TTS | API | Pagos. |

### Áudio e vídeo

| Ferramenta | Observação |
|---|---|
| **ffmpeg / ffprobe** | Cortar, converter, remover silêncio, queimar legendas. |
| **yt-dlp** | Baixar mídia. Precisa de `deno` para o YouTube. |
| auto-editor | Corte automático de silêncio. |
| PySceneDetect | Detecção de cenas. |

### Imagem

| Ferramenta | Tipo | Observação |
|---|---|---|
| **Gemini Flash Image** | API | Principal hospedado. Geração e edição. |
| FLUX.2, gpt-image-2, Ideogram, Recraft | API | Recraft gera SVG de verdade. |
| mflux | CLI local | FLUX no Apple Silicon. |
| ImageMagick, libvips, rembg | CLI | Redimensionar, converter, remover fundo. |
| Mermaid CLI, Graphviz, D2 | CLI | Diagramas a partir de texto. |

### Vídeo

| Ferramenta | Tipo | Observação |
|---|---|---|
| **HyperFrames** (heygen-com) | CLI | Apache-2.0. HTML para MP4, já vem com skills. |
| Remotion | CLI | Gratuito até 3 pessoas; pago para automação. |
| Manim, MoviePy | Lib | Animação matemática e edição por código. |
| **Veo 3.1 Lite** | API | Principal generativo. Cerca de $0,05 por segundo. |
| LTX, Kling, Runway, Luma | API | Via fal.ai ou direto. |
| HeyGen, Synthesia | API | Avatares. |

### OCR e visão barata

| Ferramenta | Tipo | Observação |
|---|---|---|
| **Apple Vision OCR** | CLI | Principal no Mac. |
| Tesseract | CLI | Principal no Linux. |
| PaddleOCR, Surya, docTR | Lib | Surya tem restrição de uso comercial nos pesos. |
| Mistral OCR | API | Cerca de $4 por mil páginas. |
| Gemini Flash-Lite | API | Descreve imagens e vídeos por fração do custo. |

### Gerar documentos

| Ferramenta | Tipo | Observação |
|---|---|---|
| **pandoc** | CLI | Markdown para docx, html, pptx, epub. |
| **Typst** | CLI | PDF rápido, marcação curta. |
| **Marp CLI** | CLI | Slides a partir de markdown. |
| python-docx, python-pptx, openpyxl | Lib | Usar em scripts com modelo pronto. |
| LibreOffice headless | CLI | Conversão universal, lenta. |
| WeasyPrint | CLI | HTML e CSS para PDF sem navegador. |
| qpdf, pdftk, Ghostscript | CLI | Juntar, dividir, comprimir PDF. |
| ExcelJS | Lib | Sem manutenção desde 2023. Evitar. |

### Ler documentos

| Ferramenta | Tipo | Licença | Observação |
|---|---|---|---|
| **markitdown** (Microsoft) | CLI | MIT | Principal para Office e HTML. |
| **pdftotext** (poppler) | CLI | GPL | Principal para PDF com texto. |
| Docling (IBM) | CLI | MIT | Melhor em tabelas; instalação grande. |
| pymupdf4llm | Lib | AGPL ou comercial | Rápido; atenção à licença. |
| LiteParse | CLI | Apache-2.0 | Alternativa permissiva. |
| marker, MinerU | CLI | Com restrições | Pedem GPU. |
| LlamaParse, unstructured | API | Pago | Os dados saem da máquina. |

### Dados

| Ferramenta | Observação |
|---|---|
| **DuckDB CLI** | SQL direto em CSV, Parquet, JSON e XLSX. Agregar antes de mostrar ao modelo. |
| qsv | `qsv stats` dá um perfil compacto de um CSV. |
| sqlite3, jq, yq | Básicos. |
| usql | Uma CLI para vários bancos. |
| vl-convert | Vega-Lite para PNG ou SVG sem navegador. |
| DBHub | MCP de banco com duas ferramentas. |

### Comunicação

| Ferramenta | Observação |
|---|---|
| **gh** | GitHub. `--json --jq` corta a saída. |
| **gog**, **gws** | Google Workspace por CLI. |
| himalaya | E-mail por IMAP e SMTP. |
| Telegram Bot API, webhooks do Discord | Um `curl` por mensagem. |
| MCPs oficiais de Slack, Notion, Google | Remotos, com OAuth. |
| rclone, aws, gcloud | Armazenamento. |
| WhatsApp Cloud API, Twilio | Único caminho oficial para WhatsApp. |

### Busca local e memória

| Ferramenta | Observação |
|---|---|
| **ripgrep** | Base. Usar `-l`, `-c`, `-m`. |
| qmd | Busca híbrida local; modelos de cerca de 2 GB. |
| sqlite-vec, LanceDB, Chroma | Exigem script próprio. |
| basic-memory, claude-mem | AGPL-3.0. |
| mem0 | Apache-2.0; self-host precisa de Postgres. |

### Delegar a modelo barato

| Ferramenta | Observação |
|---|---|
| **API da Anthropic com Haiku 4.5** | Principal. A chave já existe em quem usa o Agent SDK. |
| **Ollama** | Local e gratuito. |
| llm (simonw) | CLI com plugins para vários provedores. |
| MLX-LM, LM Studio | Locais no Apple Silicon. |
| OpenRouter | Uma chave para vários modelos. |
| aichat | Binário único. |

### Agregadores de mídia

| Serviço | CLI oficial | MCP oficial |
|---|---|---|
| **fal.ai** | `genmedia` | Sim |
| Replicate | `replicate` | Sim |
| Groq | Não | Sim |
| OpenRouter | Não | Não |

### Runtime

| Ferramenta | Observação |
|---|---|
| **uv** | Scripts Python de arquivo único com dependências embutidas (PEP 723). |
| bun, deno, npx | Scripts TypeScript de arquivo único. |
| just | `just --list` funciona como menu compacto. |
| Docker, E2B, Daytona, Modal | Isolamento local e remoto. |

### Onde achar mais

| Fonte | Para quê |
|---|---|
| github.com/anthropics/skills | Skills oficiais. |
| github.com/anthropics/claude-plugins-official | Plugins revisados. |
| skills.sh | Catálogo com ranking de uso. |
| agentskills.io | Especificação do formato. |
| github.com/punkpeye/awesome-mcp-servers | Lista de servidores MCP. |
| registry.modelcontextprotocol.io | Registro oficial de MCP, ainda em prévia. |
| github.com/hesreallyhim/awesome-claude-code | Hooks, comandos e utilitários. |

## 4. Alertas

- **Licença das skills oficiais de documento.** As skills `docx`, `pdf`,
  `pptx` e `xlsx` da Anthropic são proprietárias: não podem ser copiadas
  para este repositório. Instalar pelo marketplace.
- **Descontinuados ou sem manutenção**, segundo a pesquisa: API do Sora
  (removida em 24/09/2026), acesso gratuito do Gemini CLI (encerrado em
  18/06/2026), Motion Canvas, Editly, Demucs, ExcelJS, `mods`, Stainless.
- **Modelos com data de desligamento:** `whisper-1` e `gpt-4o-transcribe`
  da OpenAI (26/02/2027), Gemini 2.5 Flash Image (02/10/2026).
- **WhatsApp não oficial.** wacli, Baileys e Evolution API usam protocolo
  não oficial e há risco de banimento da conta.
- **Licenças restritivas:** AGPL em Firecrawl, Skyvern, SearXNG,
  pymupdf4llm, basic-memory e claude-mem; Elastic License em context-mode;
  restrição de receita nos pesos do marker e do Surya.
- **Instaladores por `curl | bash`** (`genmedia`, `ntn`): ler o script
  antes de rodar.
- **Anti-bot.** Scrapling e Steel anunciam recursos para burlar CAPTCHA e
  detecção de bots. Não foram avaliados e ficam fora deste repositório.

## 5. Não verificado

- Os benchmarks de tokens por fluxo de navegador (114 mil no Playwright
  MCP, 27 mil na Playwright CLI, 7 mil no agent-browser) vêm de blogs de
  terceiros e não foram reproduzidos.
- Não há um benchmark único de pt-BR cobrindo todos os motores de
  transcrição; os números de erro são para português em geral.
- Preços marcados como de fonte secundária nos relatórios: Serper,
  Browserbase, Arcade, Pipedream, Zapier, Deepgram, AssemblyAI, Gladia,
  FLUX, Kling, Runway, Luma e os editores de vídeo por API.
- Limites do plano gratuito do Gemini divergem entre fontes.
- Licenças de `ck`, `semtools`, `mflux`, DBHub e vl-convert.
- As ferramentas clássicas (pandoc, ffmpeg, ImageMagick, LibreOffice,
  Tesseract e semelhantes) foram listadas por conhecimento prévio; versões
  e comandos de instalação precisam de um teste na máquina de destino.
