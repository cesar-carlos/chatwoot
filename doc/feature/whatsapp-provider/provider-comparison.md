# Comparação de providers alternativos

Notas de alto nível sobre gateways não oficiais comuns e como cada um se encaixa no Chatwoot. **Não substitui** a documentação oficial de cada fornecedor — validar endpoints antes de implementar.

**Relacionados:** [feature-mapping.md](./feature-mapping.md) · [implementation-decision-tree.md](./implementation-decision-tree.md) · [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md)

---

## Visão geral

| Provider | Modelo | Sessão | Webhooks | Templates WABA | Grupos | Voz |
|----------|--------|--------|----------|----------------|--------|-----|
| **Meta Cloud API** | Oficial BSP | Token OAuth | `entry/changes/value` | ✅ Aprovados | ❌ individual | ✅ EE Calling API |
| **360dialog** (`default`) | BSP oficial | API key | Flat Meta-like | ✅ Sync BSP | ❌ | ❌ |
| **Evolution API** | Self-host / SaaS | QR + instance | Por evento (`MESSAGES_UPSERT`, …) | ❌ (modo Baileys) | ✅ | ⚠️ experimental |
| **Z-API** | SaaS | QR + instance | 4 URLs (receive, delivery, status, disconnected) | ❌ | ✅ | ❌ documentado |
| **NotificaMe** | SaaS BR | API + credenciais | Proprietário | ❌ | ⚠️ | ❌ |
| **Baileys/WPPConnect** (genérico) | Self-host | QR | Variável por wrapper | ❌ | ✅ | ⚠️ lib-level |

---

## Evolution API

