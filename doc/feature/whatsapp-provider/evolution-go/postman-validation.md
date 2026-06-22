# Validação Postman — Evolution Go

Mapa da collection **[Evolution GO](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go)** cruzado com OpenAPI oficial (`docs.evolutionfoundation.com.br/evolution-go/*`) e documentação fork.

**Última revisão:** 22/jun/2026 — audit via Postman MCP (collection `26869335-5d33806c-d951-48d9-b258-140c3277a923`, fork org `9985534-d3e2f18b-3401-4352-809b-a84b02fd8198`)

---

## Fontes de verdade

| Fonte | Escopo | Prioridade implementação |
|-------|--------|--------------------------|
| **OpenAPI** (`llms.txt` + páginas `evolution-go/*`) | Endpoints publicados oficialmente | **1ª** — Fase 1 MVP |
| **Postman dgcode** | Collection completa (inclui endpoints não indexados no OpenAPI) | **2ª** — complementar + E2E |
| **Swagger runtime** | Versão instalada no servidor | **3ª** — congelar `evolution-target-version.txt` |

---

## Estrutura Postman (12 pastas, ~75 requests)

```
Evolution GO
├── Instance          ← 15 requests (Fase 1 + admin)
├── Send Message      ← 10 requests (texto + interativos)
├── User              ← 11 requests
├── Message           ← 8 requests
├── Chat              ← 8 requests
├── Group             ← 11 requests
├── Call              ← 1 request
├── Community         ← 3 requests
├── Label             ← 6 requests
├── Newsletter        ← 6 requests
├── Polls             ← 1 request
└── Server            ← 1 request (health)
```

---

## Resumo — provider Chatwoot (Fase 1)

| Endpoint | Postman | OpenAPI | Fase | Status |
|----------|---------|---------|------|--------|
| `POST /instance/create` | ✅ | ✅ | 1 | ✅ Confirmado |
| `POST /instance/connect` | ✅ | ✅ | 1 | ✅ Confirmado |
| `GET /instance/all` | ✅ | ✅ | 1 | ✅ Confirmado |
| `GET /instance/qr` | ✅ | ✅ | 1 | ✅ Confirmado |
| `GET /instance/status` | ✅ | ✅ | 1 | ✅ Confirmado |
| `POST /instance/pair` | ✅ | ✅ | 1 | ✅ Confirmado |
| `POST /send/text` | ✅ | ✅ | 1 | ✅ **Path oficial** |
| `POST /instance/disconnect` | ✅ | ✅ | 3 | ✅ Confirmado |
| `DELETE /instance/logout` | ✅ | ✅ | 3 | ✅ Confirmado |
| `DELETE /instance/delete/{instanceId}` | ✅ | ✅ | 3 | ✅ Confirmado |
| `DELETE /instance/proxy/{instanceId}` | ✅ | ✅ | 2 | ✅ Confirmado |

> **`/message/sendText` não existe** — path correto é **`POST /send/text`**.

---

## Divergências doc fork ↔ Postman ↔ OpenAPI

### Corrigidas nesta revisão (22/jun/2026)

| Antes (doc fork) | Postman / OpenAPI | Ação |
|------------------|-------------------|------|
| `GET /group/my` | `GET /group/myall` | ✅ Corrigido em [documentation-links.md](./documentation-links.md) |
| `POST /instance/{id}/advanced-settings` | `GET` + `PUT /instance/{id}/advanced-settings` | ✅ Corrigido em [api-reference.md](./api-reference.md) |
| Só `/message/downloadimage` | Postman também tem `/message/downloadmedia` | ⚠️ E2E — OpenAPI só indexa `downloadimage` |

### Ainda abertas — validar no E2E

