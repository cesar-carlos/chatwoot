# Webhooks — Z-API

Mapeamento dos callbacks Z-API para o pipeline Chatwoot (`WhatsappEventsJob` → normalizer → `IncomingMessageService`).

**Última revisão:** 23/jun/2026 — payloads confirmados em [developer.z-api.io](https://developer.z-api.io/webhooks/on-message-received-examples.md)

---

## Modelo Z-API vs Evolution

| Aspecto | Evolution | Z-API |
|---------|-----------|-------|
| Configuração | 1 URL + lista de eventos | 4–7 URLs ou 1 bulk (`update-every-webhooks`) |
| Transporte | POST JSON com `event` + `data` | POST JSON com `type` no root |
| Identificação inbox | `instance_name` na rota | `instance_id` na rota |
| Auth callback | `?token=webhook_token` | Mesmo padrão fork (Z-API exige HTTPS) |

---

## Tipos de callback (`type`)

| `type` | Config REST | Uso Chatwoot |
|--------|-------------|--------------|
| `ReceivedCallback` | `update-webhook-received` | Inbound mensagens |
| `DeliveryCallback` | `update-webhook-delivery` | Confirmação envio / erros |
| `MessageStatusCallback` | `update-webhook-message-status` | SENT / RECEIVED / READ / PLAYED |
| `DisconnectedCallback` | `update-webhook-disconnected` | Perda de sessão |
| `ConnectedCallback` | `update-webhook-connected` | Sessão restabelecida |
| Chat presence | `update-webhook-chat-presence` | Ignorar MVP |

Doc índice: [webhooks/introduction](https://developer.z-api.io/webhooks/introduction.md)

---

## Estratégia no fork

**Rota única:**

```
POST /webhooks/zapi/:instance_id?token={webhook_token}
```

Registrar via:

```json
PUT .../update-every-webhooks
{
  "value": "https://chatwoot.example.com/webhooks/zapi/INSTANCE_ID?token=SECRET",
  "notifySentByMe": false
}
```

`ZapiController` + `ZapiNormalizer` roteiam por `payload['type']`.

---

## Atributos comuns (todos os callbacks)

Fonte: [on-message-received-examples](https://developer.z-api.io/webhooks/on-message-received-examples.md)

| Campo | Tipo | Uso |
|-------|------|-----|
| `instanceId` | string | Validar === `params[:instance_id]` |
| `messageId` | string | `source_id` |
| `phone` | string | `ContactInbox#source_id` |
| `fromMe` | boolean | Ignorar se `true` |
| `isGroup` | boolean | Ignorar se `true` (MVP) |
| `isNewsletter` | boolean | Ignorar se `true` |
| `momment` | integer | Timestamp ms (typo oficial Z-API) |
| `status` | string | PENDING, SENT, RECEIVED, READ, PLAYED |
| `type` | string | Discriminador do evento |
| `senderName` | string | Nome do contato |
| `chatName` | string | Nome exibido no chat |
| `senderLid` | string | LID WhatsApp — fallback identificação |
| `connectedPhone` | string | Número da instância conectada |
| `participantPhone` | string | Em grupos — ignorar MVP |

---

## ReceivedCallback — texto

```json
{
  "isStatusReply": false,
  "senderLid": "81896604192873@lid",
  "connectedPhone": "554499999999",
  "waitingMessage": false,
  "isEdit": false,
  "isGroup": false,
  "isNewsletter": false,
  "instanceId": "A20DA9C0183A2D35A260F53F5D2B9244",
  "messageId": "A20DA9C0183A2D35A260F53F5D2B9244",
  "phone": "5544999999999",
  "fromMe": false,
  "momment": 1632228638000,
  "status": "RECEIVED",
  "chatName": "Nome",
  "senderName": "Nome",
  "type": "ReceivedCallback",
  "text": {
    "message": "teste"
  }
}
```

**Normalizer:**

| Campo flat | Origem |
|------------|--------|
| `content` | `text.message` |
| `content_type` | `text` |
| `source_id` | `messageId` |
| `phone` | `phone` |

---

## ReceivedCallback — imagem

```json
{
  "type": "ReceivedCallback",
  "messageId": "...",
  "phone": "5544999999999",
  "fromMe": false,
  "isGroup": false,
  "image": {
    "mimeType": "image/jpeg",
    "imageUrl": "https://...",
    "thumbnailUrl": "https://...",
    "caption": "",
    "width": 600,
    "height": 315
  }
}
```

**Fase 2:** `attachments: [{ url: image.imageUrl, file_type: 'image' }]` — download no job.

Outros tipos documentados: áudio, vídeo, documento, localização, contato, sticker, enquete — ver [exemplos completos](https://developer.z-api.io/webhooks/on-message-received-examples.md).

---

## DeliveryCallback

Fonte: [on-message-send-examples](https://developer.z-api.io/webhooks/on-message-send-examples.md)

### Sucesso

```json
{
  "phone": "554499999999",
  "messageId": "A800FB3697F1DE58C48D",
  "instanceId": "instance.id",
  "zaapId": "A20DA9C0183A2D35A260F53F5D2B9244",
  "momment": 1777494009341,
  "type": "DeliveryCallback"
}
```

### Erro

```json
{
  "phone": "554499999999",
  "messageId": "A20DA9C0183A2D35A260F53F5D2B9244",
  "error": "Phone number does not exist",
  "instanceId": "instance.id",
  "zaapId": "A20DA9C0183A2D35A260F53F5D2B9244",
  "momment": 1777494091684,
  "type": "DeliveryCallback"
}
```

**Chatwoot MVP:** logar `error`; status principal via `MessageStatusCallback`. `errorCode: "SHADOW_BAN"` — alertar operador.

---

## MessageStatusCallback

Fonte: [on-whatsapp-message-status-changes](https://developer.z-api.io/webhooks/on-whatsapp-message-status-changes.md)

```json
{
  "instanceId": "instance.id",
  "status": "READ",
  "ids": ["999999999999999999999"],
  "phone": "5544999999999",
  "momment": 1632228638000,
  "phoneDevice": 0,
  "type": "MessageStatusCallback",
  "isGroup": false
}
```

| Z-API `status` | Chatwoot |
|----------------|----------|
| `SENT` | sent |
| `RECEIVED` | delivered |
| `READ` / `READ_BY_ME` | read |
| `PLAYED` | read (áudio) |

**Mapeamento:** `source_id` = `ids[0]`; emitir array `statuses[]` flat para job upstream.

---

## DisconnectedCallback

Fonte: [on-whatsapp-disconnected](https://developer.z-api.io/webhooks/on-whatsapp-disconnected.md)

```json
{
  "momment": 1632228638000,
  "error": "Description",
  "disconnected": true,
  "type": "DisconnectedCallback",
  "instanceId": "..."
}
```

Atualizar `provider_config.connection_status` → `disconnected`; broadcast ActionCable.

---

## ConnectedCallback

Fonte: [on-webhook-connected](https://developer.z-api.io/webhooks/on-webhook-connected.md)

```json
{
  "type": "ConnectedCallback",
  "connected": true,
  "momment": 26151515154,
  "instanceId": "instance.id",
  "phone": "5544999999999"
}
```

Atualizar `connection_status` → `connected` e `phone_number` ← `phone`.

---

## Fila de envio assíncrona

1. `POST /send-text` → retorna `messageId` imediato
2. `DeliveryCallback` → aceito pelo WhatsApp
3. `MessageStatusCallback` → progressão de status

`zaapId` = ID fila interna — **não** usar como `source_id`.

---

## Normalizer checklist

- [ ] Router por `type`
- [ ] `ignore?` → `fromMe`, `isGroup`, `isNewsletter`
- [ ] `extract_source_id` → `messageId` ou `ids[0]`
- [ ] `extract_phone` → `phone` (strip não-dígitos)
- [ ] Conteúdo por chave: `text`, `image`, `audio`, `video`, `document`, `location`, `contact`
- [ ] Mídia: URL download Fase 2

---

## Fixtures (`spec/fixtures/zapi/`)

| Arquivo | Evento |
|---------|--------|
| `received_text.json` | ReceivedCallback texto |
| `received_image.json` | ReceivedCallback imagem |
| `delivery_success.json` | DeliveryCallback OK |
| `delivery_error.json` | DeliveryCallback erro |
| `status_read.json` | MessageStatusCallback READ |
| `disconnected.json` | DisconnectedCallback |

Capturar via [validation-checklist.md](./validation-checklist.md).
