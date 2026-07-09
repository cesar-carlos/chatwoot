# Plano de implementação — Provider Evolution Go

> **Nota (jul/2026):** Documento histórico de fases — ver [status.md](./status.md) para estado atual. Fases 0–4 implementadas; E2E e fixtures reais pendentes.

Integração `provider: 'evolution_go'` no fork Chatwoot. Alinhado com [../implementation-plan-second-whatsapp-provider.md](../implementation-plan-second-whatsapp-provider.md).

**Pré-requisitos:** [differences-from-evolution-api.md](./differences-from-evolution-api.md) · [decisions.md](./decisions.md) · [status.md](./status.md)

**Infra Evolution Go:** externa ao fork — operador fornece `base_url`, licença e chaves.

---

## Visão da arquitetura

```mermaid
flowchart TB
  subgraph chatwoot_fork["Chatwoot fork (custom/)"]
    WIZ[Vue wizard Evolution Go]
    EGS[EvolutionGoService]
    CS[EvolutionGo ConnectionService]
    AE[EvolutionGo ApiError]
    AC[EvolutionGo ApiClient]
    NORM[EvolutionGoNormalizer]
    REG[MessagingProvider::Registry]
    CTRL[EvolutionGoController]
    CH[EvolutionGoConnectionChannel AC]
    PRE[prepend WhatsappEventsJob]
    PRE3[prepend MessageWindowService]
  end

  subgraph evogo["Evolution Go (externo)"]
    INST[/instance/*]
    SEND[/send/*]
    CONN[connect + webhook inline]
  end

  WIZ --> CS
  CS --> AC --> INST
  CS -->|POST connect webhookUrl| CONN
  REG --> EGS --> AC --> SEND
  AC -->|raise| AE
  evogo -->|MESSAGE webhook| CTRL --> PRE
  PRE -->|MESSAGE| NORM --> IncomingMessageService
  PRE -->|CONNECTION/QRCODE| CS
  CS --> CH
  PRE3 --> REG
  EGS --> SendOnWhatsappService
```

---

## Fase 0 — Infraestrutura

| # | Entrega | Local |
|---|---------|-------|
| 0.1 | `# FORK:` `PROVIDERS` inclui `evolution_go` | `app/models/channel/whatsapp.rb` |
| 0.2 | Registry `evolution_go` (formato posicional — igual evolution node) | `custom/config/initializers/messaging_provider_registry.rb` |
| 0.3 | Capability `unlimited_session: true` | `custom/lib/messaging_provider/capabilities.rb` |
| 0.4 | Prepend `MessageWindowService` | `custom/app/services/custom/conversations/message_window_service.rb` |
| 0.5 | Rota + stub `EvolutionGoController` | `config/routes.rb`, `custom/app/controllers/webhooks/evolution_go_controller.rb` |
| 0.6 | Migration índice `instance_name` unique para `provider = 'evolution_go'` | `db/migrate/` |
| 0.7 | **Fix prepend evolution node:** mudar `return` → `return super(params)` no guard `unless channel` — evita descarte silencioso de envelopes Go ([decisions.md §27](./decisions.md)) | `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` |

> **0.7 é pré-requisito para testar 0.5** — sem o fix, o prepend node intercepta e descarta todos os eventos evolution_go. Ver [coordination-with-evolution-api.md](./coordination-with-evolution-api.md).

**Critério:** `provider: 'evolution_go'` persiste; cloud e evolution node inalterados; migration aplicada.

---

## Fase 1 — MVP texto + conexão QR

Contratos: [spec-design.md](./spec-design.md) · validação E2E: [validation-checklist.md](./validation-checklist.md)

### Backend

