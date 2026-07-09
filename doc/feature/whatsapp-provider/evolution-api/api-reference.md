# API Reference — Evolution (uso pelo provider Chatwoot)

Endpoints REST que o fork chama. Base URL: `{base_url}` do `provider_config`. Auth: header **`apikey: {api_key}`**.

Documentação oficial: https://docs.evolutionfoundation.com.br/evolution-api

**Postman v2.3 (validação manual):** [postman-validation.md](./postman-validation.md) · [collection agenciadgcode](https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3)

---

## Health (raiz)

| Ação | Método | Notas |
|------|--------|-------|
| Informações da API | `GET /` | Versão, URL do manager — pasta **Get Informations** no Postman |
| Métricas | `GET /metrics` | Prometheus — só se `METRICS` habilitado no `.env` |

---

## Convenções

| Item | Valor |
|------|-------|
| Prefixo instância | `/:instanceName` no path (exceto `/instance/create` e `/instance/fetchInstances`) |
| Content-Type | `application/json` |
| Guards Evolution | `instanceExistsGuard`, `instanceLoggedGuard`, `authGuard.apikey` |

Rotas montadas em `src/api/routes/index.router.ts`:

```
/instance   → InstanceRouter
/message    → MessageRouter
/settings   → SettingsRouter
/proxy      → ProxyRouter
/webhook    → WebhookRouter (EventRouter)
/chat       → ChatRouter
```

---

## 1. Lifecycle da instância

### Criar instância

```
POST /instance/create
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/create-instance

**Body mínimo (Baileys + QR):**

```json
{
  "instanceName": "minha-instancia",
  "integration": "WHATSAPP-BAILEYS",
  "qrcode": true,
  "groupsIgnore": true,
  "rejectCall": false,
  "alwaysOnline": false,
  "readMessages": false,
  "readStatus": false,
  "syncFullHistory": false
}
```

**Proxy inline (opcional):**

```json
{
  "proxyHost": "proxy.example.com",
  "proxyPort": "8080",
  "proxyProtocol": "http",
  "proxyUsername": "user",
  "proxyPassword": "pass"
}
```

**Resposta relevante:**

```json
{
  "instance": {
    "instanceName": "...",
    "instanceId": "uuid",
    "status": "connecting"
  },
  "hash": "INSTANCE-API-KEY",
  "qrcode": { "base64": "...", "code": "..." },
  "settings": { ... }
}
```

Persistir `hash` → `provider_config.api_key` e `instanceId` → `provider_config.instance_id`.

**Código:** `src/api/controllers/instance.controller.ts` → `createInstance()`

---

### Conectar (QR / pairing)

```
GET /instance/connect/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/connect-instance

Query opcional: `?number=5511999999999`

Retorna QR atualizado. Alternativa: aguardar webhook `QRCODE_UPDATED`.

---

### Estado da conexão

```
GET /instance/connectionState/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/get-connection-state

```json
{
  "instance": { "instanceName": "...", "state": "open" }
}
```

Estados: `open`, `close`, `connecting`, etc.

---

### Listar instâncias

```
GET /instance/fetchInstances
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/fetch-all-instances

Útil para wizard "usar instância existente".

---

### Logout / restart / delete

