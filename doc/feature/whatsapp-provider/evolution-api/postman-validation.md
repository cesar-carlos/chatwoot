# Validação Postman v2.3 — Evolution API

Revisão endpoint a endpoint da collection **[Evolution API | v2.3.*](https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3)** contra:

1. Código local `/root/evolution-api` (v**2.3.6** dev) · produção **2.3.7**
2. Documentação do fork: [api-reference.md](./api-reference.md) · [documentation-links.md](./documentation-links.md)

**Última revisão:** jun/2026

---

## Como usar esta página com o Postman

1. Abrir a collection no Postman (link acima) ou importar de [evolution-api.com/postman](https://evolution-api.com/postman).
2. Configurar variáveis de ambiente: `baseUrl`, `apikey`, `instance` (nome da instância).
3. Para cada pasta da collection, conferir **método + path** na tabela abaixo.
4. Se o body do Postman divergir do **runtime** (coluna “Body runtime”), seguir o runtime — o fork usa o código, não o OpenAPI desatualizado.

> A API Postman pública não permite export JSON sem login; esta validação foi feita pelo **source of truth** em `src/api/routes/*.router.ts` e schemas em `src/validate/`.

---

## Resumo — provider Chatwoot (Fase 1)

| Endpoint | Postman / código | `api-reference.md` | Status |
|----------|------------------|-------------------|--------|
| `POST /instance/create` | Instance | §1 | ✅ Correto |
| `GET /instance/connect/:instance` | Instance | §1 | ✅ Correto |
| `GET /instance/connectionState/:instance` | Instance | §1 | ✅ Correto |
| `GET /instance/fetchInstances` | Instance | §1 | ✅ Correto |
| `POST /instance/restart/:instance` | Instance | §1 | ✅ Correto |
| `DELETE /instance/logout/:instance` | Instance | §1 | ✅ Correto |
| `DELETE /instance/delete/:instance` | Instance | §1 | ✅ Correto |
| `POST /instance/setPresence/:instance` | Instance | §1 | ✅ Correto |
| `POST /settings/set/:instance` | Settings | §2 | ✅ Correto |
| `GET /settings/find/:instance` | Settings | §2 | ✅ Correto |
| `POST /proxy/set/:instance` | Proxy | §3 | ✅ Correto (`host`/`port`, não `proxyHost`) |
| `GET /proxy/find/:instance` | Proxy | §3 | ✅ Correto |
| `POST /webhook/set/:instance` | Integrations → Webhook | §4 | ✅ Correto (`webhook.byEvents`) |
| `GET /webhook/find/:instance` | Integrations → Webhook | §4 | ✅ Correto |
| `POST /message/sendText/:instance` | Send Message | §5 | ✅ Correto (`text`, não `textMessage`) |
| `POST /message/sendMedia/:instance` | Send Message | §5 | ✅ Fase 2 |
| `POST /chat/markMessageAsRead/:instance` | Chat | §5 | ✅ Correto (rota em `/chat`, não `/message`) |
| `POST /chat/findContacts/:instance` | Chat | §6 | ✅ Fase 4 |
| `POST /chat/findMessages/:instance` | Chat | §6 | ✅ Fase 4 |
| `POST /chat/findChats/:instance` | Chat | §6 | ✅ Fase 4 |
| `POST /chatwoot/set/:instance` | Integrations → Chatwoot | §7 | ✅ Documentado como **NÃO usar** |
| `GET /` | Get Informations | — | ⚠️ Adicionado neste doc (health) |
| `GET /metrics` | Metrics | — | ⚠️ Opcional (Prometheus, se `METRICS` habilitado) |

**Conclusão Fase 1:** os endpoints que o fork precisa estão **corretos** em `api-reference.md`. As divergências conhecidas são de **formato de body** (OpenAPI/Postman antigo vs runtime) — já documentadas em [documentation-links.md § Discrepâncias](./documentation-links.md#discrepâncias-documentação-vs-código-local-rootevolution-api).

---

## Pasta → rotas (collection v2.3.*)

### Raiz

| Postman | Método | Path | Auth | Notas |
|---------|--------|------|------|-------|
| Get Informations | `GET` | `/` | Não | Retorna `version`, `manager`, `whatsappWebVersion` |
| Metrics | `GET` | `/metrics` | Depende config | Só se `METRICS` habilitado no `.env` |
| — | `POST` | `/verify-creds` | `apikey` | Valida credenciais Meta (Cloud) — fora do MVP Baileys |

---

### Instance

| Postman (típico) | Método | Path | Body runtime (`instance.schema.ts`) |
|------------------|--------|------|-------------------------------------|
| Create Instance | `POST` | `/instance/create` | `instanceName`, `integration: "WHATSAPP-BAILEYS"`, `qrcode`, `groupsIgnore`, `rejectCall`, …; proxy inline: `proxyHost`, `proxyPort`, …; webhook inline: `webhookUrl`, `webhookByEvents`, `webhookEvents` |
| Connect | `GET` | `/instance/connect/:instanceName` | Query opcional: `number` |
| Connection State | `GET` | `/instance/connectionState/:instanceName` | — |
| Fetch Instances | `GET` | `/instance/fetchInstances` | Sem `:instanceName` no path |
| Restart | `POST` | `/instance/restart/:instanceName` | — |
| Logout | `DELETE` | `/instance/logout/:instanceName` | — |
| Delete | `DELETE` | `/instance/delete/:instanceName` | — |
| Set Presence | `POST` | `/instance/setPresence/:instanceName` | `{ "presence": "available" \| "unavailable" \| … }` |

**Resposta create:** persistir `hash` → `api_key`, `instance.instanceId` → `instance_id`, QR em `qrcode.base64` ou via webhook `QRCODE_UPDATED`.

---

### Proxy

| Postman | Método | Path | Body runtime (`proxy.schema.ts`) |
|---------|--------|------|----------------------------------|
| Set Proxy | `POST` | `/proxy/set/:instanceName` | `{ "enabled", "host", "port", "protocol", "username", "password" }` |
| Find Proxy | `GET` | `/proxy/find/:instanceName` | — |

⚠️ **Postman/OpenAPI** às vezes mostram `proxyHost`/`proxyPort` neste endpoint — o **código v2.3.6** usa `host`/`port`. Proxy inline no **create** usa `proxyHost` (formato diferente).

---

### Settings

| Postman | Método | Path | Body runtime (`settings.schema.ts`) |
|---------|--------|------|-------------------------------------|
| Set Settings | `POST` | `/settings/set/:instanceName` | `rejectCall`, `msgCall`, `groupsIgnore`, `alwaysOnline`, `readMessages`, `readStatus`, `syncFullHistory` (todos obrigatórios no schema) |
| Find Settings | `GET` | `/settings/find/:instanceName` | — |

Campos em **camelCase** (`groupsIgnore`), não snake_case.

---

### Send Message

| Postman | Método | Path | Fase fork | Body runtime |
|---------|--------|------|-----------|--------------|
| Send Text | `POST` | `/message/sendText/:instanceName` | **1** | `{ "number", "text", "delay?", "quoted?", "linkPreview?" }` |
| Send Media | `POST` | `/message/sendMedia/:instanceName` | 2 | `multipart` ou JSON: `number`, `mediatype`, `media`, `caption?` |
| Send WhatsApp Audio | `POST` | `/message/sendWhatsAppAudio/:instanceName` | 2 | `audio` + upload opcional |
| Send PTV | `POST` | `/message/sendPtv/:instanceName` | 3 | video note |
| Send Sticker | `POST` | `/message/sendSticker/:instanceName` | 3 | upload |
| Send Status | `POST` | `/message/sendStatus/:instanceName` | — | stories/status |
| Send Location | `POST` | `/message/sendLocation/:instanceName` | 3 | |
| Send Contact | `POST` | `/message/sendContact/:instanceName` | 3 | |
| Send Reaction | `POST` | `/message/sendReaction/:instanceName` | 3 | |
| Send Poll | `POST` | `/message/sendPoll/:instanceName` | 3 | |
| Send List | `POST` | `/message/sendList/:instanceName` | 3 | |
| Send Buttons | `POST` | `/message/sendButtons/:instanceName` | 3 | |
| Send Template | `POST` | `/message/sendTemplate/:instanceName` | — | WABA/Cloud — noop Baileys |

**Divergência crítica Postman/OpenAPI vs runtime:**

| Campo | OpenAPI / Postman antigo | Runtime v2.3.6 |
|-------|--------------------------|----------------|
| Texto | `textMessage: { text }` | **`text`** (string) |
| Webhook set | `webhook_by_events` | **`webhook.byEvents`** |
| Webhook create | `webhookByEvents` (top-level no create) | top-level no `POST /instance/create` |

---

### Call

| Postman | Método | Path | Fase fork |
|---------|--------|------|-----------|
| Offer Call | `POST` | `/call/offer/:instanceName` | — (Baileys; `reject_call` no settings cobre inbound) |

Body: `number`, `callDuration` (1–15), `isVideo?`.

---

### Chat

| Postman | Método | Path | Fase fork |
|---------|--------|------|-----------|
| Check is WhatsApp | `POST` | `/chat/whatsappNumbers/:instanceName` | 2+ |
| Mark Message Read | `POST` | `/chat/markMessageAsRead/:instanceName` | 2 |
| Archive Chat | `POST` | `/chat/archiveChat/:instanceName` | — |
| Mark Chat Unread | `POST` | `/chat/markChatUnread/:instanceName` | — |
| Delete Message | `DELETE` | `/chat/deleteMessageForEveryone/:instanceName` | 2 (`sync_delete`) |
| Find Contacts | `POST` | `/chat/findContacts/:instanceName` | 4 |
| Find Messages | `POST` | `/chat/findMessages/:instanceName` | 4 |
| Find Chats | `POST` | `/chat/findChats/:instanceName` | 4 |
| Find Status Message | `POST` | `/chat/findStatusMessage/:instanceName` | — |
| Find Chat By Remote Jid | `GET` | `/chat/findChatByRemoteJid/:instanceName?remoteJid=` | — |
| Fetch Profile Picture | `POST` | `/chat/fetchProfilePictureUrl/:instanceName` | — |
| Get Base64 Media | `POST` | `/chat/getBase64FromMediaMessage/:instanceName` | 2 (mídia inbound) |
| Update Message | `POST` | `/chat/updateMessage/:instanceName` | — |
| Send Presence (chat) | `POST` | `/chat/sendPresence/:instanceName` | ✅ typing (`PresenceSyncService`) |
| Block User | `POST` | `/chat/updateBlockStatus/:instanceName` | — |

---

### Profile Settings (subpasta Chat no Postman)

| Postman | Método | Path |
|---------|--------|------|
| Fetch Business Profile | `POST` | `/chat/fetchBusinessProfile/:instanceName` |
| Fetch Profile | `POST` | `/chat/fetchProfile/:instanceName` |
| Update Profile Name | `POST` | `/chat/updateProfileName/:instanceName` |
| Update Profile Status | `POST` | `/chat/updateProfileStatus/:instanceName` |
| Update Profile Picture | `POST` | `/chat/updateProfilePicture/:instanceName` |
| Remove Profile Picture | `DELETE` | `/chat/removeProfilePicture/:instanceName` |
| Fetch Privacy Settings | `GET` | `/chat/fetchPrivacySettings/:instanceName` |
| Update Privacy Settings | `POST` | `/chat/updatePrivacySettings/:instanceName` |

Fora do escopo do provider Chatwoot MVP.

---

### Label

| Postman | Método | Path |
|---------|--------|------|
| Find Labels | `GET` | `/label/findLabels/:instanceName` |
| Handle Label | `POST` | `/label/handleLabel/:instanceName` |

---

### Group

| Postman | Método | Path |
|---------|--------|------|
| Create Group | `POST` | `/group/create/:instanceName` |
| Update Subject | `POST` | `/group/updateGroupSubject/:instanceName` |
| Update Picture | `POST` | `/group/updateGroupPicture/:instanceName` |
| Update Description | `POST` | `/group/updateGroupDescription/:instanceName` |
| Find Group Infos | `GET` | `/group/findGroupInfos/:instanceName` |
| Fetch All Groups | `GET` | `/group/fetchAllGroups/:instanceName` |
| Participants | `GET` | `/group/participants/:instanceName` |
| Invite Code | `GET` | `/group/inviteCode/:instanceName` |
| Invite Info | `GET` | `/group/inviteInfo/:instanceName` |
| Accept Invite | `GET` | `/group/acceptInviteCode/:instanceName` |
| Send Invite | `POST` | `/group/sendInvite/:instanceName` |
| Revoke Invite | `POST` | `/group/revokeInviteCode/:instanceName` |
| Update Participant | `POST` | `/group/updateParticipant/:instanceName` |
| Update Setting | `POST` | `/group/updateSetting/:instanceName` |
| Toggle Ephemeral | `POST` | `/group/toggleEphemeral/:instanceName` |
| Leave Group | `DELETE` | `/group/leaveGroup/:instanceName` |

Com `groups_ignore: true` no fork, a maioria é irrelevante para inbound.

---

### Integrations (pasta Postman)

Montagem em `ChatbotRouter` + `EventRouter`:

| Integração | Prefixo | Endpoints principais | Fork |
|------------|---------|---------------------|------|
| **Webhook** | `/webhook` | `POST /set/:instance`, `GET /find/:instance` | ✅ Usar |
| WebSocket | `/websocket` | set/find | Opcional (fork usa ActionCable) |
| RabbitMQ, NATS, SQS, Kafka, Pusher | `/rabbitmq`, … | set/find | Não |
| **Chatwoot** | `/chatwoot` | `POST /set/:instance`, `GET /find/:instance`, `POST /webhook/:instance` | ❌ **Desabilitar** com provider nativo |
| Typebot, OpenAI, Dify, Flowise, n8n, EvoAI, EvolutionBot | `/typebot`, … | CRUD bots | Não |

**Webhook body (confirmado Postman v2.3 + código):**

```json
{
  "webhook": {
    "enabled": true,
    "url": "https://chatwoot.example.com/webhooks/evolution/MINHA-INSTANCIA",
    "byEvents": false,
    "base64": false,
    "events": ["MESSAGES_UPSERT", "MESSAGES_UPDATE", "CONNECTION_UPDATE", "QRCODE_UPDATED"],
    "headers": {}
  }
}
```

Eventos completos: enum em `instance.schema.ts` / `EventController.events`.

---

## Autenticação (todas as pastas)

```http
apikey: {GLOBAL_API_KEY}
```

ou token da instância (`hash` retornado no create).

Header alternativo em alguns exemplos Postman: `Authorization: Bearer …` — o guard principal no código é **`apikey`**.

---

## Checklist rápido no Postman (antes de codar Fase 1)

- [ ] `GET /` → versão ≥ 2.3.7 (ou pin em [evolution-target-version.txt](./evolution-target-version.txt))
- [ ] `POST /instance/create` com `integration: WHATSAPP-BAILEYS` → recebe `hash` + QR
- [ ] `GET /instance/connectionState/:instance` → `open` após scan
- [ ] `POST /webhook/set/:instance` com URL Chatwoot → `GET /webhook/find` confirma
- [ ] `POST /message/sendText/:instance` com body `{ "number", "text" }` → mensagem no WhatsApp
- [ ] Webhook inbound `MESSAGES_UPSERT` chega no Chatwoot (após Fase 1 implementada)
- [ ] `GET /chatwoot/find/:instance` → `enabled: false` (sem integração legada)

Registrar resultados em [validation-checklist.md](./validation-checklist.md).

---

## Referências

| Recurso | URL |
|---------|-----|
| Collection Postman v2.3 (agenciadgcode) | https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3 |
| Postman oficial Evolution | https://evolution-api.com/postman |
| OpenAPI | https://docs.evolutionfoundation.com.br/api-reference/openapi.json |
| Código rotas | `/root/evolution-api/src/api/routes/` + `src/api/integrations/` |
