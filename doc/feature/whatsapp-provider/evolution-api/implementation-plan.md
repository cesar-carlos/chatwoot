# Plano de implementação — Provider Evolution

Plano concreto para `provider: 'evolution'` no fork Chatwoot. Alinhado com [../implementation-plan-second-whatsapp-provider.md](../implementation-plan-second-whatsapp-provider.md).

**Pré-requisitos gerais:** [../gaps-and-blockers.md](../gaps-and-blockers.md) · [../feature-mapping.md](../feature-mapping.md) · **[validation-checklist.md](./validation-checklist.md)** (spike manual antes de fechar Fase 1)

**Versão Evolution alvo:** [evolution-target-version.txt](./evolution-target-version.txt)

---

## Visão da arquitetura alvo

```mermaid
flowchart TB
  subgraph chatwoot_fork["Chatwoot fork (custom/)"]
    WIZ[Vue wizard Evolution]
    ES[EvolutionService]
    CS[ConnectionService]
    AC[ApiClient]
    NORM[EvolutionNormalizer]
    REG[MessagingProvider::Registry]
    PRE1[prepend Channel::Whatsapp]
    PRE2[prepend WhatsappEventsJob]
    PRE3[prepend MessageWindowService]
  end

  subgraph evolution["Evolution API"]
    INST[/instance/*]
    MSG[/message/*]
    WH[/webhook/set]
  end

  WIZ --> CS
  CS --> AC --> INST
  CS --> WH
  REG --> ES --> AC --> MSG
  PRE1 --> REG
  evolution -->|MESSAGES_UPSERT| PRE2 --> NORM --> IncomingMessageService
  ES --> SendOnWhatsappService
```

---

## Fase 0 — Infraestrutura (sem comportamento novo)

**Escopo:** registry + prepends; provider ainda não usável.

| # | Entrega | Local |
|---|---------|-------|
| 0.1 | `# FORK:` `PROVIDERS` inclui `evolution` | `app/models/channel/whatsapp.rb` |
| 0.2 | `MessagingProvider::Registry` | `custom/lib/messaging_provider/registry.rb` |
| 0.3 | Initializer register `evolution` | `custom/config/initializers/messaging_provider_registry.rb` |
| 0.4 | Prepend `provider_service` | `custom/app/models/custom/channel/whatsapp.rb` |
| 0.5 | Prepend `WhatsappEventsJob` (stub) | `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` |
| 0.6 | `Capabilities.evolution` → `unlimited_session: true` | `custom/lib/messaging_provider/capabilities.rb` |
| 0.7 | Prepend `MessageWindowService` → `nil` para evolution | `custom/app/services/custom/conversations/message_window_service.rb` |

**Critério de done:** specs do registry; `provider: 'evolution'` persiste; cloud e default inalterados.

**Doc pai:** [../implementation-plan-second-whatsapp-provider.md](../implementation-plan-second-whatsapp-provider.md) Fase 0

---

## Fase 1 — MVP texto + conexão QR + proxy opcional

**Escopo:** criar inbox, conectar via QR, receber e enviar **texto**; **proxy opcional no wizard**; regras de conversa mínimas (`lock_to_single_conversation`, defaults fork).

**Pré-requisito:** [validation-checklist.md](./validation-checklist.md) · defaults: [business-rules-adaptation.md](./business-rules-adaptation.md)

### Backend

| # | Classe | Responsabilidade |
|---|--------|------------------|
| 1.1 | `Custom::Whatsapp::Evolution::ApiClient` | HTTP para Evolution (`for_channel`) — ver [api-reference.md](./api-reference.md) |
| 1.2 | `Custom::Whatsapp::Evolution::ConnectionService` | Facade: QR, reconnect, status, delega provision/events |
| 1.2b | `Custom::Whatsapp::Evolution::Provisioner` | create, webhook, settings, proxy, disable legado |
| 1.2c | `Custom::Whatsapp::Evolution::ConnectionEvents` | `CONNECTION_UPDATE`, `QRCODE_UPDATED` + ActionCable |
| 1.2d | `Custom::Whatsapp::Evolution::EventNames` | Normaliza `messages.upsert` → `MESSAGES_UPSERT` |
| 1.3 | `Custom::Whatsapp::Providers::EvolutionService` | `send_message` (texto puro), `validate_provider_config?`, `process_response` |
| 1.4 | `Custom::Whatsapp::Webhooks::EvolutionNormalizer` | `MESSAGES_UPSERT` → flat; `Array.wrap(data)` |
| 1.5 | Rota webhook dedicada | `POST /webhooks/evolution/:instance_name` |
| 1.6 | `Webhooks::EvolutionController` | Auth + enqueue job (`EventNames` no payload) |

