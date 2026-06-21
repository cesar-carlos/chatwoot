# Validação Postman — Evolution Go

Mapa da collection **[Evolution GO](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go)** validado contra OpenAPI oficial `docs.evolutionfoundation.com.br/evolution-go/*`.

**Última revisão:** jun/2026 — paths confirmados via documentação oficial

---

## Estrutura Postman (pastas)

```
Evolution GO
├── Instance          ← Fase 1 (provider Chatwoot)
├── Send Message      ← Fase 1–3
├── Message           ← Fase 2–3
├── User              ← fora do MVP
├── Chat              ← fora do MVP
├── Group             ← fora do MVP (filtrar inbound)
├── Call              ← voz separada
├── Community         ← fora do MVP
├── Label             ← fora do MVP
├── Newsletter        ← fora do MVP
├── Polls             ← Fase 3
└── Server            ← health / info
```

---

## Resumo — provider Chatwoot

| Endpoint | Postman pasta | OpenAPI | Fase fork | Status |
|----------|---------------|---------|-----------|--------|
| `POST /instance/create` | Instance | ✅ | 1 | ✅ Confirmado |
| `POST /instance/connect` | Instance | ✅ | 1 | ✅ Confirmado |
| `GET /instance/all` | Instance | ✅ | 1 | ✅ Confirmado |
| `GET /instance/qr` | Instance | ✅ | 1 | ✅ Confirmado |
| `GET /instance/status` | Instance | ✅ | 1 | ✅ Confirmado |
| `POST /instance/pair` | Instance | ✅ | 1 | ✅ Confirmado |
| `POST /instance/disconnect` | Instance | ✅ | 3 | ✅ Confirmado |
| `DELETE /instance/logout` | Instance | ✅ | 3 | ✅ Confirmado |
| `DELETE /instance/delete/{instanceId}` | Instance | ✅ | 3 | ✅ Confirmado |
| `DELETE /instance/proxy/{instanceId}` | Instance | ✅ | 2 | ✅ Confirmado |
| `POST /send/text` | Send Message | ✅ | 1 | ✅ **Path oficial** |
| `POST /send/media` | Send Message | ✅ | 2 | ✅ Confirmado |
| `POST /send/location` | Send Message | ✅ | 3 | ✅ Confirmado |
| `POST /send/contact` | Send Message | ✅ | 3 | ✅ Confirmado |
| `POST /send/link` | Send Message | ✅ | 3 | ✅ Confirmado |
| `POST /send/sticker` | Send Message | ✅ | 3 | ✅ Confirmado |
| `POST /send/poll` | Send Message / Polls | ✅ | 3 | ✅ Confirmado |
| `POST /message/markread` | Message | ✅ | 2 | ✅ Confirmado |
| `POST /message/status` | Message | ✅ | 2 | ✅ Confirmado |
| `POST /message/react` | Message | ✅ | 3 | ✅ Confirmado |
| `POST /message/presence` | Message | ✅ | 3 | ✅ Confirmado |
| `POST /message/edit` | Message | ✅ | 3 | ✅ Confirmado |
| `POST /message/delete` | Message | ✅ | 3 | ✅ Confirmado |
| `POST /message/downloadimage` | Message | ✅ | 2 | ✅ Confirmado |

> **`/message/sendText` não existe** no OpenAPI oficial — path correto é **`POST /send/text`**.

---

## Divergências corrigidas (wiki/README vs OpenAPI)

| Antes (levantamento inicial) | Oficial (jun/2026) |
|------------------------------|-------------------|
| `POST /message/sendText` alternativo | ❌ Não documentado — usar `/send/text` |
| `GET /instance/{name}/status` | `GET /instance/status` + header token |
| `DELETE /instance/{name}` | `DELETE /instance/delete/{instanceId}` |
| `source_id` = `key.id` | `data.Info.ID` (PascalCase whatsmeow) |
| Status `connected`/`loggedIn` lowercase | `Connected`/`LoggedIn` PascalCase |
| QR `base64\|code` pipe | `data.Qrcode` + `data.Code` |

---

## Instance — detalhe

| Postman | Método | Path | Header `apikey` | Body chave |
|---------|--------|------|-----------------|------------|
| Create | `POST` | `/instance/create` | Global | `name`, `token?`, `proxy?` |
| Connect | `POST` | `/instance/connect` | Instance token | `webhookUrl`, `subscribe[]`, `phone?` |
| QR | `GET` | `/instance/qr` | Instance token | — |
| Status | `GET` | `/instance/status` | Instance token | — |
| Pair | `POST` | `/instance/pair` | Instance token | `phone`, `subscribe?` |
| All | `GET` | `/instance/all` | Global | — |
| Disconnect | `POST` | `/instance/disconnect` | Instance token | — |
| Logout | `DELETE` | `/instance/logout` | Instance token | — |
| Delete | `DELETE` | `/instance/delete/{instanceId}` | Global | — |
| Delete proxy | `DELETE` | `/instance/proxy/{instanceId}` | Global | — |

**Connect body Chatwoot:**

```json
{
  "webhookUrl": "{{frontendUrl}}/webhooks/evolution_go/{{instanceName}}?token={{webhookSecret}}",
  "subscribe": ["MESSAGE", "CONNECTION", "QRCODE"]
}
```

---

## Send Message — detalhe

| Postman | Path | Body mínimo |
|---------|------|-------------|
| Text | `POST /send/text` | `{ number, text }` |
| Media | `POST /send/media` | `{ number, type, url, caption?, filename? }` |
| Location | `POST /send/location` | `{ number, latitude, longitude, name?, address? }` |
| Sticker | `POST /send/sticker` | `{ number, sticker }` |

**Quoted reply (todos sends):** `{ quoted: { messageId, participant } }`

---

## Message — detalhe

| Postman | Path | Body |
|---------|------|------|
| Mark read | `POST /message/markread` | `{ number, id: [] }` |
| Status | `POST /message/status` | `{ id }` |
| React | `POST /message/react` | `{ number, id, reaction }` |
| Presence | `POST /message/presence` | `{ number, state, isAudio? }` |
| Delete | `POST /message/delete` | `{ chat, messageId }` |

---

## Variáveis Postman recomendadas

| Variável | Exemplo | Uso |
|----------|---------|-----|
| `baseUrl` | `http://localhost:8080` | Todas as requests |
| `globalApiKey` | `your-global-key` | Create, all, delete |
| `instanceToken` | UUID da instância | Connect, send, message |
| `instanceId` | UUID do create | Delete instance/proxy |
| `instanceName` | `minha-instancia` | Webhook URL Chatwoot |
| `frontendUrl` | `https://chatwoot.example.com` | Webhook |
| `webhookSecret` | gerado | Query `?token=` |

---

## Checklist pós-execução

- [ ] Rodar pasta **Instance** + **Send Message → Text** contra servidor real
- [ ] Salvar fixtures `spec/fixtures/evolution_go/`
- [ ] Confirmar `data.Info.ID` no send text response
- [ ] Confirmar webhook `MESSAGE` inbound
- [ ] Atualizar [evolution-target-version.txt](./evolution-target-version.txt)

---

## Comparação collections

| Collection | URL | Provider fork |
|------------|-----|---------------|
| **Evolution GO** | [nk736ze/evolution-go](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go) | `evolution_go` |
| Evolution API v2.3 | [nm0wqgt/evolution-api-v2-3](https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3) | `evolution` |

**Não misturar** variáveis nem paths entre collections.