| # | Classe | Responsabilidade |
|---|--------|------------------|
| 1.1 | `Custom::Whatsapp::EvolutionGo::ApiError` | Exceção tipada (`status`, `body`, `user_message`) — ver [error-handling.md](./error-handling.md) |
| 1.2 | `Custom::Whatsapp::EvolutionGo::ApiClient` | HTTP; `unwrap { data }`; dual auth (global/instance); `dig_field` casing |
| 1.3 | `Custom::Whatsapp::EvolutionGo::ConnectionService` | `provision_new_inbox!`, `connect_existing!`, `handle_event`, `sync_phone_number!`, `reconnect!`, `broadcast_connection_event` |
| 1.4 | `Custom::Whatsapp::Providers::EvolutionGoService` | `send_message`, `process_response` → `data.Info.ID` |
| 1.5 | `Custom::Whatsapp::Webhooks::EvolutionGoNormalizer` | `MESSAGE` → flat Chatwoot; filtros `fromMe`/`@g.us`/`status@broadcast` |
| 1.6 | `Custom::Webhooks::EvolutionGoController` | `process_payload` com `evolution_go_instance_name:` (ADR §27) + `authenticate_webhook!` |
| 1.7 | Prepend `WhatsappEventsJob` evolution_go | `evolution_go_envelope?` por `evolution_go_instance_name` — não ambíguo com node |
| 1.8 | `EvolutionGoConnectionChannel` | ActionCable `evolution_go:connection:{inbox_id}` |

### Separação de responsabilidades

```
EvolutionGoController → Job prepend → dispatch_evolution_go_event
                                       ├── MESSAGE       → EvolutionGoNormalizer → IncomingMessageService
                                       ├── READ_RECEIPT  → statuses[] (Fase 2)
                                       ├── CONNECTION    → ConnectionService#handle_event → AC broadcast
                                       ├── QRCODE        → ConnectionService#handle_event → AC broadcast
                                       └── SEND_MESSAGE  → ignorar (echo outbound)
```

> ⚠️ **Isolamento de envelope (ADR §27):** `EvolutionGoController#sanitized_job_payload` injeta `evolution_go_instance_name:` e remove `instance` do payload bruto. Impede que o prepend evolution node intercepte eventos Go.

---

### ConnectionService — fluxo criação inbox

```
Modo A — Criar nova instância:
1. POST /instance/create (global_api_key) → salvar instance_token, instance_id, instance_name
2. Gerar webhook_token server-side
3. POST /instance/connect (instance_token)
   - webhookUrl: {FRONTEND_URL}/webhooks/evolution_go/{name}?token={webhook_token}
   - subscribe: ["MESSAGE", "CONNECTION", "QRCODE"]
4. GET /instance/qr → data.Qrcode (base64) para Step 3 wizard
5. Poll GET /instance/status a cada 3s até Connected + LoggedIn
6. Extrair JID → channel.phone_number (dig_field: jid, myJid, JID…)
7. Broadcast ActionCable evolution_go:connection:{inbox_id} → sucesso wizard

Modo B — Instância existente:
1. Operador informa instance_name + instance_token
2. Gerar webhook_token → connect (step 3 acima)
```

### Envio texto

```
POST /send/text
{ "number": "5511999999999", "text": "Olá!" }
→ source_id = response.dig('data', 'Info', 'ID') || response.dig('data', 'messageId')
```

### Frontend (wizard — 3 steps)

| # | Entrega |
|---|---------|
| 1.9 | Card "Evolution Go" em `Whatsapp.vue` (`// FORK:` import) |
| 1.10 | `EvolutionGo.vue` — Step 1: `base_url`, `global_api_key` + `GET /server/ok` health check |
| 1.11 | Step 2: `instance_name` (criar) ou `instance_token` (existente) + proxy opcional |
| 1.12 | Step 3: QR / pairing code — ActionCable + polling 3s |
| 1.13 | `useEvolutionGoConnection.js` composable |
| 1.14 | `isEvolutionGoWhatsAppChannel` em `useInbox.js` — ocultar features cloud-only |

---

## Fase 2 — Mídia, READ_RECEIPT, settings

| # | Item |
|---|------|
| 2.1 | `send_attachment_message` → `POST /send/media` |
| 2.2 | Mídia inbound: `ApiClient#download_media` (`POST /message/downloadmedia` only) |
| 2.3 | `READ_RECEIPT` → `statuses[]` flat |
| 2.4 | Reply/quote: `{ quoted: { messageId, participant } }` no send |
| 2.5 | `GET`+`PUT /instance/:id/advanced-settings` (`sync_settings!`) |
| 2.6 | `POST /message/markread` ao abrir conversa |
| 2.7 | `DELETE /instance/proxy/{id}` + UI proxy delete |

---

## Fase 3 — Interativos e operação