| Ação | Método | Doc |
|------|--------|-----|
| Logout | `DELETE /instance/logout/:instanceName` | [logout-instance](https://docs.evolutionfoundation.com.br/evolution-api/logout-instance) |
| Restart | `POST /instance/restart/:instanceName` | [restart-instance](https://docs.evolutionfoundation.com.br/evolution-api/restart-instance) |
| Delete | `DELETE /instance/delete/:instanceName` | [delete-instance](https://docs.evolutionfoundation.com.br/evolution-api/delete-instance) |

---

### Presença da instância

```
POST /instance/setPresence/:instanceName
{ "presence": "available" }
```

Valores: `unavailable`, `available`, `composing`, `recording`, `paused`

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/set-presence

Uso no fork: **não** ligado ao typing do dashboard. Serve para presença global da sessão WhatsApp.

### Presença por chat (typing)

```
POST /chat/sendPresence/:instanceName
{ "number": "5511999999999", "presence": "composing", "delay": 3000 }
```

- `presence`: `composing` | `recording` | `paused` | `available` | `unavailable`
- `delay` (ms) é **obrigatório** no schema Evolution v2.3.x — o servidor segura o HTTP pelo delay e depois força `paused`
- Fork: `ApiClient#send_presence` + `PresenceSyncService` / `TypingListener` (dashboard `conversation.typing_on` / `typing_off`)
- Delay curto no composing (`3000`) para não bloquear Sidekiq; Chatwoot reemite typing enquanto o agente digita

Listado em [postman-validation.md](./postman-validation.md) (`Send Presence (chat)`).

---

## 2. Settings

### Set

```
POST /settings/set/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/set-settings

```json
{
  "rejectCall": false,
  "msgCall": "",
  "groupsIgnore": true,
  "alwaysOnline": false,
  "readMessages": false,
  "readStatus": false,
  "syncFullHistory": false
}
```

### Find

```
GET /settings/find/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/get-settings

---

## 3. Proxy

Proxy afeta apenas o **socket Baileys** da instância (conexão WhatsApp Web) — não o tráfego Chatwoot ↔ Evolution REST.

**Fase fork:** Fase 1 (wizard) + Fase 2 (settings completo) — **implementado**. Ver [inbox-business-rules.md §3](./inbox-business-rules.md) · [decisions.md §19](./decisions.md).

### Set (por instância)

```
POST /proxy/set/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/set-proxy

**Body (runtime — `proxy.schema.ts`):**

```json
{
  "enabled": true,
  "host": "proxy.example.com",
  "port": "8080",
  "protocol": "http",
  "username": "",
  "password": ""
}
```

| Campo | Obrigatório se `enabled: true` | Valores `protocol` |
|-------|-------------------------------|-------------------|
| `host` | Sim | — |
| `port` | Sim | string numérica |
| `protocol` | Sim | `http`, `https`, `socks4`, `socks5` |
| `username` / `password` | Não | Auth SOCKS/HTTP |

**Desabilitar:** `{ "enabled": false }` — Evolution zera host/port/protocol no controller.

**Validação Evolution:** antes de persistir, `ProxyController#testProxy` chama `https://icanhazip.com/` via proxy — IP de saída deve **diferir** do IP direto; senão HTTP 400 `Invalid proxy`.

**Código:** `proxy.controller.ts`, `channel.service.ts#setProxy`, `makeProxyAgent.ts`

> **OpenAPI vs runtime:** doc oficial usa `proxyHost` / `proxyPort` em `/proxy/set` — código local aceita **`host`** / **`port`**. Ver [documentation-links.md §6](./documentation-links.md).

### Proxy inline no create

`POST /instance/create` aceita campos **`proxyHost`**, `proxyPort`, `proxyProtocol`, `proxyUsername`, `proxyPassword` (`instance.schema.ts`) — formato diferente de `/proxy/set`.

### Find

```
GET /proxy/find/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/get-proxy

Retorna registro Prisma da instância. HTTP 404 se nunca configurado.

### Comportamento Baileys

- Proxy aplicado em `whatsapp.baileys.service.ts` ao criar socket (`agent` + `fetchAgent`)
- Caso especial `proxyscrape` no host: busca lista HTTP e escolhe IP aleatório (legado Evolution — não replicar no fork)
- Após alterar proxy: pode exigir **restart** da instância (`POST /instance/restart`) para socket reconectar — validar em staging

### Mapeamento Chatwoot → Evolution

| `provider_config` | `POST /proxy/set` |
|-------------------|-------------------|
| `proxy_enabled` | `enabled` |
| `proxy_host` | `host` |
| `proxy_port` | `port` |
| `proxy_protocol` | `protocol` |
| `proxy_username` | `username` |
| `proxy_password` | `password` |

`ConnectionService#sync_proxy!` ao salvar settings do inbox — **implementado** (Fase 1 wizard + Fase 2 settings).

---

## 4. Webhook

### Set

```
POST /webhook/set/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/set-webhook

```json
{
  "webhook": {
    "enabled": true,
    "url": "https://chatwoot.example.com/webhooks/evolution/minha-instancia",
    "byEvents": false,
    "base64": false,
    "events": ["MESSAGES_UPSERT", "MESSAGES_UPDATE", "CONTACTS_UPSERT", "CONTACTS_UPDATE", "CONNECTION_UPDATE", "QRCODE_UPDATED"]
  }
}
```

Se `events` vazio com `enabled: true`, Evolution registra **todos** os eventos (`EventController.events`).

### Headers opcionais

```json
{
  "webhook": {
    "enabled": true,
    "url": "https://chatwoot.example.com/webhooks/evolution/minha-instancia",
    "byEvents": false,
    "base64": false,
    "events": ["MESSAGES_UPSERT", "MESSAGES_UPDATE", "CONTACTS_UPSERT", "CONTACTS_UPDATE", "CONNECTION_UPDATE", "QRCODE_UPDATED"],
    "headers": {
      "Authorization": "Bearer optional-shared-secret"
    }
  }
}
```

O fork valida primariamente `apikey` no **body** do envelope ([decisions.md §2](./decisions.md)). Headers extras são opcionais para operadores com requisitos de segurança adicionais.

### Find

```
GET /webhook/find/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/get-webhook

---

## 5. Mensagens — outbound (Chatwoot → Evolution)

### Texto (MVP)

```
POST /message/sendText/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/send-text-message

```json
{
  "number": "5511999999999",
  "text": "Olá!",
  "delay": 500,
  "quoted": {
    "key": { "id": "MSG_ID", "remoteJid": "5511...@s.whatsapp.net", "fromMe": false },
    "message": { "conversation": "texto original" }
  }
}
```

> **Atenção:** o OpenAPI publicado em [send-text-message](https://docs.evolutionfoundation.com.br/evolution-api/send-text-message) usa `textMessage: { text }`. O código em `/root/evolution-api` aceita **`text`** plano. Validar contra o servidor em produção — ver [documentation-links.md](./documentation-links.md).

**Resposta (Baileys messageRaw):** objeto com `key.id` — usar como `source_id`:

```json
{
  "key": {
    "remoteJid": "5511999999999@s.whatsapp.net",
    "fromMe": true,
    "id": "3EB0XXXX"
  },
  "message": { "conversation": "Olá!" },
  "messageTimestamp": 1234567890
}
```

**`process_response` no fork:** extrair `response['key']['id']` (não `messages[0].id` da Meta).

**Código:** `sendMessage.controller.ts` → `textMessage()` → `whatsapp.baileys.service.ts`

---

### Mídia (Fase 2)

```
POST /message/sendMedia/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/send-media-message

```json
{
  "number": "5511999999999",
  "mediatype": "image",
  "media": "https://example.com/photo.jpg",
  "caption": "Legenda",
  "fileName": "documento.pdf",
  "delay": 1200,
  "quoted": {
    "key": { "id": "MSG_ID", "remoteJid": "5511...@s.whatsapp.net", "fromMe": false },
    "message": { "conversation": "texto original" }
  }
}
```

`mediatype`: `image`, `document`, `video`, `audio`, `ptv`

Áudio enviado como voice note usa endpoint dedicado:

```
POST /message/sendWhatsAppAudio/:instanceName
```

```json
{
  "number": "5511999999999",
  "audio": "https://example.com/voice.ogg",
  "delay": 1200,
  "quoted": { "key": { ... }, "message": { "conversation": "..." } }
}
```

Inbound mídia (webhook `webhookBase64: false`): Chatwoot chama `POST /chat/getBase64FromMediaMessage/:instanceName` — ver `IncomingMessageServiceHelpers` prepend em `custom/`. O normalizer inclui `evolution_remote_jid` no payload para delete sync e contatos LID.

---

### Áudio, sticker, poll (Fase 2–3)

| Endpoint | Fase | Notas |
|----------|------|-------|
| `POST /message/sendWhatsAppAudio/:instanceName` | 2 | Upload multipart ou `audio` base64/URL |
| `POST /message/sendPtv/:instanceName` | 3 | Video note |
| `POST /message/sendSticker/:instanceName` | 3 | Upload |
| `POST /message/sendPoll/:instanceName` | 3 | Enquete |

### Interativos e contato (implementados no fork)

| Endpoint | Doc | Status fork |
|----------|-----|-------------|
| `POST /message/sendButtons/:instanceName` | [send-buttons](https://docs.evolutionfoundation.com.br/evolution-api/send-buttons) | ✅ `input_select` com ≤3 itens |
| `POST /message/sendList/:instanceName` | [send-list](https://docs.evolutionfoundation.com.br/evolution-api/send-list) | ✅ `input_select` com >3 itens |
| `POST /message/sendContact/:instanceName` | [send-contact](https://docs.evolutionfoundation.com.br/evolution-api/send-contact) | ✅ cartão de contato outbound |
| `POST /message/sendLocation/:instanceName` | [send-location](https://docs.evolutionfoundation.com.br/evolution-api/send-location) | ⏸️ Fase 3+ |
| `POST /message/sendReaction/:instanceName` | [send-reaction](https://docs.evolutionfoundation.com.br/evolution-api/send-reaction) | ⏸️ Fase 3+ |

---

### Marcar como lida

```
POST /chat/markMessageAsRead/:instanceName
```

**Doc:** https://docs.evolutionfoundation.com.br/evolution-api/mark-message-as-read

---

### Deletar mensagem (sync outbound)

```
DELETE /chat/deleteMessageForEveryone/:instanceName
{ "id": "MSG_ID", "fromMe": true, "remoteJid": "5511...@s.whatsapp.net" }
```

Usado por `DeleteSyncService` quando `sync_delete_to_whatsapp: true` no inbox.

---

### Perfil de contato (enrichment)

| Endpoint | Uso no fork |
|----------|-------------|
| `POST /chat/fetchProfilePictureUrl/:instanceName` | `ContactEnrichmentService` |
| `POST /chat/fetchProfile/:instanceName` | Idem |
| `POST /chat/fetchBusinessProfile/:instanceName` | Idem |

### Grupos (metadata)

| Endpoint | Uso no fork |
|----------|-------------|
| `GET /group/findGroupInfos/:instanceName?groupJid={jid}` | `GroupMetadataService` — subject do grupo para nome do contato (`{subject} (GROUP)`); cache 1h |

Query param validado contra Evolution **2.3.7** (`groupJid` URL-encoded). Fixture: `spec/fixtures/evolution/group_find_infos_response.json`.

---

## 6. Chat — histórico (fase posterior)

| Endpoint | Doc |
|----------|-----|
| `POST /chat/findContacts/:instanceName` | [find-contacts](https://docs.evolutionfoundation.com.br/evolution-api/find-contacts) |
| `POST /chat/findMessages/:instanceName` | [find-messages](https://docs.evolutionfoundation.com.br/evolution-api/find-messages) |
| `POST /chat/findChats/:instanceName` | [find-chats](https://docs.evolutionfoundation.com.br/evolution-api/find-chats) |

---

## 7. Integração Chatwoot na Evolution — NÃO usar

```
POST /chatwoot/set/:instanceName   ← manter disabled
GET  /chatwoot/find/:instanceName
POST /chatwoot/webhook/:instanceName
```

Ver [current-evolution-chatwoot-integration.md](./current-evolution-chatwoot-integration.md).

---

## 8. Templates Evolution (não WABA)

Endpoints existem mas são para modo Cloud/Business na Evolution — **fora do escopo** Baileys MVP:

- [find-templates](https://docs.evolutionfoundation.com.br/evolution-api/find-templates)
- [create-template](https://docs.evolutionfoundation.com.br/evolution-api/create-template)

No fork: `sync_templates` → noop; `send_template` → texto livre ou erro documentado.

---

## Cliente HTTP sugerido no fork

```ruby
# custom/app/services/custom/whatsapp/evolution/api_client.rb
# ApiClient.for_channel(channel) — base_url, api_key, instance_name do provider_config
# headers: { 'apikey' => api_key, 'Content-Type' => 'application/json' }
# métodos: create_instance, connect, connection_state, apply_webhook, apply_settings,
#          apply_proxy, disable_chatwoot_integration, send_text, send_media, send_audio, …
```

`ConnectionService`, `Provisioner` e `EvolutionService` delegam para o mesmo client.
