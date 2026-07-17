# API Reference — Evolution Go (uso pelo provider Chatwoot)

Endpoints REST oficiais (OpenAPI jun/2026). Base URL: `{base_url}` do `provider_config`.

**Postman:** [Evolution GO collection](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go) · índice completo: [documentation-links.md](./documentation-links.md)

---

## Convenções

| Item | Valor |
|------|-------|
| Auth header | `apikey: {key}` |
| Content-Type | `application/json` |
| Instância no path | **Não** — identificada pelo token no header `apikey` |
| Resposta sucesso | `{ "message": "success", "data": { ... } }` |
| Resposta erro | `{ "success": false, "error": { "code", "message" }, "meta": { ... } }` |
| Send response ID | `data.Info.ID` (whatsmeow PascalCase) |

### Duas chaves API

| Chave | Uso | Operações |
|-------|-----|-----------|
| `GLOBAL_API_KEY` | Admin | `POST /instance/create`, `GET /instance/all`, `DELETE /instance/delete/{id}`, `DELETE /instance/proxy/{id}` |
| `instance_token` | Instância | connect, qr, status, pair, disconnect, logout, `/send/*`, `/message/*`, `/group/*`, `/user/*` |

---

## 1. Instance lifecycle

### Create

```
POST /instance/create
Header: apikey: {GLOBAL_API_KEY}
```

