# Contrato webhook + ActionCable — Wavoip

Especificação fixa para autenticação, idempotência, resolução de inbox e eventos realtime. Evita ambiguidade na implementação.

**DTO e handlers:** [architecture.md §3](./architecture.md#3-backend--webhook) (`Voice::Dto::WebhookCallEvent`).

**Doc oficial webhook:** https://wavoip.gitbook.io/api/webhook-beta.md · **Índice:** [official-docs.md](./official-docs.md)

**Relacionado:** [architecture.md](./architecture.md) · [fixtures/README.md](./fixtures/README.md)

---

## 1. Autenticação HTTP

Wavoip documenta a configuração de uma URL, mas não assinatura HMAC nem header
customizado. Contrato **do fork**:

| Item | Valor |
|------|-------|
| **Método** | `POST` |
| **Rota** | `POST /webhooks/wavoip/:webhook_key` |
| **Chave** | Token opaco por canal (`channel_wavoip.webhook_key`), gerado e rotacionado pelo backend |
| **Lookup** | `Channel::Wavoip.find_by(webhook_key:)` — **não** usar inbox id no path |
| **Falha auth** | `401` sem body; log mínimo (sem payload) |
| **Sucesso** | `202` imediato; processamento assíncrono via `Wavoip::ProcessWebhookJob` |

URL exibida ao admin (campo API `wavoip_webhook_url`):

```
{FRONTEND_URL}/webhooks/wavoip/{webhook_key}
```

Exemplo produção (account 2, inbox 42): `https://chat.se7esistemassinop.com.br/webhooks/wavoip/mz5uFxCZ4tVZn94Nm5osnqCQ`

> **Erro comum:** `/webhooks/wavoip/42` — `42` é o inbox id, não a `webhook_key`. O path correto
> usa a chave opaca gerada na criação do canal.

Não usar telefone no path nem secret em query: ambos aparecem com frequência em logs,
proxies e analytics. No painel Wavoip: ativar toggle do webhook e selecionar evento **CALL**.
**Rotação:** Settings → regenerar → atualizar URL no painel Wavoip.

### Rate limiting ✅ **Implementado**

| Limite | Valor |
|--------|-------|
| Por `webhook_key` + IP | 120 req/min (`config/initializers/rack_attack.rb`) |
| Payload máximo | 64 KB (`WavoipController::MAX_PAYLOAD_BYTES`) |
| Resposta throttle | `429` |

---

## 2. Resolução de inbox

O controller resolve o canal exclusivamente por `webhook_key`. `phone_number` e
`id_session` do payload são dados de validação/correlação, não credenciais nem lookup
primário. Chave inexistente retorna `401` sem revelar se um inbox existe.

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
| Status/duração sem mudança | Não rebroadcastar nem atualizar timestamps |

```ruby
# Pseudocódigo CallUpdateHandler
return if call.terminal? && !terminal_transition?(new_status)
```

---

## 4. `accepted_by_agent_id`

| Momento | Fonte |
|---------|-------|
| Preferencial | Após `offer.accept()` no browser → `POST .../calls/:id/join` (persiste claim) |
| Alias | `PATCH .../calls/:id` — idempotente, mesma lógica de `join` (clientes antigos) |
| Fallback | Webhook `ACTIVE` sem agente → `JoiningAgentCache` / campo `nil` |
| Assignee conversa | Só se `inbox.enable_auto_assignment?` **e** `assignee_id` em branco |

### 4.1 Rota API (implementado)

**Verificado no código:** `custom/app/controllers/custom/api/v1/accounts/calls_controller.rb` (prepend no Enterprise controller)

```ruby
# POST /api/v1/accounts/:account_id/calls/:id/join  — claim autoritativo
# PATCH /api/v1/accounts/:account_id/calls/:id      — alias de join
# Sem user id no body — o backend usa Current.user
# Só preenche accepted_by_agent_id quando provider wavoip e campo ainda vazio
```

Autorização: `authorize @call.inbox, :show?`. Spec: `spec/custom/controllers/api/v1/accounts/calls_controller_spec.rb`.

### 4.2 ClaimGuard e timeouts

| Situação | Comportamento |
|----------|---------------|
| `accepted_by_agent_id` presente | `ClaimGuard.claimed?` — para ring/escalate/push |
| `AutoNoAnswerRingJob` com claim | Não fecha; agenda `ClaimedRingGraceJob` (~45 min) |
| `HANDLED_REMOTELY` + claimed + ringing | Ignora (não mata SDK); agenda `HandledRemotelyStaleJob` (~2 min) |

---

## 5. Evento `RECORD`

Webhook separado do `CALL` — entrega `record_url` e `record_status` após a ligação. Fixture: [fixtures/record_update.json](./fixtures/record_update.json).

| Campo payload | Uso |
|---------------|-----|
| `whatsapp_call_id` | Correlação com `Call.provider_call_id` |
| `record_url` | URL pública da gravação (`.ogg`) |
| `record_status` | `READY`, `RECORDING`, `MIXING`, `DISABLED`, `EMPTY_RECORDING` |

### 5.1 Pipeline

```
RECORD → PayloadNormalizer → RecordHandler → RecordingPolicy → AttachRecordingJob (:low)
```

| Gate | Comportamento |
|------|---------------|
| `!inbox.channel.call_recording_enabled?` | Ignorar (não enfileirar attach) |
| `Call.status != completed` | Não anexar agora; persistir URL + `RetryRecordAttachmentJob` (debounce 2 min) |
| `record_status` desconhecido | Log warn + ignorar attach |
| `record_status` ∈ `DISABLED`, `EMPTY_RECORDING` | Ignorar |
| `record_status` ∈ `RECORDING`, `MIXING` | Persistir `record_status` em `Call#meta`; aguardar `READY` |
| `record_status == READY` (ou ausente com URL) | Enfileirar `AttachRecordingJob` se call completed |
| `Call` ainda não existe | `RetryRecordAttachmentJob` (mesmo debounce) |

Idempotência: mesmo `record_url` já em `meta` → não reenfileirar attach; retries usam lock Redis por inbox+provider_call_id.

---

## 6. ActionCable — contrato por provider

### 6.1 `voice_call.incoming`

| Campo | WhatsApp (Meta) | Wavoip |
|-------|-----------------|--------|
| `provider` | `whatsapp` | `wavoip` |
| `id` | DB call id | DB call id |
| `call_id` | Meta call id | `whatsapp_call_id` |
| `conversation_id` | sim | sim |
| `inbox_id` | sim | sim |
| `caller` | `{ phone, name }` | `{ phone, name? }` |
| `sdp_offer` | **obrigatório** | **ausente** |
| `ice_servers` | sim | **ausente** |
| `escalated` | — | `true` em re-ring de timeout (`EscalateRingJob`); FE ignora se call active/dismissed |

Handler Wavoip: popular `calls` store **sem** SDP; áudio via SDK `offer` paralelo.
Após `accepted_by_agent_id` (`ClaimGuard`), backend **não** reenvia incoming/escalated/push.

### 6.2 `voice_call.outbound_connected`

| Provider | Usar? |
|----------|-------|
| WhatsApp | Sim — aplica `sdp_answer` |
| Wavoip | **Não** — ignorar no registry; outbound 100% SDK |

### 6.3 `voice_call.ended` / `voice_call.accepted`

| Campo | Wavoip |
|-------|--------|
| `provider` | `wavoip` |
| `status` | `completed` \| `no_answer` \| `failed` |
| `duration_seconds` | quando `completed` |
| SDP | nunca |

### 6.4 Implementação frontend (dispatch real)

```javascript
// app/javascript/dashboard/lib/voice/whatsappVoiceCableRegistry.js
export const createWhatsappVoiceCableHandlers = () => ({
  onIncoming(data) { /* SDP required */ },
  onOutboundConnected(data) { /* applyOutboundAnswer */ },
  // ...
});

// custom/.../lib/voice/voiceCallCableRegistry.js
export const createWavoipVoiceCableHandlers = t => ({ /* no SDP */ });
```

`actionCable.js` delega por `data.provider`:

```javascript
if (data?.provider === VOICE_CALL_PROVIDERS.WAVOIP) {
  this.wavoipVoiceCableHandlers().onIncoming?.(data);
  return;
}
if (data?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP) return;
this.whatsappVoiceCableHandlers().onIncoming(data);
```

---

## 7. Push com aba fechada (pós-MVP)

Web Push pode avisar sobre uma chamada, mas não mantém a conexão SDK nem a oferta viva.
Portanto é best-effort e não faz parte do critério de atendimento inbound.

Se implementado, usar o pipeline de `Notification`/VAPID existente, respeitar
preferências do usuário e enviar apenas deep-link para a conversa. Não prometer botão
“aceitar” nem entrega antes da expiração da oferta.

---

## 8. Logging e privacidade

| Dado | Log produção |
|------|--------------|
| `device_token` | nunca |
| `webhook_key` | nunca |
| Payload completo | só `development` / spike |
| Produção | `type`, `action`, `whatsapp_call_id`, `status`, `inbox_id` |