| Tema | Postman | OpenAPI | Impacto fork |
|------|---------|---------|--------------|
| **advanced-settings body** | `rejectCalls`, `rejectCallMessage`, `readStatus` | create response: `rejectCall`, `msgRejectCall`, `ignoreGroups`, `ignoreStatus` | Fase 2 `sync_settings` — aceitar variantes |
| **download mídia** | `POST /message/downloadmedia` (body `message.imageMessage`) | `POST /message/downloadimage` (campos flat) | Fase 2 inbound mídia |
| **reconnect** | `POST /instance/reconnect` | Não no `llms.txt` | **Não usar** no fork — ADR §24; connect canônico |
| **create proxy** | comentário `host` | `address`, `port`, `username`, `password` | Seguir OpenAPI |
| **connect extras** | `websocketEnable`, `rabbitmqEnable`, `natsEnable`, `subscribe: ["ALL"]` | Parcial no create response | Fora MVP; documentar para ops |
| **send/contact body** | `vcard: { fullName, organization, phone }` | OpenAPI genérico | Fase 3 |

### Endpoints Postman sem página OpenAPI (Fase 3+ / ops)

| Path | Postman pasta | Notas |
|------|---------------|-------|
| `GET /instance/info/{instanceId}` | Instance | Admin |
| `GET /instance/logs/{instanceId}` | Instance | Admin + query `start_date`, `end_date`, `level` |
| `POST /instance/reconnect` | Instance | Ops only — fork usa `connect` (ADR §24) |
| `POST /instance/forcereconnect/{instanceId}` | Instance | Admin |
| `POST /send/button` | Send Message | Interativos whatsmeow |
| `POST /send/list` | Send Message | Lista interativa |
| `POST /send/carousel` | Send Message | Carrossel |
| `POST /chat/history-sync` | Chat | Import histórico (evento `HISTORY_SYNC`) |
| `POST /chat/unarchive`, `/chat/unmute`, `/chat/unpin` | Chat | Pares dos archive/mute/pin |
| `POST /group/description`, `/group/leave` | Group | — |
| `GET /polls/{pollMessageId}/results` | Polls | — |
| `GET /server/ok` | Server | Health check |
| `/community/*`, `/newsletter/*`, `/label/*`, `/call/*` | várias | Fora MVP 1:1 |

---

## Instance — detalhe

| Postman | Método | Path | Header `apikey` | Body chave |
|---------|--------|------|-----------------|------------|
| Create | `POST` | `/instance/create` | Global (`adminToken`) | `name`, `token?`, `instanceId?`, `proxy?` |
| Connect | `POST` | `/instance/connect` | Instance token | `webhookUrl`, `subscribe[]`, `phone?` |
| QR | `GET` | `/instance/qr` | Instance token | — |
| Status | `GET` | `/instance/status` | Instance token | — |
| Pair | `POST` | `/instance/pair` | Instance token | `phone` |
| All | `GET` | `/instance/all` | Global | — |
| Info | `GET` | `/instance/info/{instanceId}` | Global | — |
| Logs | `GET` | `/instance/logs/{instanceId}` | Global | query dates/level |
| Disconnect | `POST` | `/instance/disconnect` | Instance token | — |
| Reconnect | `POST` | `/instance/reconnect` | Instance token | **Não usar** no fork |
| Logout | `DELETE` | `/instance/logout` | Instance token | — |
| Delete | `DELETE` | `/instance/delete/{instanceId}` | Global | — |
| Delete proxy | `DELETE` | `/instance/proxy/{instanceId}` | Global | — |
| Force reconnect | `POST` | `/instance/forcereconnect/{instanceId}` | Global | — |
| Get advanced settings | `GET` | `/instance/{instanceId}/advanced-settings` | Instance token | — |
| Update advanced settings | `PUT` | `/instance/{instanceId}/advanced-settings` | Instance token | ver § divergências |

**Connect body Chatwoot:**

```json
{
  "webhookUrl": "{{frontendUrl}}/webhooks/evolution_go/{{instanceName}}?token={{webhookSecret}}",
  "subscribe": ["MESSAGE", "CONNECTION", "QRCODE"]
}
```

**Não usar** `subscribe: ["ALL"]` no fork — gera ruído (`SEND_MESSAGE`, `GROUP`, etc.).

---

## Send Message — detalhe

