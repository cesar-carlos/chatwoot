# Regras de negócio — Caixa de entrada Evolution Go

Regras do inbox `provider: 'evolution_go'` mapeadas para campos `provider_config`, APIs Go e UI do fork.

**Defaults adaptados:** [business-rules-adaptation.md](./business-rules-adaptation.md) · **Campos ↔ API:** [provider-config-mapping.md](./provider-config-mapping.md)

**Irmão (referência UI):** [../evolution-api/inbox-business-rules.md](../evolution-api/inbox-business-rules.md) — mesma UX alvo, APIs diferentes.

---

## Escopo por fase (histórico — tudo implementado jul/2026)

| Área | Onde vive | Default / notas |
|------|-----------|-----------------|
| Wizard + provision | `EvolutionGo.vue`, `ConnectionProvisioner` | `base_url`, `instance_name`, proxy opcional |
| Settings | `EvolutionGoSettingsPage.vue` | `ignore_groups`, import, sync delete/edit, … |
| Health + diagnóstico | `EvolutionGoHealthPage.vue` | reconnect, logout, sync webhook, test webhook |
| Filtros inbound | `EvolutionGoNormalizer` + job prepend | `ignore_from_me_echo`, `ignore_groups`; `status@broadcast` sempre ignorado |
| Webhook subscribe | `WebhookSubscribeSync` | Lista canônica + `GROUP` condicional; re-sync ao mudar flags |
| Conversas | inbox settings + `provider_config` | `lock_to_single_conversation`, `merge_brazil_contacts` |

---

## Onde cada regra vive (Evolution Go)

```mermaid
flowchart LR
  subgraph inbox_ui["Inbox Chatwoot"]
    CONN[Conexão]
    WA[Comportamento WA]
    CONV[Conversas]
    OUT[Outbound]
    IN[Inbound filtros]
    PROXY[Proxy]
  end

  subgraph evogo_api["Evolution Go REST"]
    CREATE["POST /instance/create"]
    CONNECT["POST /instance/connect"]
    ADV["GET/PUT /instance/:id/advanced-settings"]
    DELPROXY["DELETE /instance/proxy/:id"]
  end

  subgraph fork["custom/"]
    NORM[EvolutionGoNormalizer]
    ESVC[EvolutionGoService]
    CONN_SVC[ConnectionService]
  end

  CONN --> CREATE
  CONN --> CONNECT
  WA --> CREATE
  WA --> ADV
  PROXY --> CREATE
  PROXY --> DELPROXY
  OUT --> ESVC
  IN --> NORM
  CONV --> fork
```

| Camada Go | Regras |
|-----------|--------|
| **Create** | `name`, `token`, `proxy`, flags `ignoreGroups`, `rejectCall`, `readMessages` |
| **Connect** | `webhookUrl`, `subscribe[]`, `phone` (pairing) |
| **Advanced-settings** | `alwaysOnline`, `rejectCall`, `ignoreGroups`, etc. |
| **Fork envio** | `sign_msg`, markdown, template→texto |
| **Fork inbound** | `ignore_jids`, echo, broadcast |
| **Fork conversas** | `lock_to_single_conversation`, merge BR |

> **Sem** `POST /settings/set` nem `POST /webhook/set` — diferente da Evolution API Node.

---

## 1. Conexão (wizard — obrigatório)

| Campo | Tipo | Fase | UI | API Go |
|-------|------|------|-----|--------|
| `base_url` | string | 1 | URL servidor | Todas |
| `global_api_key` | string | 1 | Admin API key | `POST /instance/create`, `GET /instance/all` |
| `instance_name` | string | 1 | Nome instância | body `name` no create |
| `instance_token` | string | 1 | Oculto / readonly | `data.token` do create |
| `instance_id` | string | 1 | Debug readonly | `data.id` do create |
| `webhook_token` | string | 1 | Auto-gerado | query `?token=` na webhook URL |
| `connection_status` | enum | 1 | Badge | `GET /instance/status` |
| `phone_number` | channel | 1 | Após connect | `data` status / jid |

### Modos de setup

| Modo | Fluxo |
|------|-------|
| **A — Criar nova** | Wizard → create (global key) → connect (instance token) → QR |
| **B — Instância existente** | Operador cola `instance_token` + `instance_name` → connect only |

### Segurança

