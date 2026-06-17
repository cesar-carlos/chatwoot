# Contrato webhook + ActionCable — Wavoip

Especificação fixa para autenticação, idempotência, resolução de inbox e eventos realtime. Evita ambiguidade na implementação.

**Relacionado:** [architecture.md](./architecture.md) · [fixtures/README.md](./fixtures/README.md)

---

## 1. Autenticação HTTP

Wavoip não documenta assinatura HMAC. Contrato **do fork**:

| Item | Valor |
|------|-------|
| **Método** | `POST` |
| **Rota** | `/webhooks/wavoip/:phone_number` |
| **Secret** | Query `?secret={webhook_secret}` **ou** header `X-Chatwoot-Wavoip-Secret` |
| **Comparação** | `ActiveSupport::SecurityUtils.secure_compare` (timing-safe) |
| **Falha auth** | `401` sem body; log mínimo (sem payload) |
| **Sucesso** | `200` imediato; processamento assíncrono via job |

URL exibida ao admin (uma forma só — query):

```
{FRONTEND_URL}/webhooks/wavoip/+5511999999999?secret=abc123...
```

**Rotação do secret:** Settings → regenerar → admin atualiza URL no painel Wavoip. Documentar em [operations-runbook.md](./operations-runbook.md).

### Rate limiting

| Limite | Valor sugerido |
|--------|----------------|
| Por `phone_number` | 120 req/min |
| Resposta | `429` |

Implementar em `Rack::Attack` ou middleware em `custom/` — não no controller.

---

## 2. Resolução de inbox

Ordem de lookup no `WavoipController`:

1. `Channel::Wavoip.find_by(phone_number: normalized_e164)` — path param
2. Fallback: `provider_config['id_session']` no payload `DEVICE` / `CALL` se `phone` ausente
3. Não encontrado → `404` + log (sem enfileirar job)

Normalizar phone: sempre E.164 (`+` + dígitos).

---

## 3. Idempotência

Wavoip pode reenviar o mesmo evento. Regras em `CallUpsertService` / `CallUpdateHandler`:

| Regra | Comportamento |
|-------|---------------|
| Chave única | `(provider: wavoip, provider_call_id: whatsapp_call_id)` — índice UNIQUE em `calls` |
| `CREATE` duplicado | Retornar `Call` existente; não criar segunda bolha |
| `UPDATE` em status **terminal** (`completed`, `no_answer`, `failed`) | Ignorar downgrade para `ringing` |
| `UPDATE` `ACTIVE` após terminal | Ignorar (log warn) |
| `HANDLED_REMOTELY` | Fechar ring; não reabrir widget |
| `RECORD` duplicado | Sobrescrever `record_url` se URL mudou; idempotente se igual |

```ruby
# Pseudocódigo CallUpdateHandler
return if call.terminal? && !terminal_transition?(new_status)
```

---

## 4. `accepted_by_agent_id` (sem REST MVP)

| Momento | Fonte |
|---------|-------|
| Preferencial | Após `offer.accept()` no browser → `PATCH /api/v1/accounts/:id/calls/:id` com `accepted_by_agent_id: Current.user.id` (rota EE existente se disponível) |
| Fallback | Webhook `ACTIVE` sem agente → campo `nil`; atribuição manual depois |
| Assignee conversa | Na Fase 3: ao aceitar, `conversation.update!(assignee: Current.user)` se inbox com auto-assign habilitado |

**Não** criar `register_attempt` / `ack_accept` no MVP.

---

## 5. ActionCable — contrato por provider

### 5.1 `voice_call.incoming`

| Campo | WhatsApp (Meta) | Wavoip |
|-------|-----------------|--------|
| `provider` | `whatsapp` | `wavoip` |
| `id` | DB call id | DB call id |
| `call_id` | Meta call id | `whatsapp_call_id` |
| `conversation_id` | sim | sim |
| `inbox_id` | sim | sim |
| `caller` | `{ phone, name }` | `{ phone, name, profile_picture? }` |
| `sdp_offer` | **obrigatório** | **ausente** |
| `ice_servers` | sim | **ausente** |

Handler Wavoip: popular `calls` store **sem** SDP; áudio via SDK `offer` paralelo.

### 5.2 `voice_call.outbound_connected`

| Provider | Usar? |
|----------|-------|
| WhatsApp | Sim — aplica `sdp_answer` |
| Wavoip | **Não** — ignorar no registry; outbound 100% SDK |

### 5.3 `voice_call.ended` / `voice_call.accepted`

| Campo | Wavoip |
|-------|--------|
| `provider` | `wavoip` |
| `status` | `completed` \| `no_answer` \| `failed` |
| `duration_seconds` | quando `completed` |
| SDP | nunca |

### 5.4 Implementação frontend

```javascript
// custom/.../lib/voice/voiceCallCableRegistry.js
export const VOICE_CALL_CABLE_HANDLERS = {
  whatsapp: whatsappVoiceCableHandlers,
  wavoip: wavoipVoiceCableHandlers,
};
```

`actionCable.js` — único `# FORK:`:

```javascript
const handler = VOICE_CALL_CABLE_HANDLERS[data?.provider];
if (handler) handler.onIncoming(data);
```

---

## 6. Push offline (Fase 3)

Job enfileirado no `CallCreateHandler` inbound quando:

- `inbound_calls_enabled?`
- Nenhum agente **online** no inbox (mesma query do ring Meta)
- Enviar via push VAPID existente — payload deep-link para conversa

Não depende do SDK (aba fechada).

---

## 7. Logging e privacidade

| Dado | Log produção |
|------|--------------|
| `device_token` | nunca |
| `webhook_secret` | nunca |
| Payload completo | só `development` / spike |
| Produção | `type`, `action`, `whatsapp_call_id`, `status`, `inbox_id` |
