# Contrato webhook + ActionCable — Wavoip

Especificação fixa para autenticação, idempotência, resolução de inbox e eventos realtime. Evita ambiguidade na implementação.

**Portas backend e DTO:** [contracts-and-ports.md §4](./contracts-and-ports.md#4-contratos-backend-ruby) · **Fontes da verdade:** [§3](./contracts-and-ports.md#3-fontes-da-verdade-evitar-duplicidade-conflitante)

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

### Rate limiting

| Limite | Valor sugerido |
|--------|----------------|
| Por `webhook_key` + IP | 120 req/min |
| Resposta | `429` |

Implementar em `Rack::Attack` ou middleware em `custom/` — não no controller.

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
| Preferencial | Após `offer.accept()` no browser → `PATCH /api/v1/accounts/:account_id/calls/:id` |
| Fallback | Webhook `ACTIVE` sem agente → campo `nil`; atribuição manual depois |
| Assignee conversa | Ao aceitar, `conversation.update!(assignee: Current.user)` se inbox com auto-assign habilitado |

### 4.1 Rota API (implementado)

**Verificado no código (jun/2026):** `custom/app/controllers/api/v1/accounts/calls_controller.rb`

```ruby
# PATCH /api/v1/accounts/:account_id/calls/:id
# Sem user id no body — o backend usa Current.user
# Só preenche accepted_by_agent_id quando provider wavoip e campo ainda vazio
```

Autorização: `authorize @call.inbox, :show?`. Spec: `spec/custom/controllers/api/v1/accounts/calls_controller_spec.rb`.

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
| `caller` | `{ phone, name }` | `{ phone, name? }` |
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

## 6. Push com aba fechada (pós-MVP)

Web Push pode avisar sobre uma chamada, mas não mantém a conexão SDK nem a oferta viva.
Portanto é best-effort e não faz parte do critério de atendimento inbound.

Se implementado, usar o pipeline de `Notification`/VAPID existente, respeitar
preferências do usuário e enviar apenas deep-link para a conversa. Não prometer botão
“aceitar” nem entrega antes da expiração da oferta.

---

## 7. Logging e privacidade

| Dado | Log produção |
|------|--------------|
| `device_token` | nunca |
| `webhook_key` | nunca |
| Payload completo | só `development` / spike |
| Produção | `type`, `action`, `whatsapp_call_id`, `status`, `inbox_id` |