| Campo | GET API dashboard |
|-------|-------------------|
| `global_api_key` | masked |
| `instance_token` | masked |
| `webhook_token` | nunca expor |
| `proxy_password` | masked |

Ver [decisions.md §14](./decisions.md).

---

## 2. Comportamento WhatsApp

Flags no **create** (`data` da instância) e **advanced-settings** (Fase 2) via `GET`+`PUT /instance/{id}/advanced-settings`.

Mapeamento completo com variantes de casing: [provider-config-mapping.md § Grupo 2](./provider-config-mapping.md) · [decisions.md §26](./decisions.md).

| Campo fork | Campo Go | Default | Fase | Label UI (en) |
|------------|----------|---------|------|---------------|
| `ignore_groups` | `ignoreGroups` | **`true`** | 2 | Ignore groups — com `false`, conversa única por grupo |
| `reject_call` | `rejectCall` | `false` | 2 | Reject calls |
| `msg_call` | `msgRejectCall` | `""` | 2 | Message when rejecting call |
| `always_online` | `alwaysOnline` | `false` | 2 | Always online |
| `read_messages` | `readMessages` | `false` | 2 | Mark incoming as read on WA |
| `ignore_status` | `ignoreStatus` | **`true`** | 2 | Ignore status broadcasts |

**Default:** `ignore_groups: true` no create. UI toggle em **Comportamento WhatsApp** (`EvolutionGoSettingsPage`).

