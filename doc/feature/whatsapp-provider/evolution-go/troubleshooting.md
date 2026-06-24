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
| Filtros | `@g.us`, `fromMe` ignorados por design F1 |

### HTTP 401 no webhook

- `webhook_token` na URL ≠ `provider_config.webhook_token`
- Token regenerado sem re-connect na Go

### HTTP 404

- `instance_name` na rota ≠ `provider_config.instance_name`

---

## Reconnect

### Webhook para de funcionar após reconnect manual no painel Go

| Causa | Ação |
|-------|------|
| Operador reconectou no painel Go sem `webhookUrl` | Usar botão **Reconnect** no Chatwoot — reenvia connect com URL + `subscribe` |
| `webhook_token` rotacionado | `ConnectionService#reconnect!` com novo secret + atualizar URL no Go |
| `subscribe` sem `MESSAGE` | Garantir `["MESSAGE","CONNECTION","QRCODE"]` em todo connect |

**Regra:** todo `POST /instance/connect` do fork deve incluir:

```json
{
  "webhookUrl": "https://{FRONTEND_URL}/webhooks/evolution_go/{instance_name}?token={webhook_token}",
  "subscribe": ["MESSAGE", "CONNECTION", "QRCODE"]
}
```

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
| `SEND_MESSAGE` + outbound CW | Não subscrever `SEND_MESSAGE` no MVP |
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
| Mídia inbound falha | `download_media` — primário `downloadimage`, fallback `downloadmedia` ([decisions.md §25](./decisions.md)) |
