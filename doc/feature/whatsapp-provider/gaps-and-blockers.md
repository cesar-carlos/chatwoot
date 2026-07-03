# Lacunas e bloqueios no código atual

Inventário de pontos no Chatwoot que **impedem ou dificultam** providers alternativos. Baseado no código em jun/2026.

**Status consolidado:** [STATUS.md](./STATUS.md)

---

## Resumo executivo

| Severidade | Lacuna | Estado fork (jun/2026) |
|------------|--------|------------------------|
| 🔴 Bloqueante | `PROVIDERS` whitelist | ✅ **`evolution`** adicionado · ❌ `evolution_go`, `zapi`, `notificame` pendentes |
| 🔴 Bloqueante | Dispatch incoming gateway | ✅ prepend job + normalizer para **`evolution`** |
| 🟠 Alto | Janela 24h forçada | ✅ bypass para **`evolution`** via prepend |
| 🟠 Alto | `process_response` formato Meta | ✅ override em `EvolutionService` |
| 🟠 Alto | Formato webhook proprietário | ✅ `EvolutionNormalizer` |
| 🟡 Médio | Frontend só cloud/default | ⚠️ parcial — wizard Evolution em `custom/` |
| 🟡 Médio | `phone_number` UNIQUE global | Documentado — 1 inbox/número |
| 🟢 Baixo | Campanhas, CSAT, health cloud | Gates cloud-only — OK para gateway |

---

## 1. Modelo `Channel::Whatsapp`

### 1.1 Whitelist de providers

**Upstream (sem fork):**

```ruby
PROVIDERS = %w[default whatsapp_cloud].freeze
```

**Fork atual:**

```29:30:app/models/channel/whatsapp.rb
  # FORK: evolution — Baileys gateway via Evolution API (custom/)
  PROVIDERS = %w[default whatsapp_cloud evolution].freeze
```

| Provider | Em `PROVIDERS` | Código `custom/` |
|----------|----------------|------------------|
| `evolution` | ✅ | ✅ |
| `evolution_go` | ❌ | ❌ (doc pronta) |
| `zapi` | ❌ | ❌ |
| `notificame` | ❌ | ❌ |

**Próximo `# FORK:`** ao implementar Go: adicionar `'evolution_go'` na mesma linha — [evolution-go/coordination-with-evolution-api.md](./evolution-go/coordination-with-evolution-api.md).

### 1.2 Dispatch `provider_service`

**Upstream:** non-cloud → 360dialog (incorreto para gateway).

**Mitigação implementada:** prepend + `MessagingProvider::Registry` — ver `custom/app/models/custom/channel/whatsapp.rb`.

### 1.3 `provider_config` heterogêneo

| Provider | Campos típicos |
|----------|----------------|
| `default` | `api_key` |
| `whatsapp_cloud` | `api_key`, `phone_number_id`, `business_account_id`, `webhook_verify_token`, `source`, `calling_enabled` |
| Gateway | `base_url`, `api_key`, `instance_name`, `instance_id` (Z-API), `connection_status` |

**Impacto:** validação remota (`validate_provider_config`) e serializers JSON da inbox precisam ser por provider.

**Mitigação:** cada `*Service` implementa `validate_provider_config?`; não centralizar validação além do delegate atual.

### 1.4 Índice único em `phone_number`

```32:32:app/models/channel/whatsapp.rb
  validates :phone_number, presence: true, uniqueness: true
```

**Impacto:** um número = um inbox `Channel::Whatsapp`. Dois tiles (mensagens + voz) com o mesmo número exigem **dois modelos** (`Channel::Whatsapp` + `Channel::WhatsappCall`) ou relaxar unique no fork.

---

## 2. Webhooks e incoming

### 2.1 Controller — assinatura Meta

```36:42:app/controllers/webhooks/whatsapp_controller.rb
  def meta_signature_verification_required?
    return true if whatsapp_channel.blank?
    return false unless whatsapp_channel.provider == 'whatsapp_cloud'
    ...
  end
```

