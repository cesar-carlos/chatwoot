# Webhook events — Evolution Go → Chatwoot

Formato dos webhooks que a Evolution Go envia ao Chatwoot e como o **`EvolutionGoNormalizer`** deve transformá-los para `IncomingMessageService`.

**Código referência:** [events-system.md](https://github.com/evolution-foundation/evolution-go/blob/main/docs/wiki/recursos-avancados/events-system.md)

---

## Envelope padrão

Evolution Go POST na `webhookUrl` configurada em `POST /instance/connect`:

```json
{
  "event": "MESSAGE",
  "instance": "minha-instancia",
  "data": {
    "key": {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "fromMe": false,
      "id": "3EB0C5A277F7F9B6C599"
    },
    "message": {
      "conversation": "Olá!"
    },
    "messageTimestamp": "1699999999",
    "pushName": "João Silva"
  }
}
```

| Campo | Uso no Chatwoot |
|-------|-----------------|
| `event` | Roteamento no prepend `WhatsappEventsJob` |
| `instance` | Validar `provider_config.instance_name` |
| `data` | Payload a normalizar |

### Diferenças vs Evolution API (Node)

| Campo Evolution API | Evolution Go |
|---------------------|--------------|
| `apikey` no body | **Ausente** — auth via URL/token query ou header custom |
| `destination` | Ausente |
| `date_time` | Ausente |
| `sender` | Ausente — usar `data.key.remoteJid` ou `myJid` do status |
| `event: MESSAGES_UPSERT` | `event: MESSAGE` |

**Auth webhook fork:** validar token na URL (`?token=`) ou header configurado — ver [decisions.md §2](./decisions.md). Não depender de `apikey` no envelope.

### Retry Evolution Go

- 5 tentativas, intervalo 30s
- Chatwoot deve responder **HTTP 200** rápido e processar async
- Dedup: Redis lock por `source_id` em `IncomingMessageBaseService`

---

## Eventos necessários (MVP)

Configurar em `subscribe` no `POST /instance/connect`:

| Evento Go | Equivalente Evolution API | Fase | Ação Chatwoot |
|-----------|---------------------------|------|---------------|
| `MESSAGE` | `MESSAGES_UPSERT` | 1 | Normalizer → `IncomingMessageService` |
| `READ_RECEIPT` | `MESSAGES_UPDATE` (parcial) | 2 | Status read |
| `CONNECTION` | `CONNECTION_UPDATE` | 1 | `connection_status` no channel |
| `QRCODE` | `QRCODE_UPDATED` | 1 | QR no wizard via ActionCable |

**Subscribe MVP:**

```json
["MESSAGE", "CONNECTION", "QRCODE"]
```

Fase 2: adicionar `READ_RECEIPT`.

**Não subscrever no MVP:** `SEND_MESSAGE` (echo outbound), `ALL`, eventos de grupo se `ignore_groups: true`.

### Catálogo completo `subscribe` (connect)

Quando `subscribe` é omitido, o connect pode registrar todos os eventos (`eventString` na resposta):

```
MESSAGE, SEND_MESSAGE, READ_RECEIPT, PRESENCE, HISTORY_SYNC,
CHAT_PRESENCE, CALL, CONNECTION, LABEL, CONTACT, GROUP, NEWSLETTER, QRCODE
```

| Evento | Categoria | Fase fork | Ação |
|--------|-----------|-----------|------|
| `MESSAGE` | Mensagens | 1 | Normalizer inbound |
| `SEND_MESSAGE` | Mensagens | — | **Ignorar** (echo) |
| `READ_RECEIPT` | Status | 2 | Status read |
| `CONNECTION` | Sessão | 1 | `connection_status` |
| `QRCODE` | Sessão | 1 | QR wizard |
| `PRESENCE` | Presença | — | Ignorar |
| `CHAT_PRESENCE` | Typing | 3 | Opcional → `message/presence` |
| `HISTORY_SYNC` | Histórico | 4 | Import |
| `CALL` | Chamadas | — | Projeto voz |
| `GROUP` | Grupos | — | Ignorar MVP |
| `CONTACT` | Contatos | — | Ignorar |
| `LABEL` | Labels | — | Ignorar |
| `NEWSLETTER` | Newsletter | — | Ignorar |

Doc connect: [connect-to-instance](https://docs.evolutionfoundation.com.br/evolution-go/connect-to-instance)

Lista completa: wiki `events-system.md` § Tipos de Eventos.

---

## `MESSAGE` — estrutura `data`

`data` segue formato whatsmeow (similar ao messageRaw Baileys):

```json
{
  "key": {
    "remoteJid": "5511999999999@s.whatsapp.net",
    "remoteJidAlt": "5511999999999@s.whatsapp.net",
    "fromMe": false,
    "id": "3EB0XXXX",
    "addressingMode": "pn"
  },
  "pushName": "João",
  "message": {
    "conversation": "Olá!"
  },
  "messageTimestamp": "1718880000"
}
```

### Variações importantes

| Caso | `remoteJid` | Phone para Chatwoot |
|------|-------------|---------------------|
| Contato normal | `5511...@s.whatsapp.net` | Dígitos antes de `@` |
| LID | `xxx@lid` + `remoteJidAlt` | Usar `remoteJidAlt` se presente |
| Grupo | `120363...@g.us` | Ignorar se `ignore_groups: true` |
| Status | `status@broadcast` | Ignorar |
| Echo | `fromMe: true` | Ignorar (hardcoded F1) |

### Texto — `conversation` vs `extendedTextMessage`

| Tipo inbound | Campo body | Notas |
|--------------|------------|-------|
| Texto simples | `message.conversation` | Exemplo oficial webhook |
| Texto formatado / link preview | `message.extendedTextMessage.text` | Comum em respostas outbound echo |
| Legenda em mídia | `message.*Message.caption` | Fase 2 |

Normalizer deve tentar, nesta ordem: `conversation` → `extendedTextMessage.text` → caption da mídia.

### Mídia (Fase 2)

`data.message` pode conter:

- `imageMessage`, `documentMessage`, `audioMessage`, `videoMessage`
- URL ou base64 conforme config MinIO/S3 do servidor Go

---

## `CONNECTION` — status

Mapear para `provider_config.connection_status`:

| Estado Go | Valor fork |
|-----------|------------|
| Conectado | `open` |
| Desconectado | `close` |
| Conectando | `connecting` |

Emitir ActionCable `evolution_go:connection:{inbox_id}`.

> ⚠️ **Payload real pendente spike** — template sintético até fixture `connection_event.json`:

```json
{
  "event": "CONNECTION",
  "instance": "minha-instancia",
  "data": {
    "state": "open"
  }
}
```

`ConnectionService` deve aceitar variantes: `data.state`, `data.Connected`, string livre.

---

## `QRCODE` — pairing

Payload contém QR base64 — broadcast para wizard.

> ⚠️ Template sintético — confirmar no spike (`qrcode_event.json`):

```json
{
  "event": "QRCODE",
  "instance": "minha-instancia",
  "data": {
    "qrcode": "data:image/png;base64,..."
  }
}
```

Fallback polling: `GET /instance/qr` a cada 3s até status conectado.

**Casing status (`GET /instance/status`):** OpenAPI usa `Connected` / `LoggedIn` (PascalCase). `ApiClient#unwrap` deve aceitar também `connected` / `loggedIn` até spike definir canônico.

---

## `READ_RECEIPT` — status (Fase 2)

Mapear para flat `statuses[]`:

```json
{
  "statuses": [{
    "id": "3EB0XXXX",
    "status": "read",
    "recipient_id": "5511999999999"
  }]
}
```

> ⚠️ **Template alvo Chatwoot** — payload bruto Go a confirmar no spike:

```json
{
  "event": "READ_RECEIPT",
  "instance": "minha-instancia",
  "data": {
    "key": { "id": "3EB0XXXX", "remoteJid": "5511999999999@s.whatsapp.net" },
    "timestamp": "1718880000"
  }
}
```

Salvar fixture real em `spec/fixtures/evolution_go/read_receipt.json` — pode diferir de Meta/360dialog.

---

## Normalizer — payload canônico Chatwoot

Target para `Whatsapp::IncomingMessageService` (formato 360dialog-like):

```json
{
  "contacts": [{
    "profile": { "name": "João" },
    "wa_id": "5511999999999"
  }],
  "messages": [{
    "from": "5511999999999",
    "id": "3EB0XXXX",
    "timestamp": "1718880000",
    "type": "text",
    "text": { "body": "Olá!" }
  }]
}
```

### Mapeamento `MESSAGE` → flat

| Origem (`data`) | Destino (flat) |
|-----------------|----------------|
| `key.id` | `messages[].id` |
| `key.remoteJid` (normalizado) | `messages[].from`, `contacts[].wa_id` |
| `pushName` | `contacts[].profile.name` |
| `message.conversation` | `messages[].text.body` |
| `message.extendedTextMessage.text` | `messages[].text.body` |
| `messageTimestamp` | `messages[].timestamp` |
| `message.imageMessage` etc. | `messages[].type` + attachment |

### Filtros hardcoded (Fase 1)

```ruby
# EvolutionGoNormalizer — antes de normalizar
return nil if data.dig('key', 'fromMe') == true
return nil if remote_jid&.end_with?('@g.us')
return nil if remote_jid == 'status@broadcast'
```

---

## Job prepend — roteamento

```ruby
case params['event']
when 'MESSAGE'
  normalized = EvolutionGoNormalizer.new(channel, params).perform
  super(normalized.merge(phone_number: channel.phone_number)) if normalized
when 'READ_RECEIPT'
  # Fase 2 — statuses
when 'CONNECTION', 'QRCODE'
  ConnectionService.new(channel).handle_event(params)
end
```

Ver [decisions.md §12](./decisions.md).