> **`Provisioner` / `ConnectionEvents`:** implementados jun/2026 — `ConnectionService` é facade; provisionamento remoto em `Provisioner`, handlers de conexão em `ConnectionEvents`.

### `EvolutionService` — MVP

```ruby
# send_message(phone, message)
# 1. POST /message/sendText/{instance_name} — texto puro (sem sign_msg no MVP)
#    { number: phone, text: body }
# 2. process_response → response.dig('key', 'id')
# Fase 2+: sign_msg, markdown, quoted, delay
```

### Filtros inbound MVP (hardcoded)

- `status@broadcast` → ignore
- JID termina `@g.us` → ignore
- `fromMe: true` → ignore
- LID → `remoteJidAlt` quando JID termina `@lid` ou `addressingMode: lid`

| 1.13 | `provider_config` defaults fork | Seed wizard com [business-rules-adaptation.md](./business-rules-adaptation.md) |
| 1.14 | Reabrir conversa `resolved` no inbound | ✅ `lock_to_single_conversation` + `Conversations::Resolver` + `Message#reopen_conversation` |

### `ConnectionService` — fluxo criação inbox

```
1. POST /instance/create (Baileys, qrcode: true, groupsIgnore: true, settings fork defaults)
2. Se proxy_enabled: POST /proxy/set (ou proxyHost inline no create) — bloquear se 400 Invalid proxy
3. POST /webhook/set → https://{FRONTEND_URL}/webhooks/evolution/{instance_name}
4. GET /instance/connect → QR inicial
5. Poll connectionState OU webhook CONNECTION_UPDATE / QRCODE_UPDATED
6. Broadcast ActionCable evolution:connection:{inbox_id}
7. Obter phone_number do sender/state → salvar channel.phone_number
8. Garantir chatwoot.enabled = false na Evolution
```

### Frontend

| # | Entrega |
|---|---------|
| 1.7 | Card "Evolution API" em `Whatsapp.vue` (`// FORK:` import) |
| 1.8 | Wizard: conexão + **proxy colapsável** + defaults `provider_config` |
| 1.9 | Step QR — ActionCable + polling fallback ([decisions.md §17](./decisions.md)) |
| 1.10 | Settings inbox — conexão + badge status (abas completas Fase 2) |
| 1.11 | `isEvolutionWhatsAppChannel` em `useInbox.js` — ocultar features cloud-only |
| 1.12 | `api_key` masked no GET — [decisions.md §15](./decisions.md) |

**Campos UI Fase 2:** `sign_msg`, markdown, reject_call, read_messages, merge BR, editor `ignore_jids` — ver [business-rules-adaptation.md](./business-rules-adaptation.md).

### Critérios de done

- [x] [validation-checklist.md](./validation-checklist.md) completo (T0 REST + E2E local jun/2026)
- [x] Inbox criado com `provider: 'evolution'`
- [x] QR conecta e `connection_status` → `open`
- [x] Inbound texto → conversa no Chatwoot
- [x] Outbound texto → `source_id` = `key.id` da Evolution
- [x] Integração Chatwoot **desabilitada** na Evolution (com verificação `GET /chatwoot/find`)
- [x] Sem janela 24h (texto livre em conversa antiga)
- [x] Proxy opcional no wizard (set + validação Evolution)
- [x] Reabrir conversa resolvida no inbound — `lock_to_single_conversation` + Resolver + Message callback
- [x] `provider_config` com defaults [business-rules-adaptation.md](./business-rules-adaptation.md)

