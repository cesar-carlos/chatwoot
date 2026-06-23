# API Reference — Z-API (uso pelo provider Chatwoot)

Endpoints REST usados pelo provider `zapi`. Base URL padrão: `https://api.z-api.io`.

**Postman:** [Z-API Collection](https://go.postman.co/collection/1696280-cea57506-b9de-4e61-b4d5-227743bd8151) · índice: [documentation-links.md](./documentation-links.md) · doc oficial: https://developer.z-api.io/llms.txt

---

## Convenções

| Item | Valor |
|------|-------|
| Path pattern | `/instances/{instance_id}/token/{instance_token}/{action}` |
| Header obrigatório | `Client-Token: {client_token}` (quando ativado na conta) |
| Content-Type | `application/json` |
| Telefone | DDI + DDD + número, só dígitos — ex. `5511999999999` |
| Webhooks | Somente **HTTPS** |
| Mídia inbound | URLs temporárias (~30 dias) — [file-expiration](https://developer.z-api.io/tips/file-expiration.md) |

### Identificadores de mensagem

| Campo | Uso |
|-------|-----|
| `messageId` | ID WhatsApp — **usar como `source_id`** no Chatwoot |
| `zaapId` | ID interno Z-API / fila |
| `id` | Alias de `messageId` (compatibilidade Zapier) |

---

## 1. Instance — conexão

### Status

```
GET /instances/{instance_id}/token/{instance_token}/status
Header: Client-Token: {client_token}
```

Doc: [status](https://developer.z-api.io/instance/status.md)

**Resposta 200:**

```json
{
  "connected": true,
  "error": "You are already connected",
  "smartphoneConnected": true
}
```

| Campo | Mapeamento fork |
|-------|-----------------|
| `connected: true` | `connection_status: connected` |
| `connected: false` | `connecting` ou `disconnected` conforme `error` |

---

### QR Code (bytes)

```
GET /instances/{instance_id}/token/{instance_token}/qr-code
```

Doc: [qr-code](https://developer.z-api.io/instance/qr-code.md)

Retorna bytes do QR para renderizar em componente QRCode.

---

### QR Code (imagem base64)

```
GET /instances/{instance_id}/token/{instance_token}/qr-code/image
```

Doc: [qr-code-image](https://developer.z-api.io/instance/qr-code-image.md)

**Uso wizard:** `<img src="data:image/png;base64,...">` após unwrap da resposta.

---

### Pairing por telefone

```
GET /instances/{instance_id}/token/{instance_token}/phone-code/{PHONE_NUMBER}
```

Doc: [phone-code](https://developer.z-api.io/instance/phone-code.md)

Alternativa ao QR — exibir código no wizard (Fase 2).

---

### Dados da instância

```
GET /instances/{instance_id}/token/{instance_token}/me
```

Doc: [me](https://developer.z-api.io/instance/me.md)

**Resposta:** `id`, `token`, `name`, `connected`, `due`, `paymentStatus`.

Usar após conexão para sincronizar `phone_number` via `connectedPhone` do webhook ou campo equivalente.

---

### Desconectar

```
GET /instances/{instance_id}/token/{instance_token}/disconnect
```

Doc: [disconnect](https://developer.z-api.io/instance/disconnect.md)

> Método `GET` (não DELETE). Atualiza `connection_status` local após sucesso.

---

### Reiniciar

```
GET /instances/{instance_id}/token/{instance_token}/restart
```

Doc: [restart](https://developer.z-api.io/instance/restart.md)

Operação admin — Fase 2 troubleshooting.

---

## 2. Messages — envio

### Texto

```
POST /instances/{instance_id}/token/{instance_token}/send-text
```

Doc: [send-text](https://developer.z-api.io/message/send-text.md)

```json
{
  "phone": "5511999999999",
  "message": "Welcome to *Z-API*",
  "delayMessage": 15,
  "delayTyping": 5,
  "editMessageId": ""
}
```

**Resposta 200:**

```json
{
  "zaapId": "3999984263738042930CD6ECDE9VDWSA",
  "messageId": "D241XXXX732339502B68",
  "id": "D241XXXX732339502B68"
}
```

**Chatwoot:** `process_response` → `source_id = messageId`.

---

### Imagem (Fase 2)

```
POST .../send-image
```

```json
{
  "phone": "5511999999999",
  "image": "https://example.com/photo.jpg",
  "caption": "opcional"
}
```

Doc: [send-message-image](https://developer.z-api.io/message/send-message-image.md)

---

### Áudio (Fase 2)

```
POST .../send-audio
```

```json
{
  "phone": "5511999999999",
  "audio": "https://example.com/audio.ogg"
}
```

Doc: [send-message-audio](https://developer.z-api.io/message/send-message-audio.md)

---

### Vídeo / documento (Fase 2)

```
POST .../send-video
POST .../send-document/{extension}
```

Docs: [video](https://developer.z-api.io/message/send-message-video.md) · [document](https://developer.z-api.io/message/send-message-document.md)

---

### Marcar como lida (Fase 2)

```
POST .../read-message
```

```json
{
  "phone": "5511999999999",
  "messageId": "D241XXXX732339502B68"
}
```

Doc: [read-message](https://developer.z-api.io/message/read-message.md)

---

## 3. Webhooks — configuração

Cada endpoint: `PUT` + `{ "value": "https://..." }`.

| Callback | Path REST | Doc |
|----------|-----------|-----|
| Receive | `/update-webhook-received` | [on-message-received](https://developer.z-api.io/webhooks/on-message-received.md) |
| Delivery | `/update-webhook-delivery` | [on-message-send](https://developer.z-api.io/webhooks/on-message-send.md) |
| Message status | `/update-webhook-message-status` | [on-whatsapp-message-status-changes](https://developer.z-api.io/webhooks/on-whatsapp-message-status-changes.md) |
| Disconnected | `/update-webhook-disconnected` | [on-whatsapp-disconnected](https://developer.z-api.io/webhooks/on-whatsapp-disconnected.md) |
| Connected | `/update-webhook-connected` | [on-webhook-connected](https://developer.z-api.io/webhooks/on-webhook-connected.md) |
| Chat presence | `/update-webhook-chat-presence` | [on-chat-presence](https://developer.z-api.io/webhooks/on-chat-presence.md) |
| Notify sent by me | `/update-webhook-received-delivery` | [update-notify-sent-by-me](https://developer.z-api.io/webhooks/update-notify-sent-by-me.md) |

### Atualizar todos de uma vez (recomendado fork)

```
PUT /instances/{instance_id}/token/{instance_token}/update-every-webhooks
Header: Client-Token: {client_token}
```

Doc: [update-every-webhooks](https://developer.z-api.io/webhooks/update-every-webhooks.md)

```json
{
  "value": "https://chatwoot.example.com/webhooks/zapi/INSTANCE_ID?token=TOKEN",
  "notifySentByMe": false
}
```

> Confirmado na doc oficial. **Ausente** na collection Postman fork (jun/2026) — usar doc ou E2E. Fallback: 4× `PUT` individuais abaixo.

**URL Chatwoot registrada:**

```
https://{FRONTEND_URL}/webhooks/zapi/{instance_id}?token={webhook_token}
```

---

## 4. Contacts (Fase 2)

```
GET /instances/{id}/token/{token}/contacts?page=1&pageSize=20
GET /instances/{id}/token/{token}/phone-exists/{phone}
```

Docs: [get-contacts](https://developer.z-api.io/contacts/get-contacts.md) · [get-iswhatsapp](https://developer.z-api.io/contacts/get-iswhatsapp.md)

---

## 5. Partners — provisionamento (Fase 2)

```
POST /instances/integrator/on-demand
Authorization: Bearer {partner_auth_token}
```

Doc: [create-instance](https://developer.z-api.io/partner/create-instance.md)

```json
{
  "name": "Instancia Z-API",
  "sessionName": "Chatwoot inbox",
  "deliveryCallbackUrl": "https://...",
  "receivedCallbackUrl": "https://...",
  "disconnectedCallbackUrl": "https://...",
  "connectedCallbackUrl": "https://...",
  "messageStatusCallbackUrl": "https://...",
  "isDevice": false,
  "businessDevice": true
}
```

Retorna credenciais da instância — persistir em `provider_config`.

---

## 6. Message queue (debug)

```
POST .../queue
```

Doc: [post-queue](https://developer.z-api.io/queue/post-queue.md)

Monitorar fila interna — não usado no fluxo Chatwoot MVP.

---

## Mapeamento rápido Fase 1

| Operação Chatwoot | Endpoint Z-API |
|-------------------|----------------|
| Wizard — status | `GET .../status` |
| Wizard — QR | `GET .../qr-code/image` |
| Setup — webhooks | `PUT .../update-every-webhooks` ou 4× PUT |
| Enviar texto | `POST .../send-text` |
| Inbound | webhook `ReceivedCallback` |
| Status outbound | webhook `MessageStatusCallback` |
| Delivery | webhook `DeliveryCallback` |
| Disconnect | webhook + `GET .../disconnect` |

Payloads webhook: [webhook-events.md](./webhook-events.md)
