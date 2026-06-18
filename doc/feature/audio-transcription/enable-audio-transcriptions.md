# Como habilitar transcrição de áudio

## Modo manual (único modo disponível)

A transcrição **não é automática**. O agente clica no ícone de ouvido (orelinha) em cada mensagem de áudio para transcrever.

| Requisito | Onde configurar |
|-----------|-----------------|
| Token Groq por usuário | **Settings → Profile** → Token da API Groq |

O toggle de transcrição automática em Settings → Account foi desabilitado neste fork.

## Configuração

1. Acesse **Settings → Profile**.
2. Preencha **Token da API Groq** (armazenado criptografado em repouso).
3. Clique em **Salvar Token**.
4. O campo mostra "Token configured" após salvar (o valor não é retornado pela API por segurança).
5. Após recarregar a página (F5), `has_groq_token` é restaurado via `/auth/validate_token`.

## Estados de transcrição (`meta.transcription.state`)

| Estado | Significado |
|--------|-------------|
| `pending` | Reservado para fila assíncrona |
| `processing` | Transcrição em andamento no backend (UI só mostra loading durante clique ativo) |
| `success` | Texto disponível em `transcription.text` e `transcribed_text` |
| `error` | Falha com mensagem em `transcription.error` |

Somente transcrições com `state=success` (ou `transcribed_text` legado) são retornadas como cache — **sem nova chamada à API Groq**.

## Idempotência e lock

- Antes de chamar a API Groq, o backend consulta `attachment.meta` no banco.
- Se já existe transcrição com sucesso, retorna o texto em cache (`cached: true`) imediatamente.
- Lock Redis por `attachment_id` (TTL ~120s) evita requisições paralelas.
- Requisição concorrente com lock ativo e `started_at` recente retorna **409 Conflict** com chave `AUDIO.TRANSCRIPTION.IN_PROGRESS`.
- Estado `processing` **obsoleto** (`started_at` ausente ou mais antigo que o TTL de 120s) é recuperado automaticamente e a transcrição pode ser reexecutada.
- `force_refresh=true` ignora cache de sucesso e estados `processing`/`error`.

## FFmpeg

- **Não é necessário** para formatos aceitos nativamente pelo Groq: mp3, ogg, opus, wav, webm, m4a, flac.
- FFmpeg é exigido apenas para conversão de formatos não suportados (ex.: aac, amr).

## Rate limiting

- Máximo **10 requisições/minuto por usuário** (configurável via `RATE_LIMIT_AUDIO_TRANSCRIPTION`).
- Rack::Attack em produção + guard no controller em todos os ambientes.
- Resposta **429** com chave `AUDIO.RATE_LIMIT.MESSAGE`.

## Teste rápido

1. Configure token Groq no perfil do usuário.
2. Abra uma conversa com anexo de áudio.
3. Clique no botão de transcrição (ícone de ouvido).
4. Confirme que `POST /api/v1/accounts/:id/transcriptions` retorna sucesso.
5. Confirme que o texto transcrito aparece no card de áudio.
6. Clique novamente no mesmo áudio — deve retornar cache sem nova chamada à API (`cached: true`).

## Smoke test (sem Groq key)

```bash
bundle exec rails runner doc/scripts/smoke-test-audio-transcription.rb
```

## Troubleshooting

- **Botão de transcrição não aparece**: configure token Groq no perfil; recarregue a página se acabou de salvar o token.
- **409 transcription_in_progress**: outra transcrição está em andamento (lock ativo + `started_at` recente). Aguarde ou tente novamente.
- **Processing preso na UI**: a UI só mostra "Transcribing audio..." durante uma requisição ativa do usuário; estados `processing` antigos no banco são ignorados na interface.
- **429 rate_limit_exceeded**: aguarde 1 minuto.
- **Token missing**: configure token Groq no perfil do usuário.
- Valide no banco: `users.groq_token` preenchido (valor criptografado).
