# Mapeamento `provider_config` — Evolution

Campos do inbox Chatwoot (`Channel::Whatsapp#provider_config`) mapeados para APIs e comportamentos da Evolution.

**Catálogo completo de regras de negócio e layout UI:** [inbox-business-rules.md](./inbox-business-rules.md)

**Defaults e adaptação ao fork:** [business-rules-adaptation.md](./business-rules-adaptation.md)

---

## Estrutura `provider_config` (resumo)

Ver JSON completo em [inbox-business-rules.md § provider_config completo](./inbox-business-rules.md#provider_config-completo-referência).

Grupos de campos:

| Grupo | Campos | Sync Evolution |
|-------|--------|----------------|
| Conexão | `base_url`, `api_key`, `instance_name`, `instance_id`, `connection_status` | create/connect |
| WhatsApp settings | `groups_ignore`, `reject_call`, `msg_call`, `always_online`, `read_messages`, `read_status`, `sync_full_history` | `POST /settings/set` |
| Proxy | `proxy_enabled`, `proxy_host`, `proxy_port`, `proxy_protocol`, `proxy_username`, `proxy_password` | `POST /proxy/set` |
| Conversas | `conversation_pending`, `merge_brazil_contacts` (+ `inbox.lock_to_single_conversation`) | Chatwoot fork |
| Outbound | `sign_msg`, `sign_delimiter`, `mark_read_on_reply`, `sync_delete_to_whatsapp`, `convert_markdown_outbound`, `send_templates_as_text` | Chatwoot fork |
| Filtros inbound | `ignore_jids`, `ignore_status_broadcast`, `ignore_from_me_echo`, `ignore_survey_links`, `ignore_private_notes` | Normalizer |
| Import | `import_contacts`, `import_messages`, `days_limit_import_messages` | Fase 4 |
| Webhook | (auto) URL + events | `POST /webhook/set` |

---

## Grupo 1 — Conexão Evolution (obrigatório)

| Campo Chatwoot | API Evolution | Notas |
|----------------|---------------|-------|
| `base_url` | Todas | URL do servidor Evolution (sem trailing slash) |
| `api_key` | Header `apikey` | Token da instância ou API key global |
| `instance_name` | Path `/:instanceName` | Único no fork — **1 instância = 1 inbox** ([decisions.md §3](./decisions.md)) |

### Segurança — campos sensíveis

| Campo | API dashboard | Armazenamento |
|-------|---------------|---------------|
| `api_key` | Write-only; GET masked | `provider_config` JSONB |
| `proxy_password` | Write-only; GET masked | `provider_config` JSONB |

Ver [inbox-business-rules.md § Segurança](./inbox-business-rules.md#segurança--api_key-e-senhas) · [decisions.md §15](./decisions.md).

**Doc:** [create-instance](https://docs.evolutionfoundation.com.br/evolution-api/create-instance)

Modalidades na criação:

1. **Criar instância nova** — `POST /instance/create` com `integration: WHATSAPP-BAILEYS`, `qrcode: true`
2. **Usar instância existente** — validar com `GET /instance/connectionState/:instanceName`

---

## Grupo 2 — Settings Baileys → `POST /settings/set/:instanceName`

| Campo `provider_config` | Campo Evolution | Default |
|-------------------------|-----------------|---------|
| `groups_ignore` | `groupsIgnore` | `false` |
| `reject_call` | `rejectCall` | `false` |
| `msg_call` | `msgCall` | `""` |
| `always_online` | `alwaysOnline` | `false` |
| `read_messages` | `readMessages` | `false` |
| `read_status` | `readStatus` | `false` |
| `sync_full_history` | `syncFullHistory` | `false` |

**Schema:** `src/validate/settings.schema.ts`  
**Doc:** [set-settings](https://docs.evolutionfoundation.com.br/evolution-api/set-settings)

---

## Grupo 3 — Proxy → `POST /proxy/set/:instanceName`

| Campo `provider_config` | Campo Evolution |
|-------------------------|-----------------|
| `proxy_enabled` | `enabled` |
| `proxy_host` | `host` |
| `proxy_port` | `port` |
| `proxy_protocol` | `protocol` |
| `proxy_username` | `username` |
| `proxy_password` | `password` |

**Doc:** [set-proxy](https://docs.evolutionfoundation.com.br/evolution-api/set-proxy)

---

## Grupo 4 — Regras Chatwoot (sem API Evolution)

Detalhes e comportamento: [inbox-business-rules.md](./inbox-business-rules.md)

| Campo | Implementar em |
|-------|----------------|
| `sign_msg`, `sign_delimiter` | `EvolutionService#send_message` |
| `conversation_pending` | `IncomingMessageServiceHelpers` + `Custom::Message#reopen_resolved_conversation` |
| Reabrir conversa resolvida | `inbox.lock_to_single_conversation` → `Conversations::Resolver` + `Message#reopen_conversation` |
| `merge_brazil_contacts` | Normalizer + `ContactInboxBuilder` |
| `mark_read_on_reply` | `EvolutionService` pós-envio → `markMessageAsRead` |
| `sync_delete_to_whatsapp` | Listener `message_updated` |
| `ignore_jids` (+ flags implícitas) | `EvolutionNormalizer` |

---

## Grupo 5 — Webhook (automático)

```json
POST /webhook/set/:instanceName
{
  "webhook": {
    "enabled": true,
    "url": "https://{CHATWOOT}/webhooks/evolution/{instance_name}",
    "byEvents": false,
    "base64": false,
    "events": ["MESSAGES_UPSERT", "MESSAGES_UPDATE", "CONNECTION_UPDATE", "QRCODE_UPDATED"]
  }
}
```

**Doc:** [set-webhook](https://docs.evolutionfoundation.com.br/evolution-api/set-webhook)

---

## Sincronização ao salvar inbox

```
PATCH channel (provider_config)
  → Channel::Whatsapp after_commit (evolution)
      → ConnectionService#sync_settings!   (grupo 2)
      → ConnectionService#sync_proxy!      (grupo 3 — `{ enabled: false }` quando proxy off)
```

**UI (Fase 2 — T2):** Settings → aba **WhatsApp** no inbox Evolution — `custom/.../EvolutionSettingsPage.vue`. Campos editáveis: grupos 2–4 parciais (ver [inbox-business-rules.md § Fase 2 UI](./inbox-business-rules.md)).

Regras dos grupos 4–6 sem sync Evolution: apenas persistidas no JSONB — lidas pelo fork em runtime.

---

## Campos que NÃO vão no `provider_config`

| Campo Evolution legado | Motivo |
|------------------------|--------|
| `chatwootAccountId`, `chatwootToken`, `chatwootUrl` | Chatwoot é o sistema host |
| `autoCreate` | Wizard Chatwoot cria o inbox |
| `organization`, `logo` | Whitelabel bot Evolution — substituído por branding CW |
| `enabled` (integração CW na Evolution) | Sempre `false` — usar provider nativo |
