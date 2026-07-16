# Troubleshooting — Provider Evolution Go

Sintomas comuns, causas e ações. Complementa [validation-checklist.md](./validation-checklist.md).

---

## Conexão e licença

### Runbook — licença Evolution Go

| Situação | Sintoma no Chatwoot | Ação operador |
|----------|---------------------|---------------|
| Primeiro deploy | Painel Go pede login | Magic Link — [getting-started](https://docs.evolutionfoundation.com.br/en/evolution-go/getting-started) |
| Licença expirada | `GET /server/ok` OK mas connect/QR falha; logs Go mencionam license | Reativar no **painel Go** (fora do adapter Chatwoot) |
| Licença inválida pós-migração | 403 em admin endpoints | Revalidar licença no host; reiniciar container |
| Sem licença em staging | E2E bloqueado | Operador ativa licença na instância Go |

**Escopo fork:** Chatwoot **não** implementa fluxo de licença — apenas documenta pré-requisito ([decisions.md §15](./decisions.md)).

### Painel Go pede ativação de licença

| Causa | Ação |
|-------|------|
| Primeiro acesso | Magic Link no painel Go — [getting-started](https://docs.evolutionfoundation.com.br/en/evolution-go/getting-started) |
| Licença expirada | Reativar via painel; fora do escopo adapter Chatwoot |

### `GET /server/ok` falha

- Servidor Go down ou porta errada (`8080` default)
- PostgreSQL `POSTGRES_AUTH_DB` / `POSTGRES_USERS_DB` inacessível

---

## QR e pairing

### QR não aparece no wizard

| Causa | Verificação | Ação |
|-------|-------------|------|
| Connect não executado | Logs backend | `POST /instance/connect` antes do QR |
| Token errado | Header | `apikey: instance_token` (não global key) |
| ActionCable off | DevTools WS | Polling `GET /instance/qr` |
| Webhook `QRCODE` não chega | Logs | Usar polling como fallback |

### QR response vazio

```http
GET {base_url}/instance/qr
apikey: {instance_token}
```

Esperado: `data.Qrcode` (base64 PNG), `data.Code` (string).

### Pairing code não gera

```http
POST {base_url}/instance/pair
apikey: {instance_token}
{ "phone": "5511999999999" }
```

Campo `phone` obrigatório — E.164 sem `+`.

### `Connected: true` mas `LoggedIn: false`

- Aguardar alguns segundos após scan
- Sessão duplicada em outro dispositivo → `DELETE /instance/logout` e reconectar

---

## Webhooks

### Inbound não chega no Chatwoot

| Check | Esperado |
|-------|----------|
| `webhookUrl` no connect | `https://{FRONTEND_URL}/webhooks/evolution_go/{name}?token=...` |
| `subscribe` inclui `MESSAGE` | Sim |
| `FRONTEND_URL` público | Evolution Go alcança URL |
| Auth | `?token=` = `webhook_token` do channel |
| Sidekiq | `WhatsappEventsJob` prepend rodando |
| Filtros | `@g.us` ignorado quando `ignore_groups: true` (default); `fromMe` echo filtrado |

### HTTP 401 no webhook

- `webhook_token` na URL ≠ `provider_config.webhook_token`
- Token regenerado sem re-connect na Go

### HTTP 404

- `instance_name` na rota ≠ `provider_config.instance_name`

### Mensagens de grupo viram conversas separadas (uma por participante)

| Causa | Ação |
|-------|------|
| `ignore_groups: true` (default) | Comportamento antigo: grupos filtrados ou tratados como 1:1 se payload resolver participante |
| `ignore_groups: false` mas conversas antigas | Conversas criadas antes da correção não se fundem — só **novas** mensagens usam JID do grupo |
| Payload EG com `key.remoteJid` = participante | `EvolutionGoPayloadAdapter` deve preferir `Info.Chat` `@g.us` — validar com fixture real no E2E |

---

## Reconnect

### Webhook para de funcionar após reconnect manual no painel Go

| Causa | Ação |
|-------|------|
| Operador reconectou no painel Go sem `webhookUrl` | Usar botão **Reconnect** no Chatwoot — reenvia connect com URL + `subscribe` |
| `webhook_token` rotacionado | `ConnectionService#reconnect!` com novo secret + atualizar URL no Go |
| `subscribe` incompleto | Usar lista canônica via `WebhookSubscribeSync` — ver [webhook-events.md](./webhook-events.md) |

**Regra:** todo `POST /instance/connect` do fork deve incluir a lista canônica (gerenciada por `WebhookSubscribeSync`):

```json
{
  "webhookUrl": "https://{FRONTEND_URL}/webhooks/evolution_go/{instance_name}?token={webhook_token}",
  "subscribe": [
    "MESSAGE", "SEND_MESSAGE", "SEND_MESSAGE_UPDATE", "CONNECTION", "QRCODE", "READ_RECEIPT",
    "MESSAGE_DELETE", "MESSAGES_DELETE", "MESSAGES_EDITED", "MESSAGE_EDIT", "HISTORY_SYNC"
  ]
}
```

Quando `ignore_groups: false`, incluir também `"GROUP"`. Botão **Sync webhook events** na health page ou `rake evolution_go:sync_webhooks`.

Ver [decisions.md §23](./decisions.md).

**Não usar** `POST /instance/reconnect` no fork — não garante webhook ([decisions.md §24](./decisions.md)).

### Reconnect no Chatwoot não restaura sessão

1. `POST /instance/disconnect` (instance token)
2. `POST /instance/connect` com webhook + subscribe
3. Exibir QR novamente se `LoggedIn: false`

### Duplicação de mensagens

| Causa | Ação |
|-------|------|
| Echo `fromMe` | Normalizer deve ignorar |
| `SEND_MESSAGE` + outbound CW | `SEND_MESSAGE` is subscribed; use `ignore_from_me_echo: false` for phone echo sync; dedup by `source_id` |
| Retry Go (5×) | Dedup Redis `source_id` |

---

## Envio outbound

### HTTP 401 em `/send/text`

- Header deve ser `apikey: instance_token` — **não** `global_api_key`

### Mensagem enviada mas sem `source_id` no CW

- `process_response` deve usar `data.Info.ID` — **não** `key.id`
- Resposta wrapped: verificar `parsed.dig('data', 'Info', 'ID')`

### HTTP 400 send text

```json
{ "number": "5511999999999", "text": "..." }
```

Campos `number` e `text` obrigatórios — ver [send-a-text-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-text-message).

### Template forçado pelo Chatwoot

- Confirmar prepend `MessageWindowService` para `evolution_go`
- `can_reply?` deve ser true

---

## Proxy

| Sintoma | Ação |
|---------|------|
| Create falha com proxy | Validar `proxy.address` + `port` |
| Remover proxy | `DELETE /instance/proxy/{instanceId}` |
| WA não conecta com proxy | Testar sem proxy; reconectar |

---

## Instância / admin

### Delete instance falha

- Path: `DELETE /instance/delete/{instanceId}` — usar **UUID** `instance_id`, não `instance_name`
- Auth: `global_api_key`

### Duas inboxes mesmo `instance_name`

- Índice único fork — [decisions.md §3](./decisions.md)
- Colisão de rota webhook

---

## Diagnóstico rápido (comandos)

```bash
# Health
curl -sS "${BASE_URL}/server/ok"

# Status
curl -sS "${BASE_URL}/instance/status" -H "apikey: ${INSTANCE_TOKEN}"

# Send test
curl -sS -X POST "${BASE_URL}/send/text" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"number":"5511999999999","text":"ping"}'
```

---

## Quando escalar

| Sintoma | Próximo passo |
|---------|---------------|
| Payload webhook desconhecido | Salvar raw JSON → fixture + atualizar normalizer |
| `READ_RECEIPT` formato diferente | Spike Fase 2 |
| Mídia inbound falha | `POST /message/downloadmedia` only ([decisions.md §25](./decisions.md)) |
| PDF/imagem abre com "Falha ao carregar" | Go devolve `data:<mime>;base64,...` em `data.base64`; Chatwoot deve strip do prefixo via `MediaDecoder` — blobs corrompidos têm magic `75ab5a6a…` |
| Recuperar blobs já salvos | `RAILS_ENV=production dry_run=1 limit=50 bundle exec rake evolution_go:repair_corrupt_media` depois `dry_run=0` |
| `[Unsupported message type]` em mensagem do celular | (1) Payload `protocolMessage` (revoke/edit) PascalCase → `MessageDeletePayloadExtractor#normalize_key` + skip em `PhoneOutgoingSyncService`. (2) PDF/doc com caption chega como `documentWithCaptionMessage` — sem unwrap vira placeholder; corrigido em `EvolutionGoPayloadAdapter#unwrap_nested_message` (jul/2026). (3) Mídia **view once** indisponível: `IsUnavailable: true` + `UnavailableType: view_once` **sem** `Message` — WhatsApp não entrega o conteúdo à API; corrigido jul/2026: normalizer cria `type: unsupported` + `unavailable_type: view_once` (i18n `view_once_unavailable` / bubble `VIEW_ONCE_MEDIA_UNAVAILABLE`) |
| PDF via n8n / API externa falha ou vira unsupported | `POST /send/media`: usar `filename` (não `fileName`); `type: "document"`; `url` = HTTPS público ou base64 string (não buffer binário); echo webhook com caption passa pelo unwrap acima |
| Delete/edit no celular não reflete no CW | Corrigido jul/2026: sync services aplicam `fromMe`; `SEND_MESSAGE` processa protocol delete/edit antes do drop de echo |
| Delete no CW mostra só aviso em inglês / some o texto | Inbound delete **mantém** o conteúdo original, marca `deleted` + destaque vermelho; i18n `DELETED_MESSAGE_NOTICE` / `DELETED_BY_CONTACT_NOTICE` (en + pt/pt_BR). Hard refresh se o aviso ainda estiver em inglês |
| Edit do cliente cria `[Unsupported message type]` | Go envia `Info.Edit=1` + `secretEncryptedMessage` (sem plaintext/`protocolMessage`); job detecta e descarta o envelope — conteúdo editado só atualiza quando vier plaintext (`protocolMessage` / `MESSAGES_EDITED`) |
| Anexo inbound lento ou some após texto | Storm de `NoMethodError` em `process_evolution_go_status` (READ_RECEIPT) saturava fila `:default` junto com `MediaDownloadJob`; corrigido em `IncomingMessageEvolutionGo` |
| Documento só-arquivo some / caption sem arquivo na UI | Race: `MediaDownloadJob` enfileirado **dentro** da transaction → job rodava antes do commit (`Message.find` nil, 12ms no-op). Corrigido: enqueue em `process_messages` (após transaction) + retry se mensagem ausente. Também: usar `Message.base64` inline do webhook (Go já decripta) e `message.updated` **depois** de criar o attachment |
| Mensagem sem anexo e sem erro visível | `MediaAttachmentService` marca `evolution_go_media_failed` quando base64 vazio; checar `content_attributes` da mensagem |
| Refresh de contatos não atualiza foto | `user/check` do Go devolve `data.Users[].IsInWhatsapp` (não `exists`); parser corrigido. `/user/avatar` devolve **base64** (não URL) — `ContactEnrichmentService` anexa base64 direto; URL HTTP ainda usa `AvatarFromUrlJob`. Se logs mostram `Net::ReadTimeout` em `POST /user/avatar`, a falha é no servidor Go/WhatsApp CDN (path sem retry, timeout 12s). Fork grava `evolution_go_avatar_attempted_at` e **não reenfileira** enrichment por falta de avatar por 6h (evita saturar `:low`); `force: true` / botão Refresh ainda tenta de novo. Nome/status ainda atualizam via `/user/info` quando o Go responde |
| Reply no WhatsApp chega sem quote no CW | Go envia `contextInfo.stanzaID` (ID maiúsculo); parser lia só `stanzaId` (Baileys) → `in_reply_to_external_id` ficava nil. Corrigido jul/2026: aceita `stanzaId`/`stanzaID`. Mensagens antigas não backfillam — reenviar um reply de teste |
| Reply no CW chega no celular sem quote | Ao citar mensagem **própria** (outgoing), `participant` ia `nil` porque o canal Evolution Go usa phone placeholder `+55000…`. Corrigido: JID do negócio vem do `instance_name` (dígitos embutidos) e `quoted` usa `.compact`. Citar mensagem do **contato** já usava o JID do peer |
| Aparece `[Reaction message]` na conversa | Comportamento antigo (placeholder). Agora `reactionMessage` atualiza a mensagem alvo com chip. Limpar legado: `dry_run=1 bundle exec rake evolution_go:cleanup_reaction_placeholders` depois `dry_run=0` |
| Reação do cliente não aparece no CW | Mensagem alvo precisa existir com `source_id` = `reactionMessage.key.id`. Checar `mutation_stats.inbound_reaction_skipped` (Go) ou logs `[EVOLUTION] inbound_reaction_skipped` (Node) |
| Agente não consegue reagir / API hang | Context menu → Go `POST /message/react` (timeout 15s, sem retry). Node `POST /message/sendReaction/:instance`. Em algumas versões Go ([#28](https://github.com/evolution-foundation/evolution-go/issues/28)) o endpoint pode hang — atualizar Evolution Go / validar no E2E |
| Chip duplicado (celular + dashboard) | Ator unificado `user:self`; reagir no dashboard substitui a reação `fromMe` do negócio |
| Clique no chip não remove | Só chips do negócio (`user:self` / `from: user`) são clicáveis; inbox precisa ser `evolution_go` ou `evolution` com `source_id` |