| Postman | Path | Body mínimo |
|---------|------|-------------|
| Text | `POST /send/text` | `{ number, text }` |
| Media | `POST /send/media` | `{ number, type, url, caption?, filename? }` — `url` aceita HTTP(S) ou base64 |
| Location | `POST /send/location` | `{ number, latitude, longitude, name?, address? }` |
| Contact | `POST /send/contact` | `{ number, vcard: { fullName, organization, phone } }` |
| Sticker | `POST /send/sticker` | `{ number, sticker }` |
| Button | `POST /send/button` | `{ number, title, description, footer, buttons[] }` |
| List | `POST /send/list` | `{ number, title, sections[] }` |
| Carousel | `POST /send/carousel` | `{ number, text, cards[] }` |

**Quoted reply (todos sends):** `{ quoted: { messageId, participant } }`

**Send text response (OpenAPI):** `data.Info.ID` — confirmado oficial.

---

## Message — detalhe

| Postman | Path | Body |
|---------|------|------|
| Mark read | `POST /message/markread` | `{ number, id: [] }` |
| Status | `POST /message/status` | `{ id }` |
| React | `POST /message/react` | `{ number, id, reaction }` |
| Presence | `POST /message/presence` | `{ number, state, isAudio? }` |
| Delete | `POST /message/delete` | `{ chat, messageId }` |
| Edit | `POST /message/edit` | `{ chat, messageId, message }` |
| Download media | `POST /message/downloadmedia` | `{ message: { imageMessage: {...} } }` |
| Download image | `POST /message/downloadimage` | campos flat (OpenAPI) |

---

## User — paths REST (Postman)

| Path | Método | Nota doc fork |
|------|--------|---------------|
| `/user/info` | POST | ✅ |
| `/user/check` | POST | ✅ |
| `/user/avatar` | POST | ✅ |
| `/user/contacts` | GET | ✅ |
| `/user/privacy` | GET | doc só tinha link slug |
| `/user/block` | POST | ✅ |
| `/user/unblock` | POST | ✅ |
| `/user/blocklist` | GET | OpenAPI confirma (sem hífen) |
| `/user/profilePicture` | POST | não listado antes |
| `/user/profileName` | POST | não listado antes |
| `/user/profileStatus` | POST | não listado antes |

---

## Group — paths REST (Postman confirma)

| Path | Método |
|------|--------|
| `/group/list` | GET |
| `/group/myall` | GET — **não** `/group/my` |
| `/group/info` | POST `{ groupJid }` |
| `/group/invitelink` | POST |
| `/group/join` | POST |
| `/group/leave` | POST |
| `/group/create` | POST |
| `/group/name` | POST |
| `/group/description` | POST |
| `/group/photo` | POST |
| `/group/participant` | POST |

---

## Variáveis Postman

| Variável | Exemplo | Uso |
|----------|---------|-----|
| `host` / `baseUrl` | `http://localhost:4000` | Base URL (Postman usa `host`) |
| `adminToken` / `globalApiKey` | UUID global | Create, all, delete, logs |
| `token` / `instanceToken` | UUID instância | Connect, send, message |
| `instance` / `instanceId` | UUID do create | Delete, info, advanced-settings |
| `instanceName` | `minha-instancia` | Webhook URL Chatwoot |
| `frontendUrl` | `https://chatwoot.example.com` | Webhook |
| `webhookSecret` | gerado | Query `?token=` |

---

## Checklist pós-execução

- [ ] Rodar pasta **Instance** + **Send Message → Text** contra servidor real
- [ ] Salvar fixtures `spec/fixtures/evolution_go/`
- [ ] Confirmar `data.Info.ID` no send text response
- [ ] Confirmar webhook `MESSAGE` inbound
- [ ] Testar `GET`+`PUT /instance/{id}/advanced-settings` vs campos create
- [ ] Testar `downloadimage` vs `downloadmedia` para mídia inbound
- [ ] Atualizar [evolution-target-version.txt](./evolution-target-version.txt)

---

## Comparação collections

| Collection | URL | Provider fork |
|------------|-----|---------------|
| **Evolution GO** | [nk736ze/evolution-go](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go) | `evolution_go` |
| Evolution API v2.3 | [nm0wqgt/evolution-api-v2-3](https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3) | `evolution` |
| Evolution API Go v3.0 | workspace Impa 365 | **Não usar** — collection separada, possível fork antigo |

**Não misturar** variáveis nem paths entre collections.