- [x] Cloud e 360dialog inalterados (regressão)

**Estimativa:** 2–2,5 semanas (proxy + reopen no escopo F1)

---

## Fase 2 — Mídia, status, settings completos

| # | Item | Referência |
|---|------|------------|
| 2.1 | `send_attachment_message` → `/message/sendMedia` | [api-reference.md](./api-reference.md) |
| 2.2 | Mídia inbound no normalizer | [webhook-events.md](./webhook-events.md) |
| 2.3 | `MESSAGES_UPDATE` → statuses | [webhook-events.md](./webhook-events.md) |
| 2.4 | Reply/quote (`quoted` no send + inbound context) | Evolution `SendTextDto.quoted` |
| 2.5 | Form settings: groups_ignore, read_messages, reject_call, etc. | [business-rules-adaptation.md](./business-rules-adaptation.md) |
| 2.5b | Proxy — editar em settings + restart sugerido | já no wizard F1 |
| 2.6 | Sync settings ao salvar inbox settings | `ConnectionService#sync_settings` |
| 2.7 | `sign_msg` / `sign_delimiter` no outbound | Portar lógica `receiveWebhook` Evolution |
| 2.8 | `ignore_jids` no normalizer | `eventWhatsapp` ref |
| 2.9 | `conversation_pending`; reabrir via `lock_to_single_conversation` | ✅ `IncomingMessageServiceHelpers` + `Custom::Message` prepend |

**Backend T1 (implementado):** 2.1, 2.2, 2.3, 2.4 (outbound quoted + inbound context), 2.7, 2.8 — ver `custom/app/services/custom/whatsapp/`.

### Critérios de done

- [x] Enviar/receber imagem e documento (backend — download via `getBase64FromMediaMessage`)
- [x] Status delivered/read mapeados
- [x] Proxy configurável no settings do inbox (`EvolutionSettingsPage.vue`)
- [x] Grupos ignorados quando `groups_ignore: true` (settings sync + filtro normalizer)

**Estimativa:** 2–4 semanas

---

## Fase 3 — Interativos e operação

| # | Item | Status |
|---|------|--------|
| 3.0 | `Provisioner` — create/webhook/settings (fluxos avançados multi-step) | ✅ básico |
| 3.1 | Botões/listas → `sendButtons` / `sendList` + mapear `input_select` | ✅ |
| 3.2 | Health: `connectionState` no settings ([decisions.md §18](./decisions.md)) | ✅ |
| 3.3 | Alerta desconexão (`CONNECTION_UPDATE` → `close`) | ✅ |
| 3.4 | Fluxo reconnect (QR novamente) | ✅ |
| 3.5 | `logout` / `restart` instance nos settings | ✅ |
| 3.6 | `merge_brazil_contacts` | ✅ |
| 3.7 | Reavaliar `EvolutionWebhookJob` dedicado se prepend causar regressão ([decisions.md §16](./decisions.md)) | ⏸️ deferido |

**Estimativa:** 2–3 semanas

---

## Fase 4 — Import histórico (opcional)

| # | Item |
|---|------|
| 4.1 | `import_contacts` via `findContacts` |
| 4.2 | `import_messages` via `findMessages` + `days_limit_import_messages` |

Substitui `chatwoot-import-helper.ts` da Evolution.

---

## Fase 5 — Voz

**Fora do escopo** deste provider de mensagens. Ver `doc/feature/whatsapp-voice/`.

---

## Arquivos fork — checklist

### `custom/` (novo)

```
custom/
├── lib/messaging_provider/
│   ├── registry.rb
│   └── capabilities.rb
├── config/initializers/messaging_provider_registry.rb
├── app/
│   ├── models/custom/channel/whatsapp.rb
│   ├── services/custom/
│   │   ├── whatsapp/providers/evolution_service.rb
│   │   ├── whatsapp/evolution/api_client.rb
│   │   ├── whatsapp/evolution/connection_service.rb
│   │   ├── whatsapp/webhooks/evolution_normalizer.rb
│   │   └── conversations/message_window_service.rb
│   ├── jobs/custom/webhooks/whatsapp_events_job.rb
│   └── controllers/custom/webhooks/evolution_controller.rb
└── app/javascript/dashboard/... (wizard Evolution)
```