Doc: [create-a-new-instance](https://docs.evolutionfoundation.com.br/evolution-go/create-a-new-instance)

```json
{
  "name": "minha-instancia",
  "token": "uuid-opcional",
  "proxy": {
    "host": "proxy.example.com",
    "port": "8080",
    "username": "",
    "password": ""
  }
}
```

**Resposta:** `data.id`, `data.name`, `data.token`, `data.connected`, flags `ignoreGroups`, `rejectCall`, etc.

Persistir: `instance_token` ← `data.token`, `instance_id` ← `data.id`, `instance_name` ← `data.name`.

---

### Connect (+ webhook)

```
POST /instance/connect
Header: apikey: {instance_token}
```

Doc: [connect-to-instance](https://docs.evolutionfoundation.com.br/evolution-go/connect-to-instance)

```json
{
  "webhookUrl": "https://chatwoot.example.com/webhooks/evolution_go/minha-instancia?token=SECRET",
  "subscribe": ["MESSAGE", "SEND_MESSAGE", "SEND_MESSAGE_UPDATE", "CONNECTION", "QRCODE", "READ_RECEIPT", "MESSAGE_DELETE", "MESSAGES_DELETE", "MESSAGES_EDITED", "MESSAGE_EDIT", "HISTORY_SYNC"],
  "phone": "5511999999999",
  "immediate": false
}
```

| Campo | Descrição |
|-------|-----------|
| `webhookUrl` | URL única Chatwoot — substitui `/webhook/set` da Evolution API |
| `subscribe` | Array de eventos — ver [webhook-events.md](./webhook-events.md) |
| `phone` | Opcional — pairing code em vez de QR |

**Resposta:** `data.webhookUrl`, `data.eventString` (eventos ativos).

---

### QR code

```
GET /instance/qr
Header: apikey: {instance_token}
```

Doc: [get-instance-qr-code](https://docs.evolutionfoundation.com.br/evolution-go/get-instance-qr-code)

**Resposta:** `data.Qrcode` (base64 PNG), `data.Code` (string pairing).

---

### Pairing code

```
POST /instance/pair
Header: apikey: {instance_token}
```

Doc: [request-pairing-code](https://docs.evolutionfoundation.com.br/evolution-go/request-pairing-code)

```json
{ "phone": "5511999999999", "subscribe": ["MESSAGE", "SEND_MESSAGE", "SEND_MESSAGE_UPDATE", "CONNECTION", "QRCODE", "READ_RECEIPT", "MESSAGE_DELETE", "MESSAGES_DELETE", "MESSAGES_EDITED", "MESSAGE_EDIT", "HISTORY_SYNC"] }
```

**Resposta:** `data.PairingCode`

---

### Status

```
GET /instance/status
Header: apikey: {instance_token}
```

Doc: [get-instance-status](https://docs.evolutionfoundation.com.br/evolution-go/get-instance-status)

**Resposta:**

```json
{
  "message": "success",
  "data": {
    "Connected": true,
    "LoggedIn": true,
    "Name": "João Silva"
  }
}
```

### Extração de `phone_number` (Chatwoot)

O exemplo oficial **não** inclui JID. Na implementação, tentar nesta ordem (confirmar no E2E — ver [validation-checklist.md](./validation-checklist.md)):

| Prioridade | Campo | Transformação |
|------------|-------|---------------|
| 1 | `data.jid` ou `data.myJid` | Dígitos antes de `@` |
| 2 | `data.JID` / `data.MyJid` | PascalCase — aceitar no `ApiClient#unwrap` |
| 3 | Webhook `CONNECTION` | JID no payload de conexão |
| 4 | Primeiro `MESSAGE` inbound | `key.remoteJid` / `remoteJidAlt` |

**Não usar** `Name` como `phone_number` — é display name WhatsApp.

### Casing — regra do adapter

| Fonte | Campos |
|-------|--------|
| OpenAPI oficial | `Connected`, `LoggedIn`, `Name` (PascalCase) |
| Respostas alternativas | `connected`, `loggedIn` (camelCase) |

`ConnectionService` e wizard polling devem tratar **ambos** até fixture real definir canônico:

```ruby
def connected?(data)
  data['Connected'] || data['connected']
end

def logged_in?(data)
  data['LoggedIn'] || data['loggedIn']
end
```

---

### Advanced settings (Fase 2)

Confirmado na collection Postman **[Evolution GO](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go)** (abr/2026). **Não** está no índice `llms.txt` — validar no Swagger runtime.

| Operação | Método | Path | Auth | Fase |
|----------|--------|------|------|------|
| Get settings | `GET` | `/instance/{instanceId}/advanced-settings` | `instance_token` | 2 |
| Update settings | `PUT` | `/instance/{instanceId}/advanced-settings` | `instance_token` | 2 |

Body (OpenAPI `AdvancedSettings` — confirmed on runtime Swagger jul/2026):

```json
{
  "ignoreGroups": true,
  "rejectCall": false,
  "msgRejectCall": "",
  "readMessages": false,
  "ignoreStatus": true,
  "alwaysOnline": false
}
```

Older Postman samples used `rejectCalls` / `rejectCallMessage` / `readStatus` — **do not send those**; `SettingsSync` writes the OpenAPI keys above.

Mapeamento fork ↔ OpenAPI — ver [provider-config-mapping.md § Grupo 2](./provider-config-mapping.md) e [decisions.md §26](./decisions.md).

**`POST /instance/reconnect`:** existe no Postman — **não usar** no fork (ADR §24); usar sempre `connect` com webhook.

### Instance admin (fora do MVP inbox)

| Operação | Método | Path | Auth |
|----------|--------|------|------|
| Info | `GET` | `/instance/info/{instanceId}` | global |
| Logs | `GET` | `/instance/logs/{instanceId}` | global |
| Reconnect | `POST` | `/instance/reconnect` | instance token |
| Force reconnect | `POST` | `/instance/forcereconnect/{instanceId}` | global |

> **Reconnect fork:** ADR §23 usa `POST /instance/connect` com webhook reenviado. `POST /instance/reconnect` existe no Postman — validar se equivale ou é atalho sem webhook.

---

### List all

```
GET /instance/all
Header: apikey: {GLOBAL_API_KEY}
```

Doc: [get-all-instances](https://docs.evolutionfoundation.com.br/evolution-go/get-all-instances)

---

### Disconnect / Logout / Delete

| Ação | Método | Path | Auth | Doc |
|------|--------|------|------|-----|
| Disconnect | `POST` | `/instance/disconnect` | instance token | [disconnect](https://docs.evolutionfoundation.com.br/evolution-go/disconnect-from-instance) |
| Logout | `DELETE` | `/instance/logout` | instance token | [logout](https://docs.evolutionfoundation.com.br/evolution-go/logout-from-instance) |
| Delete | `DELETE` | `/instance/delete/{instanceId}` | global key | [delete](https://docs.evolutionfoundation.com.br/evolution-go/delete-instance) |
| Delete proxy | `DELETE` | `/instance/proxy/{instanceId}` | global key | [delete-proxy](https://docs.evolutionfoundation.com.br/evolution-go/delete-proxy) |

---

## 2. Send Message (`/send/*`)

Todos usam `Header: apikey: {instance_token}`.

### Text (MVP Fase 1)

```
POST /send/text
```

Doc: [send-a-text-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-text-message)

```json
{
  "number": "5511999999999",
  "text": "Olá!",
  "delay": 0,
  "quoted": { "messageId": "3EB0...", "participant": "5511...@s.whatsapp.net" }
}
```

**Resposta — `process_response`:**

```ruby
response.dig('data', 'Info', 'ID')  # => source_id
```

### Media (Fase 2)

```
POST /send/media
```

Doc: [send-a-media-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-media-message)

```json
{
  "number": "5511999999999",
  "type": "document",
  "url": "https://example.com/file.pdf",
  "caption": "Legenda",
  "filename": "file.pdf"
}
```

- Campo canônico: **`filename`** (OpenAPI Go). `url` aceita HTTP(S) ou base64 string.
- Resposta / webhook echo com caption costuma vir como `documentWithCaptionMessage` → unwrap em `EvolutionGoPayloadAdapter` ([webhook-events.md § Mídia](./webhook-events.md)).

### Outros send (Fase 3)

| Path | Doc |
|------|-----|
| `POST /send/location` | [send-a-location-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-location-message) |
| `POST /send/contact` | [send-a-contact-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-contact-message) |
| `POST /send/link` | [send-a-link-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-link-message) |
| `POST /send/sticker` | [send-a-sticker-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-sticker-message) |
| `POST /send/poll` | [send-a-poll-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-poll-message) |

**QuotedMessage schema (todos sends):** `{ messageId, participant }` — diferente do Baileys `quoted.key`.

---

## 3. Message operations (`/message/*`)

### Mark read (Fase 2)

```
POST /message/markread
```

Doc: [mark-a-message-as-read](https://docs.evolutionfoundation.com.br/evolution-go/mark-a-message-as-read)

```json
{ "number": "5511999999999", "id": ["3EB0XXXX"] }
```

### Message status (Fase 2)

```
POST /message/status
```

Doc: [get-message-status](https://docs.evolutionfoundation.com.br/evolution-go/get-message-status)

```json
{ "id": "3EB0XXXX" }
```

### Chat presence / typing (implementado)

```
POST /message/presence
```

Doc: [set-chat-presence](https://docs.evolutionfoundation.com.br/evolution-go/set-chat-presence)

```json
{ "number": "5511999999999", "state": "composing", "isAudio": false }
```

**Fork wiring:** dashboard `conversation.typing_on` / `typing_off` → `Custom::Whatsapp::EvolutionGo::TypingListener` (async dispatcher) → `PresenceSyncJob` → `ApiClient#set_presence`. Private notes (`is_private: true`) are skipped. Group chats use `contact_inbox.source_id` (`@g.us`) when phone is blank.

### React / Edit / Delete

| Path | Fase fork | Componente |
|------|-----------|------------|
| `POST /message/react` | ✅ | `ApiClient#react` + `ReactSyncService` + context menu |
| `POST /message/edit` | UX ⚠️ | UI Edit → `evolution_go_edit` → `EditSyncService` (opt-in `sync_edit_to_whatsapp`; body `{ chat, messageId, message }`) — ADR §35 |
| `POST /message/delete` | UX | `DeleteSyncService` (opt-in `sync_delete_to_whatsapp`) |
| `POST /message/downloadmedia` | 2 | `MediaDownloadJob` — único endpoint de download no swagger atual |

### History sync (Fase 4)

```
POST /chat/history-sync
```

Body (swagger): `{ "count": 100, "messageInfo": { "chat": "5511...@s.whatsapp.net" } }` — dispara eventos `HISTORY_SYNC` com batch de mensagens.

`count` is **message quantity**, not days. `MessagesImporter` reads `provider_config.days_limit_import_messages` (legacy key name) and sends it as `count` (default **100**, clamp 1–1000).

`ApiClient#history_sync` uses `{ chat: "<jid string>" }` inside `messageInfo` (string form accepted by Go; OpenAPI also documents `types.JID` object — validate on E2E).

Componentes: `ApiClient#history_sync`, `Import::MessagesImporter`, `HistorySyncProcessor`.

Fixture sintética: `spec/fixtures/evolution_go/history_sync.json` — **validar payload real no E2E**.

---

## 4. Chat (fora do MVP)

| Doc | Operação |
|-----|----------|
| [archive-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/archive-a-chat) | Arquivar |
| [mute-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/mute-a-chat) | Silenciar |
| [pin-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/pin-a-chat) | Fixar |
| [unpin-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/unpin-a-chat) | Desfixar |
| [history-sync](https://docs.evolutionfoundation.com.br/evolution-go/) (Postman) | `POST /chat/history-sync` — import histórico |

---

## 5. API Chatwoot (inbox admin)

| Método | Path | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_connection` | Status + QR sob demanda (`include_qr=true` no query) |
| `POST` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_reconnect` | Reconnect + re-subscribe webhook |
| `POST` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_logout` | Logout da sessão WhatsApp |
| `POST` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_pair` | Pairing code (alternativa ao QR) |
| `POST` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_sync_webhook` | Re-envia `webhookUrl` + subscribe |
| `GET` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_diagnostics` | Webhook URL, import status, `mutation_stats` |
| `POST` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_test_webhook` | Ping webhook — atualiza `last_webhook_at` sem criar contato |
| `POST` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_import` | Força import contatos (+ messages se habilitado) |
| `POST` | `/api/v1/accounts/:account_id/inboxes/:id/evolution_go_refresh_contacts` | Refresh perfis/fotos de todos os contatos do inbox |
| `POST` | `/api/v1/accounts/:account_id/inboxes/evolution_go_server_check` | Valida `base_url` + SSRF guard (wizard step 1) |
| `POST` | `/api/v1/accounts/:account_id/conversations/:id/messages/:id/evolution_go_react` | Envia reação (`{ reaction }`) via `ReactSyncService` |

Webhook inbound: `POST /webhooks/evolution_go/:instance_name?token={webhook_token}` — auth alternativa: `Authorization: Bearer {webhook_token}`

---

## 6. Group

| Método | Path | Uso fork |
|--------|------|----------|
| `POST` | `/group/info` | `ApiClient#group_info` — nome do grupo (`subject`/`Name`) quando `ignore_groups: false` |

Demais rotas de grupo: ver [documentation-links.md § Group](./documentation-links.md#group). Outbound para grupo usa JID `@g.us` no `number` do send.

---

## 7. User / Label

Usados pelo import e enriquecimento de contatos:

| Método | Path | Uso fork |
|--------|------|----------|
| `GET` | `/user/contacts` | `ContactsImporter` |
| `POST` | `/user/check` | `ContactEnrichmentService` — body `{ "number": ["5511..."] }` (array) |
| `POST` | `/user/avatar` | Avatar no enrichment (`preview` opcional) |
| `POST` | `/user/info` | Perfil no enrichment — body `CheckUserStruct` |

> `POST /user/profilePicture` no Swagger é **set** da foto do perfil da instância, não get de avatar de contato.

Labels: fora do escopo inbox Chatwoot MVP — ver [documentation-links.md](./documentation-links.md).

---

## 8. O que NÃO existe (vs Evolution API Node)

| Evolution API | Evolution Go |
|---------------|--------------|
| `/:instanceName` no path | Token no header |
| `POST /webhook/set/:instance` | `webhookUrl` no connect |
| `POST /message/sendText/:instance` | `POST /send/text` |
| `GET /instance/connect/:instance` | `POST /instance/connect` + `GET /instance/qr` |
| `GET /instance/connectionState/:instance` | `GET /instance/status` |
| Resposta `key.id` | Resposta `data.Info.ID` |
| `POST /chatwoot/set` | ❌ |

---

## Cliente HTTP sugerido

```ruby
# custom/app/services/custom/whatsapp/evolution_go/api_client.rb
#
# def send_text(number:, text:, quoted: nil)
#   post('/send/text', { number:, text:, quoted: }.compact, headers: instance_headers)
# end
#
# def extract_message_id(response)
#   parsed = response.parsed_response
#   parsed.dig('data', 'Info', 'ID') || parsed.dig('data', 'messageId')
# end
```

Ver [spec-design.md](./spec-design.md).
