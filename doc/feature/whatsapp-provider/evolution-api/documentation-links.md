# Links da documentação Evolution API — revisão jun/2026

Índice verificado via [llms.txt oficial](https://docs.evolutionfoundation.com.br/llms.txt) e fetch das páginas principais.

**Site oficial atual:** https://docs.evolutionfoundation.com.br  
**Índice completo (máquina):** https://docs.evolutionfoundation.com.br/llms.txt  
**OpenAPI JSON:** https://docs.evolutionfoundation.com.br/api-reference/openapi.json

**Postman (validação manual v2.3):**

| Recurso | URL |
|---------|-----|
| Collection v2.3.* (agenciadgcode) | https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3 |
| Postman oficial (badge README Evolution) | https://evolution-api.com/postman |
| Validação endpoint a endpoint (fork) | [postman-validation.md](./postman-validation.md) |

---

## URLs oficiais vs legadas

| URL | Status | Notas |
|-----|--------|-------|
| https://docs.evolutionfoundation.com.br | ✅ **Oficial** | Documentação Evolution Foundation (jun/2026) |
| https://evolutionfoundation.com.br | ✅ Site | Comunidade, suporte |
| https://github.com/evolution-foundation/evolution-api | ✅ Repositório | Organização oficial desde mai/2026 |
| https://github.com/EvolutionAPI/evolution-api | ⚠️ Legado | Redireciona para `evolution-foundation` — **não usar** em docs novas |
| https://doc.evolution-api.com | ⚠️ Legado | Citado em posts antigos — **não usar** |
| https://evolutionapi-evolution-api-90.mintlify.app | ⚠️ Legado | Mintlify antigo — **não usar** |

**Regra:** preferir sempre `docs.evolutionfoundation.com.br/evolution-api/...` sem sufixo `.md` nas URLs humanas.

---

## Índice rápido — Evolution API (provider Chatwoot)

### Hub e instalação

| Tópico | URL |
|--------|-----|
| Evolution API (hub) | https://docs.evolutionfoundation.com.br/evolution-api |
| Instalação | https://docs.evolutionfoundation.com.br/evolution-api/installation |
| Docker | https://docs.evolutionfoundation.com.br/evolution-api/install/docker |
| Easypanel | https://docs.evolutionfoundation.com.br/evolution-api/install/easypanel |
| SetupOrion | https://docs.evolutionfoundation.com.br/evolution-api/install/setup-orion |
| NVM | https://docs.evolutionfoundation.com.br/evolution-api/install/nvm |
| Nginx + SSL | https://docs.evolutionfoundation.com.br/evolution-api/install/nginx |
| Atualização | https://docs.evolutionfoundation.com.br/evolution-api/updates |
| Licenciamento (2.4.0+) | https://docs.evolutionfoundation.com.br/licensing |

### Configuração

| Tópico | URL |
|--------|-----|
| Variáveis de ambiente | https://docs.evolutionfoundation.com.br/evolution-api/configuration/env |
| Webhooks (guia) | https://docs.evolutionfoundation.com.br/evolution-api/configuration/webhooks |
| Recursos disponíveis | https://docs.evolutionfoundation.com.br/evolution-api/configuration/available-resources |
| Requisitos DB | https://docs.evolutionfoundation.com.br/evolution-api/requirements/database |
| Requisitos Redis | https://docs.evolutionfoundation.com.br/evolution-api/requirements/redis |

### Integração Chatwoot (Evolution → CW — legado)

| Tópico | URL |
|--------|-----|
| **Chatwoot integration** | https://docs.evolutionfoundation.com.br/evolution-api/integrations/chatwoot |

> Documenta `/chatwoot/set`, `instance/create` com campos `chatwoot*`, e parâmetros `signMsg`, `ignoreJids`, etc.  
> **Provider nativo no fork não usa esta integração** — mas é referência de regras de negócio.

### Instância e conexão

| Tópico | URL | Método (código local) |
|--------|-----|----------------------|
| Criar instância | https://docs.evolutionfoundation.com.br/evolution-api/create-instance | `POST /instance/create` |
| Conectar (QR) | https://docs.evolutionfoundation.com.br/evolution-api/connect-instance | `GET /instance/connect/:instanceName` |
| Estado conexão | https://docs.evolutionfoundation.com.br/evolution-api/get-connection-state | `GET /instance/connectionState/:instanceName` |
| Listar instâncias | https://docs.evolutionfoundation.com.br/evolution-api/fetch-all-instances | `GET /instance/fetchInstances` |
| Logout | https://docs.evolutionfoundation.com.br/evolution-api/logout-instance | `DELETE /instance/logout/:instanceName` |
| Reiniciar | https://docs.evolutionfoundation.com.br/evolution-api/restart-instance | `POST /instance/restart/:instanceName` |
| Deletar | https://docs.evolutionfoundation.com.br/evolution-api/delete-instance | `DELETE /instance/delete/:instanceName` |
| Presença | https://docs.evolutionfoundation.com.br/evolution-api/set-presence | `POST /instance/setPresence/:instanceName` |

### Settings, proxy, webhook

| Tópico | URL | Método |
|--------|-----|--------|
| Get settings | https://docs.evolutionfoundation.com.br/evolution-api/get-settings | `GET /settings/find/:instanceName` |
| Set settings | https://docs.evolutionfoundation.com.br/evolution-api/set-settings | `POST /settings/set/:instanceName` |
| Get proxy | https://docs.evolutionfoundation.com.br/evolution-api/get-proxy | `GET /proxy/find/:instanceName` |
| Set proxy | https://docs.evolutionfoundation.com.br/evolution-api/set-proxy | `POST /proxy/set/:instanceName` |
| Get webhook | https://docs.evolutionfoundation.com.br/evolution-api/get-webhook | `GET /webhook/find/:instanceName` |
| Set webhook | https://docs.evolutionfoundation.com.br/evolution-api/set-webhook | `POST /webhook/set/:instanceName` |
| Set WebSocket | https://docs.evolutionfoundation.com.br/evolution-api/set-websocket | `POST /websocket/set/:instanceName` |

### Mensagens (outbound)

| Tópico | URL | Método |
|--------|-----|--------|
| Texto | https://docs.evolutionfoundation.com.br/evolution-api/send-text-message | `POST /message/sendText/:instanceName` |
| Mídia | https://docs.evolutionfoundation.com.br/evolution-api/send-media-message | `POST /message/sendMedia/:instanceName` |
| Botões | https://docs.evolutionfoundation.com.br/evolution-api/send-buttons | `POST /message/sendButtons/:instanceName` |
| Lista | https://docs.evolutionfoundation.com.br/evolution-api/send-list | `POST /message/sendList/:instanceName` |
| Localização | https://docs.evolutionfoundation.com.br/evolution-api/send-location | `POST /message/sendLocation/:instanceName` |
| Contato | https://docs.evolutionfoundation.com.br/evolution-api/send-contact | `POST /message/sendContact/:instanceName` |
| Reação | https://docs.evolutionfoundation.com.br/evolution-api/send-reaction | `POST /message/sendReaction/:instanceName` |
| Poll | https://docs.evolutionfoundation.com.br/evolution-api/send-poll | `POST /message/sendPoll/:instanceName` |
| Template | https://docs.evolutionfoundation.com.br/evolution-api/send-template-message | `POST /message/sendTemplate/:instanceName` |

### Chat (histórico, leitura)

| Tópico | URL | Método |
|--------|-----|--------|
| Find chats | https://docs.evolutionfoundation.com.br/evolution-api/find-chats | `POST /chat/findChats/:instanceName` |
| Find contacts | https://docs.evolutionfoundation.com.br/evolution-api/find-contacts | `POST /chat/findContacts/:instanceName` |
| Find messages | https://docs.evolutionfoundation.com.br/evolution-api/find-messages | `POST /chat/findMessages/:instanceName` |
| Mark as read | https://docs.evolutionfoundation.com.br/evolution-api/mark-message-as-read | `POST /chat/markMessageAsRead/:instanceName` |
| Archive chat | https://docs.evolutionfoundation.com.br/evolution-api/archive-chat | `POST /chat/archiveChat/:instanceName` |
| Check numbers | https://docs.evolutionfoundation.com.br/evolution-api/check-whatsapp-numbers | `POST /chat/whatsappNumbers/:instanceName` |

### Perfil, labels, grupos (fase posterior)

| Tópico | URL |
|--------|-----|
| Update profile name | https://docs.evolutionfoundation.com.br/evolution-api/update-profile-name |
| Update profile picture | https://docs.evolutionfoundation.com.br/evolution-api/update-profile-picture |
| Update profile status | https://docs.evolutionfoundation.com.br/evolution-api/update-profile-status |
| Get labels | https://docs.evolutionfoundation.com.br/evolution-api/get-labels |
| Handle label | https://docs.evolutionfoundation.com.br/evolution-api/handle-label |
| Create group | https://docs.evolutionfoundation.com.br/evolution-api/create-group |
| Get group info | https://docs.evolutionfoundation.com.br/evolution-api/get-group-info |

### Templates WABA (modo Cloud — fora do MVP Baileys)

| Tópico | URL |
|--------|-----|
| Find templates | https://docs.evolutionfoundation.com.br/evolution-api/find-templates |
| Create template | https://docs.evolutionfoundation.com.br/evolution-api/create-template |
| Edit template | https://docs.evolutionfoundation.com.br/evolution-api/edit-template |
| Delete template | https://docs.evolutionfoundation.com.br/evolution-api/delete-template |

### Chamadas

| Tópico | URL |
|--------|-----|
| Offer call | https://docs.evolutionfoundation.com.br/evolution-api/offer-call |

---

## OpenAPI specs (referência técnica)

| Spec | URL |
|------|-----|
| Instance | https://docs.evolutionfoundation.com.br/api-reference/openapi/Evolution-API/instance.yaml |
| Message | https://docs.evolutionfoundation.com.br/api-reference/openapi/Evolution-API/message.yaml |
| Settings | https://docs.evolutionfoundation.com.br/api-reference/openapi/Evolution-API/settings.yaml |
| Proxy | https://docs.evolutionfoundation.com.br/api-reference/openapi/Evolution-API/proxy.yaml |
| Events / Webhook | https://docs.evolutionfoundation.com.br/api-reference/openapi/Evolution-API/events.yaml |
| Chat | https://docs.evolutionfoundation.com.br/api-reference/openapi/Evolution-API/chat.yaml |
| General | https://docs.evolutionfoundation.com.br/api-reference/openapi/Evolution-API/general.yaml |

---

## Autenticação

Header em **todas** as requisições:

```http
apikey: {GLOBAL_API_KEY ou INSTANCE_TOKEN}
```

| Tópico | URL |
|--------|-----|
| Env `AUTHENTICATION_API_KEY` | [configuration/env](https://docs.evolutionfoundation.com.br/evolution-api/configuration/env) |
| Introdução APIs (plataforma) | https://docs.evolutionfoundation.com.br/api-reference/introduction |

- Global key: admin, todas instâncias
- Instance token: retornado em `POST /instance/create` como `hash`

---

## Variáveis de ambiente Chatwoot (servidor Evolution)

Documentadas em [configuration/env](https://docs.evolutionfoundation.com.br/evolution-api/configuration/env):

| Variável | Default doc | Mapeamento inbox fork |
|----------|-------------|----------------------|
| `CHATWOOT_ENABLED` | false | N/A — provider nativo |
| `CHATWOOT_MESSAGE_READ` | true | `mark_read_on_reply` |
| `CHATWOOT_MESSAGE_DELETE` | true | `sync_delete_to_whatsapp` |
| `CHATWOOT_IMPORT_DATABASE_CONNECTION_URI` | — | Import fase 4 (abordagem diferente) |
| `CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE` | true | Import mídia placeholder |
| `CHATWOOT_BOT_CONTACT` | (código local, não na doc env) | Substituído por UI wizard |

---

## Compatibilidade de versão

| Versão | Status (jun/2026) | Impacto no provider Chatwoot |
|--------|-------------------|------------------------------|
| **2.3.x** (ex.: 2.3.6 local, 2.3.7 stable) | Sem licença obrigatória | **Alvo recomendado** para MVP |
| **2.4.0+** | [Licença obrigatória](https://docs.evolutionfoundation.com.br/licensing) — endpoints de negócio retornam `503 LICENSE_REQUIRED` até ativar | Documentar no runbook de deploy; não assumir paridade com 2.3.x sem testes |
| **Doc `/updates`** | Ainda exemplifica Docker `evoapicloud/evolution-api:v2.1.1` | Ignorar tag antiga; seguir [releases](https://github.com/evolution-foundation/evolution-api/releases) |

**Fork local analisado:** `/root/evolution-api` → `package.json` **2.3.6**, remote `cesar-carlos/evolution-api`. Re-sync com `evolution-foundation/evolution-api` v2.3.7 antes de capturar fixtures reais.

**Congelar para Fase 1:** versão exata da imagem/binário + resultado do teste `sendText` e um `MESSAGES_UPSERT` real em `spec/fixtures/evolution/`.

---

## Discrepâncias: documentação vs código local (`/root/evolution-api`)

Validar na implementação contra a **versão real** do servidor Evolution em produção.

### 1. `sendText` — formato do body

| Fonte | Formato |
|-------|---------|
| **OpenAPI publicado** (docs) | `{ "number": "5511...", "textMessage": { "text": "Olá" } }` |
| **Código local** (`textMessageSchema`) | `{ "number": "5511...", "text": "Olá" }` |

O fork em `/root/evolution-api` usa campo **`text`** plano. Testar ambos se a API em produção for versão diferente.

### 2. Webhook — nomenclatura de campos

| Guia webhooks (prosa) | API `POST /webhook/set` (código) |
|-----------------------|----------------------------------|
| `webhook_by_events` | `webhook.byEvents` |
| `webhook_base64` | `webhook.base64` |

Usar formato do código (objeto `webhook` aninhado) — ver [api-reference.md](./api-reference.md).

### 3. `markMessageAsRead` — rota

| Doc slug | Rota real |
|----------|-----------|
| `mark-message-as-read` | `POST /chat/markMessageAsRead/:instanceName` (não `/message/...`) |

### 4. Integração Chatwoot — defaults

| Campo | Doc `/integrations/chatwoot` | Código `instance.controller.ts` |
|-------|------------------------------|--------------------------------|
| `importContacts` | exemplo: true | default create: **true** |
| `importMessages` | exemplo: true | default create: **true** |
| `daysLimitImportMessages` | exemplo: 2–3 | default create: **60** |
| `autoCreate` | true no set | true no create |

UI Evolution manager mostra defaults diferentes (7 dias, toggles off) — ver [implementation-analysis.md](./implementation-analysis.md).

### 5. `ignoreJids`

Documentado no schema Prisma e código; **não** listado na página oficial `/integrations/chatwoot` — mas existe no manager UI e em `ChatwootDto`.

### 6. Proxy — formato do body (`/proxy/set`)

| Fonte | Formato |
|-------|---------|
| **OpenAPI publicado** ([set-proxy](https://docs.evolutionfoundation.com.br/evolution-api/set-proxy)) | `proxyHost`, `proxyPort`, `proxyProtocol`, `proxyUsername`, `proxyPassword` |
| **Código local** (`proxy.schema.ts`) | `host`, `port`, `protocol`, `username`, `password` |

`POST /instance/create` com proxy inline usa **`proxyHost`** etc. (`instance.schema.ts`) — diferente de `POST /proxy/set`. O `ApiClient` do fork deve mapear `provider_config` → formato correto por endpoint.

### 7. Proxy global (`.env` Evolution)

Variáveis no servidor Evolution (não no inbox Chatwoot):

| Variável | Uso |
|----------|-----|
| `PROXY_HOST` | Default global se instância não tiver proxy próprio |
| `PROXY_PORT` | Porta (default `80`) |
| `PROXY_PROTOCOL` | `http` / `https` / `socks4` / `socks5` |
| `PROXY_USERNAME` | Auth opcional |
| `PROXY_PASSWORD` | Auth opcional |

`channel.service.ts` → `loadProxy()`: carrega global primeiro; **sobrescreve** se registro Prisma da instância tiver `enabled: true`. Provider Chatwoot configura só proxy **por instância** via `POST /proxy/set`.

---

## Eventos webhook — referência cruzada

Lista completa: [configuration/webhooks](https://docs.evolutionfoundation.com.br/evolution-api/configuration/webhooks)

**MVP provider Chatwoot:**

```
MESSAGES_UPSERT, MESSAGES_UPDATE, CONNECTION_UPDATE, QRCODE_UPDATED
```

**Opcionais fase 2+:**

```
MESSAGES_DELETE, MESSAGES_EDITED, SEND_MESSAGE, CONTACTS_UPSERT, CALL
```

Envelope do POST: ver [webhook-events.md](./webhook-events.md).

---

## Links internos deste projeto

| Documento | Uso |
|-----------|-----|
| [api-reference.md](./api-reference.md) | Endpoints + payloads (alinhado ao código local) |
| [webhook-events.md](./webhook-events.md) | Normalizer inbound |
| [integrations/chatwoot (oficial)](https://docs.evolutionfoundation.com.br/evolution-api/integrations/chatwoot) | Regras legado Evolution→CW |
| [troubleshooting.md](./troubleshooting.md) | Operação e incidentes |
| [validation-checklist.md](./validation-checklist.md) | Spike pré Fase 1 |
| [migration-from-evolution-integration.md](./migration-from-evolution-integration.md) | Legado Evolution→CW |
| [implementation-analysis.md](./implementation-analysis.md) | Código Evolution vs provider |
| [inbox-business-rules.md](./inbox-business-rules.md) | Campos do inbox |

---

## Como manter atualizado

**Versão pinada:** [evolution-target-version.txt](./evolution-target-version.txt)

**Script de diff** (páginas novas no índice oficial):

```bash
./doc/feature/whatsapp-provider/evolution-api/sync-documentation-links.sh
```

Comandos manuais:

```bash
# Baixar índice completo
curl -s https://docs.evolutionfoundation.com.br/llms.txt

# Filtrar só Evolution API
curl -s https://docs.evolutionfoundation.com.br/llms.txt | rg 'evolution-api/'
```

Revisar este arquivo após sync upstream Evolution ou mudança de versão documentada (OpenAPI: **2.3.7**; stable GitHub: **2.3.7**; pin: [evolution-target-version.txt](./evolution-target-version.txt)).
