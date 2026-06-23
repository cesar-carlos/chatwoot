# Mapeamento `provider_config` — Z-API

Chave do provider: **`zapi`**

Persistido em `channel_whatsapp.provider_config` (JSONB), mesmo padrão dos providers Evolution.

---

## Campos obrigatórios (MVP)

| Campo | Tipo | Origem | Uso |
|-------|------|--------|-----|
| `instance_id` | string | Painel Z-API ou API Partners | Identificador da instância; segmento na URL REST e rota webhook |
| `instance_token` | string | Painel Z-API | Token no path `/instances/{id}/token/{token}/` |
| `client_token` | string | Painel Z-API (conta) | Header `Client-Token` — **obrigatório se** "Token de Segurança" ativado na conta |
| `connection_status` | string | Atualizado pelo fork | `disconnected` · `connecting` · `connected` |
| `webhook_token` | string | Gerado pelo Chatwoot | Validação opcional de callbacks (`?token=`) |

---

## Campos opcionais

| Campo | Tipo | Quando |
|-------|------|--------|
| `base_url` | string | Override de `https://api.z-api.io` (raro) |
| `phone_number` | string | Preenchido após conexão (`GET /me` ou webhook connected) |
| `partner_auth_token` | string | Só se wizard usar API Partners (não persistir em produção se possível) |
| `auto_read` | boolean | Default `false` — não ativar `update-auto-read-message` |
| `ignore_groups` | boolean | Default `true` — filtrar `isGroup: true` no inbound |
| `webhook_urls` | object | Cache das URLs registradas na Z-API (debug) |

### `webhook_urls` (cache)

```json
{
  "received": "https://chatwoot.example.com/webhooks/zapi/{instance_id}",
  "delivery": "https://chatwoot.example.com/webhooks/zapi/{instance_id}",
  "message_status": "https://chatwoot.example.com/webhooks/zapi/{instance_id}",
  "disconnected": "https://chatwoot.example.com/webhooks/zapi/{instance_id}"
}
```

No MVP todas apontam para a **mesma rota**; demux por `type` no body.

---

## Exemplo completo (inbox conectado)

```json
{
  "instance_id": "3C01A8...",
  "instance_token": "A1B2C3...",
  "client_token": "F4E5D6...",
  "connection_status": "connected",
  "webhook_token": "uuid-gerado-pelo-chatwoot",
  "phone_number": "5544999887766",
  "ignore_groups": true
}
```

---

## Mapeamento para serviços do fork

| Serviço | Campos lidos |
|---------|--------------|
| `Zapi::ApiClient` | `base_url`, `instance_id`, `instance_token`, `client_token` |
| `Zapi::ConnectionService` | todos + `webhook_token` para registrar callbacks |
| `ZapiService` (provider) | `instance_*`, `client_token` |
| `ZapiController` (webhook) | `instance_id` na rota + `webhook_token` |
| Wizard Vue | `instance_id`, `instance_token`, `client_token` (input manual MVP) |

---

## Segurança

- `instance_token` e `client_token` são **secretos** — não expor em logs
- Mascarar no dashboard (como Evolution `api_key`)
- `client_token` é por **conta** Z-API, não por instância — pode ser compartilhado entre inboxes da mesma conta

---

## Diferença vs Evolution `provider_config`

| Campo Evolution | Equivalente Z-API |
|-----------------|-------------------|
| `api_key` | `instance_token` (no path) + `client_token` (header) |
| `instance_name` | `instance_id` (Z-API usa ID, não nome slug) |
| `base_url` | fixo SaaS ou override |
| `webhook_token` | igual |