| # | Item |
|---|------|
| 3.1 | Poll, location, contact, sticker (`/send/*`) |
| 3.2 | Health badge via `GET /instance/status` |
| 3.3 | Alerta desconexão (`CONNECTION` close → broadcast + UI badge) |
| 3.4 | Reconnect UI → `ConnectionService#reconnect!` (disconnect + connect com webhook) |
| 3.5 | Typing: `POST /message/presence` |

---

## Fase 4 — Import histórico

| # | Item |
|---|------|
| 4.1 | `HISTORY_SYNC` webhook + `POST /chat/history-sync` |

---

## Arquivos fork

```
custom/
├── app/channels/
│   └── evolution_go_connection_channel.rb
├── app/controllers/webhooks/
│   └── evolution_go_controller.rb
├── app/services/custom/whatsapp/
│   ├── evolution_go/
│   │   ├── api_error.rb
│   │   ├── api_client.rb
│   │   └── connection_service.rb
│   ├── providers/evolution_go_service.rb
│   └── webhooks/evolution_go_normalizer.rb
└── app/javascript/dashboard/
    ├── channels/EvolutionGo.vue
    ├── settingsPage/EvolutionGo{Settings,Health}Page.vue
    ├── components/evolution_go/EvolutionGoQrScanModal.vue
    ├── composables/evolution_go/useEvolutionGo{QrSession,HealthConnection,ImportStatus}.js
    └── lib/evolution_go/evolutionGoCableRegistry.js
```

> Árvore ilustrativa da Fase 1 — o código atual tem dezenas de services sob `evolution_go/` (import, sync, diagnostics, etc.). Fonte de verdade: [status.md](./status.md).

### Upstream mínimo (`# FORK:`)

| Arquivo | Mudança |
|---------|---------|
| `app/models/channel/whatsapp.rb` | `PROVIDERS` + `'evolution_go'` |
| `config/routes.rb` | `POST /webhooks/evolution_go/:instance_name` |
| `app/javascript/.../Whatsapp.vue` | Import card Evolution Go |
| `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` | Fix `return` → `return super(params)` (Fase 0.7) |

---

## Riscos e mitigações

| Risco | Mitigação |
|-------|-----------|
| **Prepend collision com evolution node** | Fase 0.7 obrigatório; `EvolutionGoController` injeta `evolution_go_instance_name:` — ADR §27 |
| Casing PascalCase vs camelCase nas respostas Go | `ApiClient#dig_field` aceita variantes — ADR §26 |
| JID ausente em `GET /instance/status` | 4 fallbacks documentados em `api-reference.md` |
| `POST /instance/reconnect` não reconfigura webhook | Usar sempre `connect` com `webhookUrl` + `subscribe` — ADR §23/§24 |
| `advanced-settings` casing diverge Postman vs OpenAPI | `dig_field` na leitura; chaves OpenAPI na escrita — ADR §26 |
| Licença Go obrigatória | Pré-requisito operador — [troubleshooting.md](./troubleshooting.md) |
| Fixtures sintéticas podem diferir do payload real | E2E antes de specs definitivas — validation-checklist.md |

---

## Critérios de aceite Fase 1

- [ ] Inbox `provider: 'evolution_go'` criado sem regredir evolution node e cloud
- [ ] Fix Fase 0.7: prepend node chama `super` → eventos Go não descartados
- [ ] QR conecta; `connection_status` → `open`; `phone_number` atualizado
- [ ] Inbound texto → conversa no Chatwoot
- [ ] Outbound texto → `source_id = data.Info.ID`
- [ ] Sem janela 24h
- [ ] Grupos: default ignorados; com `ignore_groups: false` → conversa única por `@g.us` (ver [tasks.md § G1](./tasks.md))
- [ ] `evolution`, `evolution_go` e cloud coexistem no mesmo account
- [ ] Specs: `EvolutionGoNormalizer`, `EvolutionGoController` auth, `ApiClient#dig_field`

---

## Ordem recomendada

```
Fase 0 (0.1–0.7) → ApiError → ApiClient → ConnectionService
→ EvolutionGoService → EvolutionGoNormalizer
→ EvolutionGoController (ADR §27) → prepend job
→ EvolutionGoConnectionChannel → wizard Vue → specs → E2E
```
