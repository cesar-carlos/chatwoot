# Mapeamento `provider_config` — Evolution Go

Campos do inbox Chatwoot (`Channel::Whatsapp#provider_config`) mapeados para APIs Evolution Go.

**Referência irmã:** [../evolution-api/provider-config-mapping.md](../evolution-api/provider-config-mapping.md) — mesma estrutura de grupos, campos diferentes.

**Defaults fork:** [business-rules-adaptation.md](./business-rules-adaptation.md)

---

## Estrutura `provider_config` (resumo)

| Grupo | Campos | Sync Evolution Go |
|-------|--------|-------------------|
| Conexão | `base_url`, `global_api_key`, `instance_token`, `instance_name`, `instance_id`, `connection_status`, `webhook_token` | create/connect/status |
| WhatsApp settings | `ignore_groups`, `reject_call`, `msg_call`, `always_online`, `read_messages`, `ignore_status` | `advanced-settings` |
| Proxy | `proxy_enabled`, `proxy_host`, `proxy_port`, `proxy_username`, `proxy_password` | create `proxy` object |
| Conversas | `conversation_pending`, `merge_brazil_contacts` (+ `inbox.lock_to_single_conversation`) | Chatwoot fork |
| Outbound | `sign_msg`, `send_templates_as_text` | Chatwoot fork |
| Filtros inbound | `ignore_from_me_echo`, `mark_inbound_deleted`, `mark_inbound_edited`, `convert_markdown_inbound` | Normalizer + sync services |
| Import | `import_contacts`, `import_messages`, `import_on_connect`, `import_*` runtime | Jobs + `POST /user/*`, `HISTORY_SYNC` |
| Sync outbound irreversível | `sync_delete_to_whatsapp`, `sync_edit_to_whatsapp` | `DeleteSyncService`, `EditSyncService` |
| Diagnóstico | `mutation_stats`, `settings_sync_error`, `last_webhook_at` | `DiagnosticsService` |
| Webhook | URL + `subscribe` events | `POST /instance/connect` |

---

## Grupo 1 — Conexão (obrigatório)

| Campo Chatwoot | API Evolution Go | Notas |
|----------------|------------------|-------|
| `base_url` | Todas | Sem trailing slash |
| `global_api_key` | Header em create/list/delete | `GLOBAL_API_KEY` do servidor |
| `instance_token` | Header em connect/send/status | Retorno de `POST /instance/create` → `data.token` |
| `instance_name` | Body create `name` | Lookup webhook + índice único |
| `instance_id` | `data.id` do create | UUID interno Go |
| `webhook_token` | Query `?token=` na URL | Gerado pelo Chatwoot no create inbox |
| `connection_status` | `GET /instance/status` | `open` / `close` / `connecting` |

### Segurança

| Campo | API dashboard |
|-------|---------------|
| `global_api_key` | Write-only; GET masked; opcional se modo "instância existente" — ver [decisions.md §22](./decisions.md) |
| `instance_token` | Write-only; GET masked |
| `webhook_token` | Nunca retornar em GET público |
| `proxy_password` | Write-only |

---

## Grupo 2 — Settings → advanced-settings (Fase 2)

Path confirmado Postman: `GET` + `PUT /instance/{instanceId}/advanced-settings`. Ver [api-reference.md § Advanced settings](./api-reference.md) e [decisions.md §26](./decisions.md).

### Mapeamento `provider_config` → API

| Campo `provider_config` | Enviar (PUT body) | Ler (GET — aceitar variantes) | Default fork |
|-------------------------|-------------------|--------------------------------|--------------|
| `ignore_groups` | `ignoreGroups` | `ignoreGroups` | `true` |

Com `ignore_groups: false`, mensagens `@g.us` criam conversa por grupo (`GroupContactService`); nome via `POST /group/info`.
| `reject_call` | `rejectCall` | `rejectCall`, `rejectCalls` | `false` |
| `msg_call` | `msgRejectCall` | `msgRejectCall`, `rejectCallMessage` | `""` |
| `always_online` | `alwaysOnline` | `alwaysOnline` | `false` |
| `read_messages` | `readMessages` | `readMessages` | `false` |
| `ignore_status` | `ignoreStatus` | `ignoreStatus`, `readStatus` (⚠️ semântica diferente — não inverter) | `true` |

`ConnectionService#sync_settings!` usa `ApiClient#update_advanced_settings` com chaves **OpenAPI create** na escrita; leitura via `dig_field` na resposta GET.

---

## Grupo 3 — Proxy (inline no create)

