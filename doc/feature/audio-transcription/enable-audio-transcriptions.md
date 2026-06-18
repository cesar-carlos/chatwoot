# Como habilitar transcrição de áudio

## Dois modos (mutuamente exclusivos)

| Modo | Como habilitar | Comportamento |
|------|----------------|---------------|
| **Automático (original)** | Toggle ON em Settings → Account → Transcribe Audio Messages | Transcreve no upload via OpenAI |
| **Manual (fork Groq)** | Toggle OFF + token Groq no perfil do usuário | Botão de transcrição na conversa |

**Regra**: quando o toggle está **ON** (`audio_transcriptions = true`), o modo manual Groq fica **desabilitado** (botão oculto + API retorna 422).

### Toggle na UI (Settings → Account)

- **ON** = transcrição automática OpenAI em cada upload de áudio
- **OFF** = transcrição manual Groq — cada agente precisa configurar um token Groq em **Settings → Profile**

## Modo automático (OpenAI)

1. Habilite na conta (toggle ON ou script):
   ```bash
   bundle exec rails runner doc/scripts/enable-audio-transcription.rb [account_id]
   ```
2. Áudios enviados são transcritos automaticamente no upload.
3. Não é necessário token Groq no perfil.

## Modo manual (Groq)

1. Confirme que o toggle **Transcribe Audio Messages** está **OFF** na conta.
2. Acesse **Settings → Profile**.
3. Preencha **Token da API Groq** (armazenado criptografado em repouso).
4. Clique em **Salvar Token**.
5. O campo mostra "Token configured" após salvar (o valor não é retornado pela API por segurança).

## Estados de transcrição (`meta.transcription.state`)

| Estado | Significado |
|--------|-------------|
| `pending` | Reservado para fila assíncrona |
| `processing` | Transcrição em andamento (UI mostra loading) |
| `success` | Texto disponível em `transcription.text` e `transcribed_text` |
| `error` | Falha com mensagem em `transcription.error` |

Somente transcrições com `state=success` são retornadas como cache.

## Idempotência e lock

- Lock Redis por `attachment_id` (TTL ~120s) evita requisições paralelas.
- Requisição concorrente com lock ativo e `started_at` recente retorna **409 Conflict** com chave `AUDIO.TRANSCRIPTION.IN_PROGRESS`.
- Estado `processing` **obsoleto** (`started_at` ausente ou mais antigo que o TTL de 120s) é recuperado automaticamente e a transcrição pode ser reexecutada.
- `force_refresh=true` ignora cache de sucesso e estados `processing`/`error`.
- Cache de sucesso é respeitado salvo `force_refresh=true`.

## FFmpeg

- **Não é necessário** para formatos aceitos nativamente pelo Groq: mp3, ogg, opus, wav, webm, m4a, flac.
- FFmpeg é exigido apenas para conversão de formatos não suportados (ex.: aac, amr).

## Rate limiting

- Máximo **10 requisições/minuto por usuário** (configurável via `RATE_LIMIT_AUDIO_TRANSCRIPTION`).
- Rack::Attack em produção + guard no controller em todos os ambientes.
- Resposta **429** com chave `AUDIO.RATE_LIMIT.MESSAGE`.

## Teste rápido (modo manual)

1. Abra uma conversa com anexo de áudio.
2. Clique no botão de transcrição (ícone de ouvido).
3. Confirme que `POST /api/v1/accounts/:id/transcriptions` retorna sucesso.
4. Confirme que o texto transcrito aparece no card de áudio.

## Teste rápido (modo automático)

1. Habilite o toggle de transcrição na conta.
2. Envie um áudio na conversa.
3. Aguarde a transcrição automática aparecer (sem clicar no botão Groq).

## Smoke test (sem Groq key)

```bash
bundle exec rails runner doc/scripts/smoke-test-audio-transcription.rb
```

## Troubleshooting

- **Botão de transcrição não aparece**: toggle automático está ON.
- **422 automatic_transcription_enabled**: conta tem modo automático; desabilite o toggle para usar Groq manual.
- **409 transcription_in_progress**: outra transcrição está em andamento (lock ativo + `started_at` recente). Aguarde ou tente novamente.
- **Processing preso**: estados `processing` com mais de ~120s são tratados como obsoletos e reprocessados automaticamente.
- **429 rate_limit_exceeded**: aguarde 1 minuto.
- **Token missing**: configure token Groq no perfil do usuário.
- Valide no banco: `users.groq_token` preenchido (valor criptografado) para modo manual.
- Faça logout/login para renovar estado do usuário no frontend.
