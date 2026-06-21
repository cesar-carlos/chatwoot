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
    "address": "proxy.example.com",
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
  "subscribe": ["MESSAGE", "CONNECTION", "QRCODE", "READ_RECEIPT"],
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
{ "phone": "5511999999999", "subscribe": ["MESSAGE", "CONNECTION", "QRCODE"] }
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

O exemplo oficial **não** inclui JID. Na implementação, tentar nesta ordem (confirmar no spike — ver [validation-checklist.md](./validation-checklist.md)):

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

> ⚠️ **Path não confirmado no OpenAPI indexado** — validar no Swagger runtime ou Postman (pasta Instance) antes de implementar `ConnectionService#sync_settings`.

| Operação | Path planejado | Auth | Fase |
|----------|----------------|------|------|
| Update settings | `POST /instance/{instanceId}/advanced-settings` | `instance_token` | 2 |

Body esperado (camelCase — confirmar no spike):

```json
{
  "ignoreGroups": true,
  "rejectCall": false,
  "msgRejectCall": "",
  "alwaysOnline": false,
  "readMessages": false,
  "ignoreStatus": true
}
```

Mapeamento fork: [provider-config-mapping.md § Grupo 2](./provider-config-mapping.md).

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

### Chat presence / typing (Fase 3)

```
POST /message/presence
```

Doc: [set-chat-presence](https://docs.evolutionfoundation.com.br/evolution-go/set-chat-presence)

```json
{ "number": "5511999999999", "state": "composing", "isAudio": false }
```

### React / Edit / Delete (Fase 3)

| Path | Doc |
|------|-----|
| `POST /message/react` | [react-a-message](https://docs.evolutionfoundation.com.br/evolution-go/react-a-message) |
| `POST /message/edit` | [edit-a-message](https://docs.evolutionfoundation.com.br/evolution-go/edit-a-message) |
| `POST /message/delete` | [delete-a-message-for-everyone](https://docs.evolutionfoundation.com.br/evolution-go/delete-a-message-for-everyone) |
| `POST /message/downloadimage` | [download-an-image](https://docs.evolutionfoundation.com.br/evolution-go/download-an-image) |

---

## 4. Chat (fora do MVP)

| Doc | Operação |
|-----|----------|
| [archive-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/archive-a-chat) | Arquivar |
| [mute-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/mute-a-chat) | Silenciar |
| [pin-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/pin-a-chat) | Fixar |
| [unpin-a-chat](https://docs.evolutionfoundation.com.br/evolution-go/unpin-a-chat) | Desfixar |

---

## 5. Group (fora do MVP 1:1)

Ver [documentation-links.md § Group](./documentation-links.md#group).

---

## 6. User / Label

Ver [documentation-links.md](./documentation-links.md) — fora do escopo inbox Chatwoot MVP.

---

## 7. O que NÃO existe (vs Evolution API Node)

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