| Campo `provider_config` | Campo Go `proxy` |
|-------------------------|------------------|
| `proxy_host` | `host` |
| `proxy_port` | `port` |
| `proxy_username` | `username` |
| `proxy_password` | `password` |

Sem `/proxy/set` — configurar no create ou advanced-settings.

---

## Grupo 4 — Webhook (via connect)

| Campo | Valor |
|-------|-------|
| URL | `{FRONTEND_URL}/webhooks/evolution_go/{instance_name}?token={webhook_token}` |
| `subscribe` | `["MESSAGE", "CONNECTION", "QRCODE"]` (+ `READ_RECEIPT` Fase 2) — persistir para reconnect ([decisions.md §23](./decisions.md)) |

Não persiste `webhook_url` separado — derivado de `instance_name` + `webhook_token`.

---

## Grupo 5 — Regras Chatwoot (não sync Go)

| Campo | Default | Descrição |
|-------|---------|-----------|
| Reabrir conversa resolvida | `inbox.lock_to_single_conversation: true` | Via `Conversations::Resolver` |
| `merge_brazil_contacts` | `true` | Normalizar 9º dígito BR |
| `sign_msg` | `false` | Assinatura agente no texto |
| `send_templates_as_text` | `true` | Template → send_text |
| `ignore_from_me_echo` | `true` | Filtrar `fromMe` no normalizer |
| `convert_markdown_inbound` | `true` | WA → markdown no normalizer |
| `convert_markdown_outbound` | `true` | markdown → WA no outbound |
| `mark_read_on_reply` | `false` | `POST /message/markread` ao responder |
| `mark_read_on_open` | `true` | mark read ao abrir conversa |
| `mark_inbound_deleted` | `true` | Cliente apaga no WA → soft delete no CW |
| `mark_inbound_edited` | `true` | Cliente edita no WA → atualiza CW |
| `sync_delete_to_whatsapp` | `false` | Agente apaga no CW → delete no WA (opt-in) |
| `sync_edit_to_whatsapp` | `false` | Conteúdo alterado no CW → edit no WA (opt-in) |
| `import_contacts` | `false` | Import manual ou `import_on_connect` |
| `import_on_connect` | `false` | Disparar import ao conectar |
| `import_messages` | `false` | Histórico via `HISTORY_SYNC` |
| `days_limit_import_messages` | `7` | Janela em dias para history sync |

### Runtime import / diagnóstico (somente leitura na UI)

| Campo | Descrição |
|-------|-----------|
| `import_status` | `idle` / `running` / `completed` / `failed` |
| `import_stats` | `contacts_imported`, `messages_imported`, … |
| `import_error` | Último erro do job |
| `mutation_stats` | `inbound_delete_skipped`, `inbound_edit_skipped` |
| `settings_sync_error` | Falha ao sync `advanced-settings` |
| `last_webhook_at` | Timestamp do último teste webhook |

---

## JSON seed (wizard)

```json
{
  "base_url": "",
  "global_api_key": "",
  "instance_name": "",
  "instance_token": "",
  "instance_id": "",
  "connection_status": "close",
  "ignore_groups": true,
  "reject_call": false,
  "msg_call": "",
  "always_online": false,
  "read_messages": false,
  "ignore_status": true,
  "proxy_enabled": false,
  "merge_brazil_contacts": true,
  "sign_msg": false,
  "send_templates_as_text": true,
  "ignore_from_me_echo": true,
  "convert_markdown_inbound": true,
  "mark_inbound_deleted": true,
  "mark_inbound_edited": true,
  "import_on_connect": false,
  "import_contacts": false,
  "import_messages": false,
  "days_limit_import_messages": 7,
  "sync_delete_to_whatsapp": false,
  "sync_edit_to_whatsapp": false
}
```

`webhook_token` gerado server-side no `ConnectionService` — não no form.

---

## Diferenças vs `provider_config` Evolution API

| Evolution API | Evolution Go |
|---------------|--------------|
| `api_key` (instance hash) | `instance_token` + `global_api_key` |
| `groups_ignore` | `ignore_groups` |
| `sync_full_history` | Via evento `HISTORY_SYNC` |
| Webhook via `/webhook/set` | Webhook no `connect` |
| `read_status` (Evolution API — **ler** status/stories) | `ignore_status` (Evolution Go — **ignorar** status) |

**⚠️ Semântica invertida:** no fork, `ignore_status: true` (default) significa não processar status WhatsApp. Não mapear 1:1 com `read_status` da Evolution API Node — labels UI devem dizer "Ignore status updates".