Doc create: [create-a-new-instance](https://docs.evolutionfoundation.com.br/evolution-go/create-a-new-instance)

---

## 3. Proxy

| Campo fork | Campo Go `proxy` | Fase |
|------------|------------------|------|
| `proxy_host` | `host` | 1 (wizard) |
| `proxy_port` | `port` | 1 |
| `proxy_username` | `username` | 1 |
| `proxy_password` | `password` | 1 |

- Configurar no `POST /instance/create` body `proxy`
- Remover: `DELETE /instance/proxy/{instanceId}` — [delete-proxy](https://docs.evolutionfoundation.com.br/evolution-go/delete-proxy)
- **Sem** `POST /proxy/set` como Evolution API Node

---

## 4. Conversas (Chatwoot fork)

| Campo | Default | Fase | Comportamento |
|-------|---------|------|---------------|
| `inbox.lock_to_single_conversation` | **`true`** | nativo | Resolved + inbound → reabre (via `Conversations::Resolver`) |
| `merge_brazil_contacts` | `true` | 2 | Normaliza 9º dígito BR |

**Não portado de Evolution Node:** `conversation_pending` — default/UI só no provider `evolution`; helpers de pending cycle checam `provider == 'evolution'`, não `evolution_go`. Settings Go não expõem o toggle.

Implementar filtros inbound no job/normalizer — **não** existe DTO Chatwoot na Evolution Go.

---

## 5. Outbound — agente

| Campo | Default | Fase | Notas |
|-------|---------|------|-------|
| `send_templates_as_text` | `true` | 1 | Template → `POST /send/text` |
| `sign_msg` | `false` | 2 | Prefixo agente |
| `sign_delimiter` | `\n` | 2 | — |
| `convert_markdown_outbound` | `true` | 2 | CW → WA formatting |
| `mark_read_on_reply` | `false` | 2 | → `POST /message/markread`; fallback: última não lida se sem reply target |
| `send_random_delay` | via `delay` no send | 2 | Campo `delay` em SendText |
| `sync_delete_to_whatsapp` | `false` | UX | Agente delete **outgoing** CW → sync WA **first** (`POST /message/delete`) → soft-delete local (opt-in, irreversível no WA); falha API → 422 sem alterar CW; JID via `ChatJid` |
| `sync_edit_to_whatsapp` | `false` | UX | Opt-in: context menu Edit → `MessageContentEditService` → `POST /message/edit` (markdown/signature) — ADR §35 |
| `notify_send_errors_private` | `true` | 2 | Nota privada em falha de envio |

**Quote reply:** `{ quoted: { messageId, participant } }` — schema Go, não Baileys.

---

## 6. Inbound — filtros

| Campo | Default | Fase | Implementação |
|-------|---------|------|---------------|
| `ignore_from_me_echo` | `true` | 1 | Normalizer (configurável) |
| `ignore_status` | `true` | 2 | `status@broadcast` |
| `mark_inbound_deleted` | `true` | UX | Webhook revoke/delete → marca `deleted` no CW **mantendo o texto original** + destaque vermelho / aviso i18n (inclui `fromMe` / celular; `deleted_via_evolution_go_webhook`). Job sempre consome o envelope; soft-delete gated por esta flag |
| `mark_inbound_edited` | `true` | UX | Webhook edit plaintext → atualiza CW (inclui `fromMe` / celular; skip noop / encrypted-only / orphan). Texto bare + `content_attributes.edited` + badge. Residual: Go sem `editedMessage` → CW não muda |
| `convert_markdown_inbound` | `true` | UX | Normalizer + edit sync |

### `source_id` inbound

`data.key.id` no webhook `MESSAGE` — formato Baileys-like no envelope, distinto do outbound `data.Info.ID`.

**Contato 1:1 LID** (ago/2026): `wa_id` é telefone quando há alt PN; senão o JID `@lid` completo. `evolution_go_remote_jid` / `identifier` guardam o addressing `@lid` — não o PN reescrito. Unique ID na sidebar = `identifier` (pode ficar vazio). Dígitos LID não viram `phone_number`. Ver [decisions.md §37](./decisions.md). Dois inboxes Go na mesma conta: lock de `source_id` é **por inbox** ([§38](./decisions.md)).

---

## 7. Webhook (automático)

| Regra | Valor |
|-------|-------|
| URL | `{FRONTEND_URL}/webhooks/evolution_go/{instance_name}?token={webhook_token}` |
| Registro | `POST /instance/connect` body `webhookUrl` |
| Subscribe | Lista canônica `ProviderConfig::WEBHOOK_EVENTS` (+ `GROUP` se `ignore_groups: false`) — ver [webhook-events.md](./webhook-events.md) |
| ActionCable | `evolution_go:connection:{inbox_id}` |
| Integração CW nativa | **Não existe** — nada a desabilitar |

---

## 8. Settings inbox — abas (Fase 2+)

| Aba / seção | Conteúdo |
|-------------|----------|
| **Health + diagnóstico** | Status, reconnect, QR, webhook URL, subscribe, import status, `mutation_stats`, test webhook |
| **Comportamento WhatsApp** | ignore_groups, reject_call, read_messages, always_online (sync advanced-settings) |
| **Mensagens enviadas** | sign_msg, markdown, mark read, delay, templates, notify errors |
| **Filtros inbound** | ignore echo/status, markdown inbound, mark deleted/edited (só Chatwoot) |
| **Irreversível** | sync_delete_to_whatsapp, sync_edit_to_whatsapp (bloco amber) |
| **Importação** | contacts, messages, on_connect, merge BR, status + polling |
| **Proxy** | Banner create-only se `proxy_host` presente; remove via API |

Ocultar: templates Meta, campanhas, embedded signup, health cloud, voz Meta.

---

## 9. Importação e histórico

| Campo | Default | API / evento |
|-------|---------|--------------|
| `import_contacts` | `false` | `GET /user/contacts` + enrichment `/user/info`, `/user/avatar` |
| `import_on_connect` | `false` | Dispara `ImportJob` ao `connection_status: open` |
| `import_messages` | `false` | `POST /chat/history-sync` → webhook `HISTORY_SYNC` |
| `days_limit_import_messages` | `100` | `count` de mensagens por chat no history-sync (nome legado; não é janela em dias) |

Mensagens históricas recebem `content_attributes.history_import: true`.

---

## 10. Diagnóstico operacional

| Endpoint | `GET /api/v1/accounts/:id/inboxes/:id/evolution_go_diagnostics` |
|----------|----------------------------------------------------------------|
| Campos | `webhook_url`, `connection_status`, `import_*`, `mutation_stats`, `settings_sync_error` |
| Teste | `POST evolution_go_test_webhook` — enfileira MESSAGE sintético + `last_webhook_at` |

---

## Checklist UI — paridade mínima Evolution Manager Go

| Tela Manager Go | Equivalente Chatwoot | Fase |
|-----------------|---------------------|------|
| Create instance | Wizard step 1 | 1 |
| Connect + webhook events | Wizard step 2 (automático) | 1 |
| QR / pairing code | Wizard step 3 | 1 |
| Instance list | Não portar (admin no painel Go) | — |
| Advanced settings | Inbox settings | 2 |

Ver [frontend-wizard-spec.md](./frontend-wizard-spec.md).
