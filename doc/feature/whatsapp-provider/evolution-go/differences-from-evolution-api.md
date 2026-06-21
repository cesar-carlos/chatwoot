# Diferenças — Evolution Go vs Evolution API (Node)

A documentação oficial afirma que ambos compartilham **"API contract REST (compatible)"** ([evo-nexus/integrations/evolution-go](https://docs.evolutionfoundation.com.br/en/evo-nexus/integrations/evolution-go)). Na prática, o levantamento jun/2026 mostra **divergências significativas** que impedem reusar o adapter `evolution` sem camada de abstração.

**Conclusão:** provider **`evolution_go`** separado no fork.

---

## Visão geral

| Aspecto | Evolution API (Node) | Evolution Go |
|---------|---------------------|--------------|
| Linguagem | Node.js / TypeScript | Go 1.24+ |
| Protocolo WhatsApp | Baileys (WhatsApp Web) | [whatsmeow](https://github.com/tulir/whatsmeow) |
| Provider key fork | `evolution` | `evolution_go` |
| Integração Chatwoot nativa | ✅ `/chatwoot/set` (desabilitar no fork) | ❌ Não existe |
| Licença | v2.4.0+ comercial | Ativação Magic Link obrigatória |
| Banco | Prisma (opcional) | PostgreSQL **obrigatório** (auth + users) |
| Swagger | OpenAPI externo | `{base_url}/swagger/index.html` |
| Postman | [v2.3.*](https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3) | [evolution-go](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go) |

---

## Autenticação

| Evolution API | Evolution Go |
|---------------|--------------|
| Header `apikey` — global ou por instância (`hash` do create) | **Duas chaves:** `GLOBAL_API_KEY` (admin) + **token por instância** |
| `instanceName` no path da maioria das rotas | Instância identificada pelo **token no header** `apikey` |
| Create retorna `hash` → `provider_config.api_key` | Create retorna `data.token` → `provider_config.instance_token` |

**Impacto no fork:**

- Wizard precisa de `global_api_key` (admin) **e** `instance_token` (operações da instância)
- Ou: operador cria instância manualmente no painel Go e cola token no wizard

---

## Rotas — lifecycle instância

| Operação | Evolution API | Evolution Go |
|----------|---------------|--------------|
| Criar | `POST /instance/create` body `instanceName` | `POST /instance/create` body **`name`** + `token` |
| Conectar | `GET /instance/connect/:instanceName` | `POST /instance/connect` (token no header) |
| QR | Via connect ou webhook `QRCODE_UPDATED` | `GET /instance/qr` (header token) |
| Pairing code | Query `?number=` no connect | `POST /instance/pair` body `{ phone }` |
| Status | `GET /instance/connectionState/:instanceName` | `GET /instance/status` (header token) |
| Listar | `GET /instance/fetchInstances` | `GET /instance/all` (global key) |
| Delete | `DELETE /instance/delete/:instanceName` | `DELETE /instance/:name` ou equivalente Postman |
| Restart | `POST /instance/restart/:instanceName` | Validar no Postman — pode não existir |
| Webhook config | `POST /webhook/set/:instanceName` | **`POST /instance/connect`** body `webhookUrl` + `subscribe` |
| Settings | `POST /settings/set/:instanceName` | `POST /instance/:id/advanced-settings` |
| Proxy | `POST /proxy/set/:instanceName` | `proxy` no body do create ou advanced-settings |

---

## Rotas — mensagens

| Operação | Evolution API | Evolution Go |
|----------|---------------|--------------|
| Texto | `POST /message/sendText/:instanceName` | **`POST /send/text`** (OpenAPI oficial) |
| Mídia | `POST /message/sendMedia/:instanceName` | **`POST /send/media`** |
| Body texto | `{ number, text }` ou `{ number, textMessage: { text } }` | `{ number, text }` |
| Resposta | `key.id` (messageRaw Baileys) | **`data.Info.ID`** (whatsmeow PascalCase) |

> **Risco resolvido (jun/2026):** OpenAPI oficial confirma **`POST /send/text`** — não existe `/message/sendText`.

---

## Webhooks — nomes de eventos

| Evolution API | Evolution Go | Ação Chatwoot |
|---------------|--------------|---------------|
| `MESSAGES_UPSERT` | **`MESSAGE`** | Inbound texto/mídia |
| `MESSAGES_UPDATE` | **`READ_RECEIPT`** (parcial) | Status delivered/read |
| `CONNECTION_UPDATE` | **`CONNECTION`** | `connection_status` |
| `QRCODE_UPDATED` | **`QRCODE`** | Exibir QR no wizard |
| `SEND_MESSAGE` | Implícito em `MESSAGE` com `fromMe: true` | Filtrar echo |
| — | `PRESENCE`, `CHAT_PRESENCE` | Ignorar MVP |
| — | `GROUP`, `GROUP_UPDATE` | Ignorar se `ignore_groups: true` |
| — | `CALL` | Fase voz separada |
| — | `HISTORY_SYNC` | Fase import |

**Envelope comum (ambos):**

```json
{
  "event": "MESSAGE",
  "instance": "minha-instancia",
  "data": { "key": { ... }, "message": { ... } }
}
```

Evolution API adiciona `apikey`, `destination`, `date_time`, `sender` no envelope — Evolution Go **pode não enviar** `apikey` no body ([events-system.md](https://github.com/evolution-foundation/evolution-go/blob/main/docs/wiki/recursos-avancados/events-system.md)).

---

## Formato de resposta HTTP

| Evolution API | Evolution Go |
|---------------|--------------|
| Objeto direto ou `{ instance, hash, qrcode }` | Wrapper `{ success, message, data }` ou `{ message: "success", data: { ... } }` |
| Erros variados | `{ success: false, error: { code, message }, meta: { ... } }` |

`ApiClient` do fork deve normalizar respostas antes de consumir campos.

---

## O que pode ser reutilizado no fork

| Componente | Reuso |
|------------|-------|
| Infra Fase 0 (registry, prepends) | ✅ Idêntico |
| `MessageWindowService` bypass | ✅ Idêntico |
| Lógica normalizer `data.key` / `remoteJid` | ✅ ~80% — payload whatsmeow ≈ Baileys |
| Filtros `@g.us`, `fromMe`, `status@broadcast` | ✅ Idêntico |
| `EvolutionService` / `ApiClient` / rotas webhook | ❌ Paths, auth, eventos diferentes |
| Wizard Vue | ⚠️ Layout similar; campos e polling diferentes |
| Fixtures `spec/fixtures/evolution/` | ❌ Criar `spec/fixtures/evolution_go/` |

---

## Matriz de decisão para implementadores

| Pergunta | Resposta |
|----------|----------|
| Posso usar o mesmo `ApiClient`? | Não — criar `EvolutionGo::ApiClient` |
| Posso usar o mesmo normalizer? | Base similar; mapear `MESSAGE` → flat, não `MESSAGES_UPSERT` |
| Mesma rota webhook? | Não — `POST /webhooks/evolution_go/:instance_name` |
| Mesmo `provider_config`? | Similar; adicionar `global_api_key`, renomear `api_key` → `instance_token` |
| Implementar antes ou depois de `evolution`? | Independente; compartilham só Fase 0 |
