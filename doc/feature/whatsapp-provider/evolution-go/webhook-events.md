# Webhook events — Evolution Go → Chatwoot

Formato dos webhooks que a Evolution Go envia ao Chatwoot e como o **`EvolutionGoNormalizer`** deve transformá-los para `IncomingMessageService`.

**Código referência:** [events-system.md](https://github.com/evolution-foundation/evolution-go/blob/main/docs/wiki/recursos-avancados/events-system.md)

**Wire format:** Evolution Go sends PascalCase event names (`Message`, `SendMessage`, `LoggedOut`). The fork normalizes them via `Custom::Whatsapp::EvolutionGo::EventNames` to SCREAMING_SNAKE (`MESSAGE`, `SEND_MESSAGE`, `LOGGED_OUT`) before routing. Examples in this doc use the normalized form unless noted.

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

**Auth webhook fork:** validar token na URL (`?token=`) ou `Authorization: Bearer {webhook_token}` — ver [decisions.md §2](./decisions.md).

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

**Subscribe MVP (canonical fork list):**

```json
[
  "MESSAGE",
  "SEND_MESSAGE",
  "SEND_MESSAGE_UPDATE",
  "CONNECTION",
  "QRCODE",
  "READ_RECEIPT",
  "MESSAGE_DELETE",
  "MESSAGES_DELETE",
  "MESSAGES_EDITED",
  "MESSAGE_EDIT",
  "HISTORY_SYNC"
]
```

When `ignore_groups: false`, also include `GROUP`.

Managed by `Custom::Whatsapp::EvolutionGo::WebhookSubscribeSync` — sync via health UI **Sync webhook events**, `POST evolution_go_sync_webhook`, reconnect, or `rake evolution_go:sync_webhooks`. Auto-sync also runs when `ignore_from_me_echo` or `ignore_groups` change (`WEBHOOK_SUBSCRIBE_KEYS`).

**Legacy MVP (superseded):**

```json
["MESSAGE", "CONNECTION", "QRCODE"]
```

**Do not subscribe:** `ALL` (noisy). Group events when `ignore_groups: true`.

### `SEND_MESSAGE` / phone echo sync

`SEND_MESSAGE` is in the canonical subscribe list. **Delete/edit protocol payloads are always handled first** (even when echo is ignored):

| Setting | Behavior |
|---------|----------|
| Protocol revoke/edit on `SEND_MESSAGE` | Always → `MessageDeleteSyncService` / `MessageEditSyncService` (inclui `fromMe`) |
| `ignore_from_me_echo: true` | Echo de texto/mídia logado e dropado |
| `ignore_from_me_echo: false` | `PhoneOutgoingSyncService` cria mensagem **outgoing** com `content_attributes.phone_sent: true`; contato via `PeerContactInboxResolver` |

Same path for `MESSAGE` events with `fromMe: true` (delete/edit before echo filter).
### Event name aliases (after normalization)

| Normalized | Also accepted |
|------------|---------------|
| `LOGGED_OUT` | `LOGGEDOUT` |
| `QR_CODE` | `QRCODE` |
| `DELETE` | `MESSAGE_DELETE`, `MESSAGES_DELETE` |
| `RECEIPT` | `READ_RECEIPT` |
| `SEND_MESSAGE_UPDATE` | (edit alias) |

### Catálogo completo `subscribe` (connect)

Quando `subscribe` é omitido, o connect pode registrar todos os eventos (`eventString` na resposta):

```
MESSAGE, SEND_MESSAGE, READ_RECEIPT, PRESENCE, HISTORY_SYNC,
CHAT_PRESENCE, CALL, CONNECTION, LABEL, CONTACT, GROUP, NEWSLETTER, QRCODE
```

| Evento | Categoria | Fase fork | Ação |
|--------|-----------|-----------|------|
| `MESSAGE` | Mensagens | 1 | Normalizer inbound |
| `SEND_MESSAGE` | Mensagens | 1 | Echo sync when `ignore_from_me_echo: false` → `PhoneOutgoingSyncService` |
| `READ_RECEIPT` | Status | 2 | Status read |
| `CONNECTION` | Sessão | 1 | `connection_status` |
| `QRCODE` | Sessão | 1 | QR wizard |
| `PRESENCE` | Presença | — | Ignorar |
| `CHAT_PRESENCE` | Typing | — | Ignorar inbound (outbound typing via dashboard → `/message/presence`) |
| `HISTORY_SYNC` | Histórico | 4 | `HistorySyncProcessor` + `content_attributes.history_import` |
| `MESSAGE_DELETE`, `MESSAGES_DELETE` | Delete cliente | UX | `MessageDeleteSyncService` (job sempre consome revoke; soft-delete gated por `mark_inbound_deleted`) |
| `MESSAGES_EDITED`, `MESSAGE_EDIT`, `SEND_MESSAGE_UPDATE` | Edit cliente | UX | `MessageEditSyncService` — plaintext ✅; encrypted-only skip — ver § Edit abaixo |
| `CALL` | Chamadas | — | Projeto voz |
| `GROUP` | Grupos | 5 | Warm `GroupMetadataFetchJob` quando `ignore_groups: false`; inbound grupo via `MESSAGE` com `@g.us` |
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
| Bot (Meta AI, etc.) | `8670…@bot` | Dígitos antes de `@` (`phone_from_jid`); pushName costuma ser o nome do bot |
| LID | `xxx@lid` + `remoteJidAlt` | Usar `remoteJidAlt` se presente (**só 1:1**; nunca em `@g.us`) |
| Grupo | `120363...@g.us` | Filtrar se `ignore_groups: true`; senão `source_id` = JID grupo + `participant` no key. **`@g.us` nunca é resolvido via `remoteJidAlt`** (mesmo com `AddressingMode: lid`) |
| Status | `status@broadcast` | Ignorar |
| Echo | `fromMe: true` | Filtrar se `ignore_from_me_echo: true` (default); senão `PhoneOutgoingSyncService` |

### Texto — `conversation` vs `extendedTextMessage`

| Tipo inbound | Campo body | Notas |
|--------------|------------|-------|
| Texto simples | `message.conversation` | Exemplo oficial webhook |
| Texto formatado / link preview / **reply quote** | `message.extendedTextMessage.text` | Reply traz `contextInfo` |
| Legenda em mídia | `message.*Message.caption` | Fase 2 |
| Meta AI / bots rich | `message.richResponseMessage.submessages[].messageText` | `AIRichResponseMessage` (whatsmeow); `Info.Type` pode ser `text` mesmo assim |

**Reply / quote inbound:** `extendedTextMessage.contextInfo.stanzaID` (Evolution Go / whatsmeow — `ID` maiúsculo). Baileys usa `stanzaId`. O normalizer aceita ambos → `messages[].context.id` → `in_reply_to_external_id`. Sem o casing `stanzaID`, a mensagem chega no CW sem preview de resposta ([evolution-go#29](https://github.com/evolution-foundation/evolution-go/issues/29)).

Normalizer tenta, nesta ordem: `conversation` → `extendedTextMessage.text` → caption da mídia → interactive reply/template → **`richResponseMessage` submessages** → placeholder (`[AI message]` / `[Unsupported message type]`).

### Meta AI / `richResponseMessage`

Bots oficiais (ex.: Meta AI, chat `@bot`) enviam `AIRichResponseMessage` serializado como `richResponseMessage`, **não** `conversation`. Payload típico ~alguns KB; o Go loga `Type: text` via `Info.Type` (classificação grossa), o que **não** implica body em `conversation`.

| Campo | Uso no fork |
|-------|-------------|
| `richResponseMessage.submessages[].messageText` | Concatenados com `\n\n` → texto inbound |
| `richResponseMessage` sem texto (ex.: só imagem/grid) | Placeholder `[AI message]` |
| `botInvokeMessage` | Wrapper `FutureProofMessage` — unwrap em `EvolutionGoPayloadAdapter` |

Fixture: `spec/fixtures/evolution_go/message_inbound_rich_response.json`.

### Mídia (Fase 2)

`data.message` / `data.Message` pode conter:

- `imageMessage`, `documentMessage`, `audioMessage`, `videoMessage`, `stickerMessage`
- URL ou base64 conforme config MinIO/S3 do servidor Go

**Wrappers aninhados** — `EvolutionGoPayloadAdapter#unwrap_nested_message` desembrulha antes do normalizer:

| Wrapper | Conteúdo interno |
|---------|------------------|
| `documentWithCaptionMessage` | `message.documentMessage` (+ caption) — comum em PDF/doc com legenda e no echo de `POST /send/media` |
| `ephemeralMessage` | `message.*` |
| `viewOnceMessage` / `viewOnceMessageV2` / `viewOnceMessageV2Extension` | `message.*` (quando o Go ainda entrega o payload interno) |
| `botInvokeMessage` | `message.*` (Meta AI / bots — frequentemente envolve `richResponseMessage`) |

Sem unwrap, `documentWithCaptionMessage` vira `[Unsupported message type]` no Chatwoot (echo phone / n8n → Go → webhook). Sem parser de `richResponseMessage`, Meta AI também virava esse placeholder (corrigido jul/2026).

**Mídia indisponível (view once)** — o Go pode enviar `MESSAGE` **sem** `Message` / `message`, só com flags no envelope:

| Campo | Exemplo | Comportamento Chatwoot |
|-------|---------|------------------------|
| `IsUnavailable` / `isUnavailable` | `true` | Adapter marca `is_unavailable` no canonical |
| `UnavailableType` / `unavailableType` | `view_once` | Normalizer → `type: unsupported` + `evolution_go_unavailable_type` |
| `Info.Type` | `media` | Sem conteúdo recuperável (limitação WhatsApp / linked device) |

O inbound cria placeholder localizado (`conversations.messages.whatsapp.view_once_unavailable`) e `content_attributes.is_unsupported` + `unavailable_type`. A bubble `Unsupported.vue` usa `CONVERSATION.VIEW_ONCE_MEDIA_UNAVAILABLE` quando `unavailableType === 'view_once'`. Fixture: `spec/fixtures/evolution_go/message_view_once_unavailable.json`.

Isto é distinto dos wrappers `viewOnceMessage*` acima: lá o conteúdo ainda vem aninhado; aqui o WhatsApp **não** disponibiliza a mídia à API.

### Reações — `reactionMessage`

Não cria mensagem no Chatwoot. O job detecta `reactionMessage` **antes** do normalizer e chama `MessageReactionSyncService`.

```json
{
  "key": { "remoteJid": "5511...@s.whatsapp.net", "fromMe": false, "id": "REACTION_ID" },
  "message": {
    "reactionMessage": {
      "text": "👍",
      "key": { "id": "TARGET_MSG_ID", "remoteJid": "5511...@s.whatsapp.net", "fromMe": true }
    }
  }
}
```

| Campo | Uso |
|-------|-----|
| `reactionMessage.text` | Emoji; vazio / `"remove"` = remoção |
| `reactionMessage.key.id` | `source_id` da mensagem alvo no CW |
| Envelope `key` | Ator (`fromMe` / participant) |

Atualiza `content_attributes.reactions[]` na mensagem alvo + chip na bolha. Ator negócio = `user:self`. Alvo ausente → `inbound_reaction_skipped` (não inventa mensagem). Placeholder `[Reaction message]` **removido**. Bump `last_activity_at` sem unread.

---

## `CONNECTION` — status

Mapear para `provider_config.connection_status`:

| Estado Go | Valor fork |
|-----------|------------|
| Conectado | `open` |
| Desconectado | `close` |
| Conectando | `connecting` |

Emitir ActionCable `evolution_go:connection:{inbox_id}`.

> ⚠️ **Payload real pendente E2E** — template sintético até fixture `connection_event.json`:

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

> ⚠️ Template sintético — confirmar no E2E (`qrcode_event.json`):

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

**Casing status (`GET /instance/status`):** OpenAPI usa `Connected` / `LoggedIn` (PascalCase). `ApiClient#unwrap` deve aceitar também `connected` / `loggedIn` até E2E definir canônico.

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

> ⚠️ **Template alvo Chatwoot** — payload bruto Go a confirmar no E2E:

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

### Filtros inbound (configuráveis)

Implementados em `EvolutionGoNormalizer#filtered?` e no job prepend **antes** do normalizer:

| Condição | Comportamento | Config |
|----------|---------------|--------|
| `fromMe: true` | Ignorar ou echo sync | `ignore_from_me_echo` (default `true`) |
| `@g.us` | Ignorar ou conversa de grupo | `ignore_groups` (default `true`) |
| `status@broadcast` | Sempre ignorar | — |

```ruby
# EvolutionGoNormalizer#filtered?
def echo_filtered?(key)
  from_me?(key) && ignore_from_me_echo?
end

def group_filtered?(remote_jid)
  ignore_groups? && group_jid?(remote_jid)
end
```

O job prepend trata delete/edit protocol em `MESSAGE` / `SEND_MESSAGE` **antes** do filtro `ignore_from_me_echo` e do normalizer. Soft-delete/edit aplica-se também a mensagens `fromMe` (agente/celular). Echo de texto/mídia só roda quando `ignore_from_me_echo: false`.

---

## Edit — formatos de payload

`MessageEditPayloadExtractor` aceita três formas (ordem efetiva no job):

| Forma | Como chega | Resultado no fork |
|-------|------------|-------------------|
| Evento explícito | `MESSAGES_EDITED` / `MESSAGE_EDIT` / `SEND_MESSAGE_UPDATE` com `editedMessage` | Atualiza mensagem (`mark_inbound_edited`) |
| Protocol plaintext | `MESSAGE` / `SEND_MESSAGE` com `IsEdit` / `messageType: "edit"` / `protocolMessage.type` 14 ou `typeName: MESSAGE_EDIT` + `editedMessage` | Idem |
| Envelope criptografado | `IsEdit` / `Info.Edit: "1"` + `secretEncryptedMessage` **sem** plaintext | **Skip** (`encrypted_edit: true`) — log `skipped encrypted edit envelope`; **não** cria `[Unsupported message type]` |

### Sinais e IDs (contrato Go atual)

| Campo | Uso |
|-------|-----|
| `IsEdit` / `messageType: "edit"` | Envelope de edição |
| `Info.Edit` | Só `"1"` / `true` conta como edit — **não** qualquer non-zero (revoke usa `Edit: "7"`) |
| ID da mensagem original | `Message.protocolMessage.key.ID` (ou `secretEncryptedMessage.targetMessageKey.ID`) — **não** `Info.ID` do evento |
| Texto novo | `editedMessage.conversation` **ou** `editedMessage.extendedTextMessage.text` (eco da API costuma usar extended) |
| Stub incompleto | Sem `key.id` + (body ou encrypted) → extrator retorna `nil` (não engole o pipeline MESSAGE) |

Original ausente no CW → **skip** + `inbound_edit_skipped` (não inventa row `#{id}-edited`).

Envelope criptografado sem texto ainda ocorre em alguns builds Go ([#92](https://github.com/evolution-foundation/evolution-go/issues/92), [#62](https://github.com/evolution-foundation/evolution-go/issues/62)); plaintext protocol (`editedMessage`) é o path feliz e está wired.

UX no CW quando o edit aplica: texto bare + `content_attributes.edited` / `edited_at` / `edited_via_evolution_go_webhook` + badge “Edited”. Prefixo legado `"Edited message:\n\n"` é stripped na bubble se ainda existir em mensagens antigas.

Fixtures: `message_edit.json` (cliente plaintext), `message_edit_api_echo.json` (eco API + `extendedTextMessage`), `message_edit_secret_encrypted.json` (skip).

---

## Revoke / delete — formatos de payload

| Forma | Como chega | Resultado no fork |
|-------|------------|-------------------|
| Protocol revoke | `MESSAGE` / `SEND_MESSAGE` com `IsRevoke` / `messageType: "revoke"` / `type` 0 ou `typeName: REVOKE` | Soft-delete se `mark_inbound_deleted` |
| Evento explícito | `MESSAGE_DELETE` / `MESSAGES_DELETE` / `DELETE` | Idem |

ID a apagar: `Message.protocolMessage.key.ID` (não `Info.ID`).

O job **sempre extrai e consome** o envelope revoke (evita normalizar como texto/unsupported). O soft-delete em si fica gated em `MessageDeleteSyncService` / `mark_inbound_deleted`.

Outbound (`sync_delete_to_whatsapp`): `DeleteSyncService` → `POST /message/delete` `{ chat, messageId }`. Se a API falhar após soft-delete local, **reverte** `deleted` / `deleted_at` / `deleted_via_evolution_go_webhook` no CW.

Fixture: `message_revoke.json`.

---

## Job prepend — roteamento

`Custom::Webhooks::WhatsappEventsJobEvolutionGo` — detecção por `evolution_go_instance_name` (não `instance` / `instance_name`). Eventos normalizados via `EventNames.normalize` (PascalCase → SCREAMING_SNAKE).

```ruby
case params[:event].to_s.upcase
when 'MESSAGE'
  # delete/edit protocol → sync services; fromMe → echo ou drop; senão normalizer → InboundMessageProcessor
when 'SEND_MESSAGE'
  # delete/edit protocol sempre; echo texto/mídia só se ignore_from_me_echo: false
when 'MESSAGE_DELETE', 'MESSAGES_DELETE', 'DELETE'
  process_inbound_delete
when 'MESSAGES_EDITED', 'MESSAGE_EDIT', 'SEND_MESSAGE_UPDATE'
  process_inbound_edit
when 'READ_RECEIPT', 'RECEIPT'
  EvolutionGoReadReceiptNormalizer → InboundMessageProcessor
when 'CONNECTION', 'CONNECTED', 'DISCONNECTED', 'LOGGEDOUT', 'LOGGED_OUT', 'QRCODE', 'QR_CODE'
  ConnectionService#handle_event
when 'HISTORY_SYNC'
  Import::HistorySyncProcessor
when 'GROUP'
  GroupMetadataFetchJob (quando ignore_groups: false)
else
  log ignored
end
```

Controller: `EvolutionGoController` injeta `evolution_go_instance_name`, remove `instance` do payload, enfileira em `queue: :default`. Ver [decisions.md §27](./decisions.md) e [spec-design.md](./spec-design.md).
