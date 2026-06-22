# Mapeamento `provider_config` — Evolution Go

Campos do inbox Chatwoot (`Channel::Whatsapp#provider_config`) mapeados para APIs Evolution Go.

**Referência irmã:** [../evolution-api/provider-config-mapping.md](../evolution-api/provider-config-mapping.md) — mesma estrutura de grupos, campos diferentes.

**Defaults fork:** [business-rules-adaptation.md](./business-rules-adaptation.md)

---

## Estrutura `provider_config` (resumo)

| Grupo | Campos | Sync Evolution Go |
|-------|--------|-------------------|
| Conexão | `base_url`, `global_api_key`, `instance_token`, `instance_name`, `instance_id`, `connection_status`, `webhook_secret` | create/connect/status |
| WhatsApp settings | `ignore_groups`, `reject_call`, `msg_call`, `always_online`, `read_messages`, `ignore_status` | `advanced-settings` |
| Proxy | `proxy_enabled`, `proxy_host`, `proxy_port`, `proxy_username`, `proxy_password` | create `proxy` object |
| Conversas | `conversation_pending`, `merge_brazil_contacts` (+ `inbox.lock_to_single_conversation`) | Chatwoot fork |
| Outbound | `sign_msg`, `send_templates_as_text` | Chatwoot fork |
| Filtros inbound | `ignore_from_me_echo` | Normalizer |
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
| `webhook_secret` | Query `?token=` na URL | Gerado pelo Chatwoot no create inbox |
| `connection_status` | `GET /instance/status` | `open` / `close` / `connecting` |

### Segurança

| Campo | API dashboard |
|-------|---------------|
| `global_api_key` | Write-only; GET masked; opcional se modo "instância existente" — ver [decisions.md §22](./decisions.md) |
| `instance_token` | Write-only; GET masked |
| `webhook_secret` | Nunca retornar em GET público |
| `proxy_password` | Write-only |

---

## Grupo 2 — Settings → advanced-settings (Fase 2)

Path confirmado Postman: `GET` + `PUT /instance/{instanceId}/advanced-settings`. Ver [api-reference.md § Advanced settings](./api-reference.md) e [decisions.md §26](./decisions.md).

### Mapeamento `provider_config` → API

| Campo `provider_config` | Enviar (PUT body) | Ler (GET — aceitar variantes) | Default fork |
|-------------------------|-------------------|--------------------------------|--------------|
| `ignore_groups` | `ignoreGroups` | `ignoreGroups` | `true` |
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
| `proxy_host` | `address` |
| `proxy_port` | `port` |
| `proxy_username` | `username` |
| `proxy_password` | `password` |

Sem `/proxy/set` — configurar no create ou advanced-settings.

---

## Grupo 4 — Webhook (via connect)

| Campo | Valor |
|-------|-------|
| URL | `{FRONTEND_URL}/webhooks/evolution_go/{instance_name}?token={webhook_secret}` |
| `subscribe` | `["MESSAGE", "CONNECTION", "QRCODE"]` (+ `READ_RECEIPT` Fase 2) — persistir para reconnect ([decisions.md §23](./decisions.md)) |

Não persiste `webhook_url` separado — derivado de `instance_name` + `webhook_secret`.

---

## Grupo 5 — Regras Chatwoot (não sync Go)

| Campo | Default | Descrição |
|-------|---------|-----------|
| Reabrir conversa resolvida | `inbox.lock_to_single_conversation: true` | Via `Conversations::Resolver` |
| `merge_brazil_contacts` | `true` | Normalizar 9º dígito BR |
| `sign_msg` | `false` | Assinatura agente no texto |
| `send_templates_as_text` | `true` | Template → send_text |
| `ignore_from_me_echo` | `true` | Filtrar `fromMe` no normalizer |

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
  "ignore_from_me_echo": true
}
```

`webhook_secret` gerado server-side no `ConnectionService` — não no form.

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