**Impacto:** gateways não passam por HMAC Meta — OK hoje (retorna `false`). **Novo risco:** sem auth alternativa, endpoint fica aberto.

**Mitigação:** `GatewayWebhookAuth` — token na URL, header `apikey`, ou IP allowlist; implementar no controller via prepend.

### 2.2 Job — switch de incoming

```79:86:app/jobs/webhooks/whatsapp_events_job.rb
  def handle_message_events(channel, params)
    case channel.provider
    when 'whatsapp_cloud'
      Whatsapp::IncomingMessageWhatsappCloudService.new(...).perform
    else
      Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: params).perform
    end
  end
```

**Impacto:** gateway precisa ou (a) normalizar para payload **flat** 360dialog-like antes do `else`, ou (b) novo branch.

**Mitigação preferida (A) — implementada para `evolution`:**

Ver `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` — normaliza antes de `IncomingMessageService`.

### 2.3 Enterprise — calls intercept

`Enterprise::Webhooks::WhatsappEventsJob` trata `field=calls` **antes** de mensagens. Gateways **não** devem passar por esse prepend — payloads sem `entry/changes` não disparam `call_event?`.

### 2.4 Resolução de canal

- URL: `/webhooks/whatsapp/:phone_number` → `find_by(phone_number:)`
- Payload WABA: `object=whatsapp_business_account` → match por `display_phone_number` + `phone_number_id`

**Impacto:** gateway com webhook por `instance_id` precisa de rota dedicada **ou** mapear `instance_name` → `phone_number` no `provider_config`.

**Evolution (decisão fechada):** rota `POST /webhooks/evolution/:instance_name` + lookup por `instance_name` — [evolution-api/decisions.md](./evolution-api/decisions.md) §1–3. Responder HTTP 200 rápido no controller; retry da Evolution coberto por dedup Redis em `IncomingMessageBaseService` ([decisions.md §14](./evolution-api/decisions.md)). ADR prepend vs job dedicado: [decisions.md §16](./evolution-api/decisions.md).

---

## 3. Envio e regras de negócio

### 3.1 Janela de 24 horas (Chatwoot, não Meta)

```27:28:app/services/conversations/message_window_service.rb
    when 'Channel::Whatsapp'
      MESSAGING_WINDOW_24_HOURS
```

**Impacto:** mesmo sem Cloud API, Chatwoot **força template** após 24h via `SendOnWhatsappService`:

```9:14:app/services/whatsapp/send_on_whatsapp_service.rb
    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
```

**Mitigação:** implementada para `evolution` — prepend retorna `nil` (sem janela).

### 3.2 `process_response` assume formato Meta

```34:41:app/services/whatsapp/providers/base_service.rb
    if response.success? && parsed_response['error'].blank?
      parsed_response['messages'].first['id']
```

**Impacto:** gateways com `{ key: { id: "..." } }` (Evolution) ou `{ messageId: "..." }` (Z-API) falham ao extrair `source_id`.

**Mitigação:** override `process_response` — feito em `Custom::Whatsapp::Providers::EvolutionService`.

### 3.3 Campanhas e CSAT

- `Whatsapp::OneoffCampaignService#validate_provider!` → só `whatsapp_cloud`
- `CsatTemplateManagementService` → paths cloud-only

**Impacto:** nenhum para MVP gateway — features simplesmente indisponíveis.

---

## 4. Frontend

### 4.1 Setup de inbox

`Whatsapp.vue` oferece Cloud, Twilio e **Evolution** (fork). 360dialog via `?provider=360dialog`.

**Pendente:** card **Evolution Go** quando `evolution_go` for implementado.

### 4.2 Gates por provider

`inboxMixin.js` / `useInbox.js`:

- `isAWhatsAppCloudChannel` → templates UI, voice PTT, campanhas
- `is360DialogWhatsAppChannel` → alguns bypasses em `ReplyBox.vue`

