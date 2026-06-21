# Plano de implementação — Provider Evolution Go

Plano concreto para `provider: 'evolution_go'` no fork Chatwoot. Alinhado com [../implementation-plan-second-whatsapp-provider.md](../implementation-plan-second-whatsapp-provider.md).

**Pré-requisitos:** [differences-from-evolution-api.md](./differences-from-evolution-api.md) · [validation-checklist.md](./validation-checklist.md) · [../gaps-and-blockers.md](../gaps-and-blockers.md)

**Dependência:** Fase 0 compartilhada com `evolution` (registry) — providers independentes a partir da Fase 1.

---

## Visão da arquitetura alvo

```mermaid
flowchart TB
  subgraph chatwoot_fork["Chatwoot fork (custom/)"]
    WIZ[Vue wizard Evolution Go]
    EGS[EvolutionGoService]
    CS[EvolutionGo ConnectionService]
    AC[EvolutionGo ApiClient]
    NORM[EvolutionGoNormalizer]
    REG[MessagingProvider::Registry]
    PRE1[prepend Channel::Whatsapp]
    PRE2[prepend WhatsappEventsJob]
    PRE3[prepend MessageWindowService]
  end

  subgraph evogo["Evolution Go"]
    INST[/instance/*]
    SEND[/send/*]
    CONN[connect + webhook inline]
  end

  WIZ --> CS
  CS --> AC --> INST
  CS --> CONN
  REG --> EGS --> AC --> SEND
  PRE1 --> REG
  evogo -->|MESSAGE| PRE2 --> NORM --> IncomingMessageService
  EGS --> SendOnWhatsappService
```

---

## Fase 0 — Infraestrutura (compartilhada)

Se `evolution` ainda não implementou Fase 0, fazer uma vez:

| # | Entrega | Local |
|---|---------|-------|
| 0.1 | `# FORK:` `PROVIDERS` inclui `evolution_go` | `app/models/channel/whatsapp.rb` |
| 0.2 | Registry register `evolution_go` | `custom/config/initializers/messaging_provider_registry.rb` |
| 0.3 | Capability `unlimited_session: true` | `custom/lib/messaging_provider/capabilities.rb` |
| 0.4 | Prepend `MessageWindowService` | `custom/app/services/custom/conversations/message_window_service.rb` |

**Critério:** `provider: 'evolution_go'` persiste; cloud inalterado.

---

## Fase 1 — MVP texto + conexão QR

**Pré-requisito:** [validation-checklist.md](./validation-checklist.md) completo

### Backend

| # | Classe | Responsabilidade |
|---|--------|------------------|
| 1.1 | `Custom::Whatsapp::EvolutionGo::ApiClient` | HTTP; unwrap `{ data }`; dual auth keys |
| 1.2 | `Custom::Whatsapp::EvolutionGo::ConnectionService` | create, connect (webhook), qr, status, ActionCable |
| 1.3 | `Custom::Whatsapp::Providers::EvolutionGoService` | `send_message`, `process_response` |
| 1.4 | `Custom::Whatsapp::Webhooks::EvolutionGoNormalizer` | `MESSAGE` → flat |
| 1.5 | Rota `POST /webhooks/evolution_go/:instance_name` | |
| 1.6 | `Custom::Webhooks::EvolutionGoController` | Auth `?token=` + enqueue |

### ConnectionService — fluxo criação inbox

```
1. POST /instance/create (global key) → persist instance_token, instance_id
2. Gerar webhook_secret no Chatwoot
3. POST /instance/connect (instance token)
   - webhookUrl com ?token=webhook_secret
   - subscribe: MESSAGE, CONNECTION, QRCODE
4. GET /instance/qr OU webhook QRCODE
5. Poll GET /instance/status até connected + loggedIn
6. Extrair myJid → channel.phone_number
7. Broadcast ActionCable evolution_go:connection:{inbox_id}
```

### Frontend

| # | Entrega |
|---|---------|
| 1.7 | Card "Evolution Go" em `Whatsapp.vue` |
| 1.8 | Wizard: base_url, global_api_key, instance_name; proxy opcional |
| 1.9 | Step QR — ActionCable + polling |
| 1.10 | `isEvolutionGoWhatsAppChannel` em `useInbox.js` |

### Critérios de done

- [ ] [validation-checklist.md](./validation-checklist.md) completo
- [ ] Inbox `provider: 'evolution_go'`
- [ ] QR conecta; `connection_status` → `open`
- [ ] Inbound texto → conversa
- [ ] Outbound texto → `source_id` = `key.id`
- [ ] Sem janela 24h
- [ ] `evolution` e cloud inalterados (se já existirem)

**Estimativa:** 2–3 semanas (inclui spike Postman + path send/text)

---

## Fase 2 — Mídia, READ_RECEIPT, settings

| # | Item |
|---|------|
| 2.1 | `send_attachment_message` → `/send/media` |
| 2.2 | Mídia inbound no normalizer |
| 2.3 | `READ_RECEIPT` → statuses |
| 2.4 | Reply/quote no send |
| 2.5 | `POST /instance/:id/advanced-settings` sync |
| 2.6 | Proxy no create/settings |

---

## Fase 3 — Interativos e operação

| # | Item |
|---|------|
| 3.1 | Poll, location, contact, sticker |
| 3.2 | Health badge via `/instance/status` |
| 3.3 | Alerta desconexão (`CONNECTION`) |
| 3.4 | Fluxo reconnect |

---

## Fase 4 — Import histórico

| # | Item |
|---|------|
| 4.1 | `HISTORY_SYNC` webhook + `/chat/history-sync-request` |

---

## Arquivos fork — checklist

```
custom/
├── app/services/custom/whatsapp/
│   ├── evolution_go/
│   │   ├── api_client.rb
│   │   └── connection_service.rb
│   ├── providers/evolution_go_service.rb
│   └── webhooks/evolution_go_normalizer.rb
├── app/controllers/custom/webhooks/evolution_go_controller.rb
└── app/javascript/dashboard/... (wizard Evolution Go)
```

### Upstream mínimo (`# FORK:`)

| Arquivo | Mudança |
|---------|---------|
| `app/models/channel/whatsapp.rb` | `PROVIDERS` + `'evolution_go'` |
| `config/routes.rb` | `/webhooks/evolution_go/:instance_name` |
| `Whatsapp.vue` | Import card Evolution Go |

---

## Riscos e mitigações

| Risco | Mitigação |
|-------|-----------|
| Paths `/send/text` vs `/message/sendText` | Spike Postman; fallback no ApiClient |
| Docs "API compatible" enganosa | Provider separado; [differences-from-evolution-api.md](./differences-from-evolution-api.md) |
| Sem `apikey` no webhook | Auth por `?token=` |
| Licença Go obrigatória | Documentar; operador responsável |
| Confusão com `evolution` | UI labels distintos; provider keys distintos |

---

## Ordem recomendada

```
validation-checklist + Postman spike → fixtures
Fase 0 (se necessário) → ApiClient → ConnectionService
→ EvolutionGoService → webhook + Normalizer → wizard → Fase 1 done
```