**Site/docs:** [docs.evolutionfoundation.com.br](https://docs.evolutionfoundation.com.br/en/evolution-api) · GitHub: `evolution-foundation/evolution-api`

### O que expõe

- **REST** com auth `apikey` header (global ou por instância)
- **Instâncias** multi-tenant: `instanceName` no path
- **Modos:** Baileys (WhatsApp Web) **ou** Meta Cloud API na mesma plataforma
- **Webhooks** configuráveis por instância: `MESSAGES_UPSERT`, `MESSAGES_UPDATE`, `CONNECTION_UPDATE`, `QRCODE_UPDATED`, etc.
- **Envio:** `POST /message/sendText/{instanceName}`, mídia, botões, listas (versão-dependent)
- **Integração nativa Chatwoot** na Evolution — útil para referência, mas o fork deve manter adapter próprio em `custom/`

### Formato típico (Baileys mode)

**Envio texto:**

```http
POST /message/sendText/my-instance
apikey: <key>
{ "number": "5511999999999", "textMessage": { "text": "Olá" } }
```

**Webhook `MESSAGES_UPSERT`:** payload com `data.key`, `data.message`, `data.pushName` — **não** é `contacts` + `messages` Meta.

### Paridade vs Cloud API

| Feature | Evolution (Baileys) |
|---------|---------------------|
| Texto livre anytime | ✅ |
| Templates Meta | ❌ (use texto ou modo Cloud na Evolution) |
| Status sent/delivered/read | ✅ via `MESSAGES_UPDATE` |
| Mídia | ✅ URL/base64 — normalizar download |
| Interativos | ⚠️ API própria, mapear para `input_select` Chatwoot |
| Reply/quote | ✅ campo `quoted` no send |
| Typing | ⚠️ depende versão |
| Chamadas | ⚠️ não contrato estável — validar antes |

### Notas para Chatwoot

- **Piloto recomendado** para fork: comunidade ativa, Docker, documentação REST
- Normalizer: `MESSAGES_UPSERT` → `{ contacts:, messages: }` flat
- `provider_config`: `base_url`, `api_key`, `instance_name`
- Conexão: polling `CONNECTION_UPDATE` + exibir QR de `QRCODE_UPDATED`
- **Cuidado:** Evolution pode rodar em modo Cloud — não confundir com provider não oficial

---

## Z-API

**Site/docs:** [developer.z-api.io](https://developer.z-api.io/en/quickstart/introduction)

### O que expõe

- **REST** SaaS com `instanceId` + token por instância
- **Fila interna** de envio — retorna ID imediato, entrega assíncrona
- **4 webhooks HTTPS obrigatórios:**
  - **Receive** — mensagens recebidas (e opcionalmente enviadas por você)
  - **Delivery** — mensagem aceita pelo WhatsApp
  - **Status** — `SENT`, `RECEIVED`, `READ`, `PLAYED`
  - **Disconnected** — perda de sessão
- **Não armazena mensagens** — mídia em storage Z-API por 30 dias

### Formato típico

**Status webhook:**

```json
{
  "instanceId": "instance.id",
  "status": "READ",
  "ids": ["999999999999999999999"],
  "phone": "5544999999999",
  "type": "MessageStatusCallback",
  "isGroup": false
}
```

### Paridade vs Cloud API

| Feature | Z-API |
|---------|-------|
| Texto | ✅ |
| Mídia | ✅ URLs temporárias 30d |
| Templates | ❌ |
| Interativos | ✅ botões, listas, CTA |
| Grupos | ✅ (Chatwoot não modela) |
| Rate limit API | Sem limite declarado — risco ban WhatsApp |
| Chamadas | ❌ não na doc pública |

### Notas para Chatwoot

- **4 rotas webhook** ou **1 rota multiplexada** por `type` no JSON
- Mapear `MessageStatusCallback` → `statuses[]` flat
- `source_id` = `messageId` / `ids[0]`
- `provider_config`: `instance_id`, `instance_token`, `client_token` (conforme doc)
- Bom para **SaaS gerenciado**; menos controle que Evolution self-host

---

## Padrão genérico Baileys gateway

Aplica-se a WPPConnect, whatsapp-web.js wrappers, gateways CPaaS custom.

### Arquitetura típica

```mermaid
flowchart LR
  CW[Chatwoot] -->|REST send| GW[Gateway Node.js]
  GW -->|Baileys protocol| WA[WhatsApp]
  WA -->|events| GW
  GW -->|POST webhook| CW
```

### Contrato mínimo esperado

| Operação | REST | Webhook |
|----------|------|---------|
| Enviar texto | `POST /send` ou `/message` | — |
| Enviar mídia | `POST` multipart ou URL | — |
| Receber mensagem | — | evento `message` / `messages.upsert` |
| Status | — | evento `message.ack` / `status` |
| Sessão | `GET /status`, `GET /qr` | evento `connection` |

### Variações comuns

- **IDs:** `wamid`, `key.id`, UUID local — normalizar para `source_id` string
- **JIDs:** `5511999999999@s.whatsapp.net`, LID — strip sufixo para `ContactInbox#source_id`
- **Mídia:** base64 inline, URL criptografada, ou relay via gateway
- **Grupos:** `@g.us` — Chatwoot trata como contato individual hoje; **ignorar ou filtrar** no MVP

### Adapter pattern no fork

```
Custom::Whatsapp::Providers::GenericGatewayService < Whatsapp::Providers::BaseService
Custom::Whatsapp::Webhooks::GenericNormalizer
```

Parametrizar por `provider_config['adapter']` se múltiplos gateways compartilharem código.

---

## NotificaMe (fork BR)

Plano detalhado em [notificame-whatsapp-integration/plano-geral.md](../notificame-whatsapp-integration/plano-geral.md).

| Aspecto | Nota |
|---------|------|
| Provider key sugerido | `notificame` |
| Escopo | Texto, mídia, interativos, reply, typing, saúde, bloqueio |
| Estratégia | Idêntica: `Channel::Whatsapp` + service + normalizer em `custom/` |
| Doc API | https://app.notificame.com.br/docs/ |

NotificaMe é **referência de implementação já planejada** neste fork — reutilizar fases e matriz de endpoints.

---

## Matriz de escolha rápida

| Critério | Evolution | Z-API | NotificaMe | Self-host Baileys |
|----------|-----------|-------|------------|-------------------|
| Self-host / controle | ✅ | ❌ SaaS | ❌ SaaS | ✅ |
| Doc REST estável | ✅ boa | ✅ boa | ✅ (fork) | ⚠️ varia |
| Setup Chatwoot existente | Integração nativa (referência) | — | Plano no fork | — |
| Interativos | ⚠️ | ✅ | ✅ planejado | ⚠️ |
| Ops (QR, reconnect) | Médio | Baixo (SaaS) | Baixo | Alto |
| Risco ToS / ban | Alto | Alto | Alto | Alto |

**Recomendação:** escolher **um piloto** (Evolution self-host **ou** NotificaMe se já contratado), congelar contrato webhook, implementar MVP texto+status antes de mídia.

---

## O que desaparece vs API oficial (todos os não oficiais)

Ver [official-vs-unofficial-restrictions.md](./official-vs-unofficial-restrictions.md). Resumo:

- Templates aprovados, janela 24h **na API** (Chatwoot ainda pode impor)
- Embedded Signup, WABA health, quality rating
- Campanhas/CSAT cloud
- Calling API Meta + `call_permission_request`
- SLA e suporte Meta

**Permanece:** risco de ban, instabilidade de sessão, compliance LGPD/gravação.