**Impacto:** gateway precisa de `isGatewayWhatsAppChannel` ou registry de capabilities para não mostrar features cloud-only.

### 4.3 Settings e health

`Settings.vue` e `whatsapp_health_management.rb` assumem cloud para health/register_webhook.

**Mitigação:** health próprio do gateway (`ConnectionService#status`) em settings fork.

---

## 5. Voz (fora do escopo de mensagens)

Documentação completa reanalisada em jun/2026: [whatsapp-voice/README.md](../whatsapp-voice/README.md).

| Gate | Arquivo | Valor para gateway |
|------|---------|-------------------|
| `voice_calling_supported?` | `channel/whatsapp.rb` | `false` (só `whatsapp_cloud`) |
| `enable_voice_calling!` | idem | raise se não cloud |
| Enterprise prepend | `WhatsappCloudService` | Graph `/calls` |
| `useWhatsappCallSession` | frontend (wrapper ~33 linhas) | Core em `useWebRtcCallSession.js` |
| `actionCable.js` | frontend | WhatsApp inline; Wavoip via registry |
| `voice_call.permission_granted` | backend broadcast | ✅ Handler FE (toast jun. 2026) |

**Conclusão:** mensagens gateway e voz são **projetos separados** no fork.

| Estratégia voz | Doc |
|----------------|-----|
| Meta oficial (atual) | [architecture-and-flow.md](../whatsapp-voice/architecture-and-flow.md) |
| CPaaS proxy Meta-like | [second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md) |
| Gateway não oficial | [second-provider-strategy.md](../whatsapp-voice/second-provider-strategy.md) + [provider-comparison.md](./provider-comparison.md) |

---

## 6. Enterprise vs OSS

| Área | OSS | Enterprise |
|------|-----|------------|
| Envio mensagens | `WhatsappCloudService` | prepend vazio para calls no cloud |
| Incoming calls | — | `Enterprise::Webhooks::WhatsappEventsJob` |
| `WhatsappCallsController` | — | EE only |
| `channel_voice` flag | — | EE feature |

Providers alternativos no fork podem viver em `custom/` **sem** depender de EE para mensagens. Voz gateway é projeto `custom/` paralelo.

---

## 7. O que já funciona sem mudança

Reutilizar **com payload normalizado**:

| Componente | Reuso |
|------------|-------|
| `Whatsapp::IncomingMessageBaseService` | Statuses, dedup Redis, contatos, mídia, reply |
| `Whatsapp::IncomingMessageService` | Payload flat (padrão 360dialog) |
| `Whatsapp::SendOnWhatsappService` | Orquestra envio (ajustar janela 24h) |
| `SendReplyJob` | Dispatch genérico por `channel_type` |
| `ContactInboxBuilder` | `source_id` = telefone/JID normalizado |
| `Channel::Whatsapp` delegates | `send_message`, `send_template`, `sync_templates` |

---

## 8. Checklist pré-implementação

### Evolution API (`evolution`) — Node

- [x] Provider key + `PROVIDERS` — [evolution-api/decisions.md](./evolution-api/decisions.md)
- [x] Fixtures T0 REST — `spec/fixtures/evolution/`
- [x] Registry + prepends Fase 0
- [x] Normalizer + webhook route
- [x] Bypass 24h + templates noop
- [ ] E2E webhook inbound + wizard QR — [validation-checklist](./evolution-api/validation-checklist.md) §2–4 (correções de confiabilidade 2026-07-03 prontas; smoke manual pendente)

### Evolution Go (`evolution_go`)

- [x] Documentação completa (~93% — melhorias 22/jun/2026)
- [ ] Spike fixtures P1 — [evolution-go/tasks.md](./evolution-go/tasks.md)
- [ ] `# FORK:` `evolution_go` em PROVIDERS
- [ ] Código `custom/.../evolution_go/`

### Outros gateways

- [ ] Z-API / NotificaMe — após piloto estável