### Upstream mínimo (`# FORK:`)

| Arquivo | Mudança |
|---------|---------|
| `app/models/channel/whatsapp.rb` | `PROVIDERS` + `'evolution'` |
| `config/routes.rb` | Rota `/webhooks/evolution/:instance_name` |
| `app/javascript/.../channels/Whatsapp.vue` | Import card Evolution |

---

## Ordem de implementação recomendada

```
validation-checklist (spike) → fixtures reais
Fase 0 → ApiClient → ConnectionService → EvolutionService (sendText)
      → Rota webhook + Normalizer (texto + Array.wrap) → Wizard mínimo → Fase 1 done
      → Settings UI + mídia + sign_msg → Fase 2 → Interativos + health → Fase 3
```

---

## Riscos e mitigações

| Risco | Mitigação |
|-------|-----------|
| Duplicação com integração Evolution CW | Documentar: nunca habilitar `/chatwoot/set` |
| LID / `remoteJidAlt` | Testar com contas LID; normalizer usa alt |
| `phone_number` UNIQUE no channel | Um inbox por número; documentar |
| Formato webhook diferente por versão Evolution | Congelar versão Evolution alvo; fixture JSON em `spec/fixtures/evolution/` |
| Echo `fromMe` duplica outbound | Filtrar no normalizer (hardcoded F1) |
| Regressão cloud/360dialog | Specs prepend job; ADR job dedicado Fase 3 |
| Migração legado duplica msgs | [migration-from-evolution-integration.md](./migration-from-evolution-integration.md) |

---

## Fixtures para specs

Criados em `spec/fixtures/evolution/` (templates sintéticos). Ver [spec/fixtures/evolution/README.md](../../../../spec/fixtures/evolution/README.md) — **substituir por capturas reais** do servidor Evolution antes de fechar Fase 1.

```
spec/fixtures/evolution/
├── messages_upsert_text.json
├── messages_upsert_batch.json
├── messages_upsert_text_normalized.json  # output esperado do normalizer
├── messages_upsert_image.json
├── messages_update_read.json
├── connection_update_open.json
├── qrcode_updated.json
└── send_text_response.json
```

## Decisões e contratos (pré-código)

| Documento | Conteúdo |
|-----------|----------|
| [decisions.md](./decisions.md) | Rota webhook, auth, sendText, source_id, grupos |
| [spec-design.md](./spec-design.md) | Interface pública de ApiClient, ConnectionService, EvolutionService, Normalizer |

---

## Links rápidos durante implementação

| Dúvida | Documento |
|--------|-----------|
| Como a Evolution implementou? (código) | [implementation-analysis.md](./implementation-analysis.md) |
| Qual regra de negócio / campo do inbox? | [inbox-business-rules.md](./inbox-business-rules.md) |
| Qual endpoint chamar? | [api-reference.md](./api-reference.md) |
| Formato do webhook? | [webhook-events.md](./webhook-events.md) |
| Decisão de rota/auth? | [decisions.md](./decisions.md) |
| Assinatura das classes? | [spec-design.md](./spec-design.md) |
| Campo do form ↔ API? | [provider-config-mapping.md](./provider-config-mapping.md) |
| O que a Evolution faz hoje? | [current-evolution-chatwoot-integration.md](./current-evolution-chatwoot-integration.md) |
| Migrar integração legada? | [migration-from-evolution-integration.md](./migration-from-evolution-integration.md) |
| Validar antes de merge? | [validation-checklist.md](./validation-checklist.md) |
| Problema em produção? | [troubleshooting.md](./troubleshooting.md) |
| Bloqueios no Chatwoot? | [../gaps-and-blockers.md](../gaps-and-blockers.md) |
| Proxy / operação | [api-reference.md §3](./api-reference.md), [decisions.md §19](./decisions.md), [implementation-analysis.md §17](./implementation-analysis.md) |
