# Lacunas e bloqueios no código atual

Inventário de pontos no Chatwoot que **impedem ou dificultam** providers alternativos (Evolution, Z-API, NotificaMe, etc.) sem adaptação no fork. Baseado na análise do código em jun/2026.

**Relacionados:** [architecture-current-whatsapp.md](./architecture-current-whatsapp.md) · [implementation-decision-tree.md](./implementation-decision-tree.md) · [feature-mapping.md](./feature-mapping.md)

---

## Resumo executivo

| Severidade | Lacuna | Mitigação recomendada |
|------------|--------|------------------------|
| 🔴 Bloqueante | `PROVIDERS` whitelist + validação no model | `# FORK:` mínimo na constante |
| 🔴 Bloqueante | Dispatch incoming por `case provider` no job | Prepend `Webhooks::WhatsappEventsJob` + normalizer |
| 🟠 Alto | Janela 24h forçada em `MessageWindowService` | Capability `unlimited_session?` + prepend ou config por provider |
| 🟠 Alto | `SendOnWhatsappService` força template fora da janela | Mesma capability ou override em `can_reply?` |
| 🟠 Alto | Formato webhook proprietário | `GatewayNormalizer` → payload flat canônico |
| 🟡 Médio | Frontend só reconhece `whatsapp_cloud` e `default` | Registry JS de capabilities + helpers em `custom/` |
| 🟡 Médio | `phone_number` UNIQUE global | Aceitar 1 inbox por número; documentar limite |
| 🟢 Baixo | Campanhas, CSAT, health, embedded signup | Gates já são `whatsapp_cloud` only — ignorar no gateway |

---

## 1. Modelo `Channel::Whatsapp`

### 1.1 Whitelist de providers

```28:31:app/models/channel/whatsapp.rb
  PROVIDERS = %w[default whatsapp_cloud].freeze
  ...
  validates :provider, inclusion: { in: PROVIDERS }
```

**Impacto:** impossível persistir `provider: 'evolution'` sem alterar o model.

**Mitigação (merge-safe possível):**

```ruby
# app/models/channel/whatsapp.rb
# FORK: allow gateway providers handled by custom adapters.
PROVIDERS = %w[default whatsapp_cloud evolution zapi notificame].freeze
```

`prepend` sozinho não resolve este ponto: a validação usa a constante congelada no load da classe. Deixe o diff restrito à constante e use `custom/`/prepend para o dispatch.

### 1.2 Dispatch hardcoded de `provider_service`

```64:70:app/models/channel/whatsapp.rb
  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end
```

**Impacto:** qualquer provider que não seja `whatsapp_cloud` cai no **360dialog** — incorreto para gateways.

**Mitigação:** registry em `custom/` (ver [implementation-plan-second-whatsapp-provider.md](./implementation-plan-second-whatsapp-provider.md) Fase 0).

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

**Mitigação preferida (A):**

```ruby
# custom — prepend Webhooks::WhatsappEventsJob
def handle_message_events(channel, params)
  normalized = GatewayWebhookRouter.normalize(channel, params)
  super(channel, normalized || params)
end
```

Payload canônico mínimo para `IncomingMessageBaseService`:

```ruby
{ contacts: [...], messages: [...], statuses: [...] }
```

### 2.3 Enterprise — calls intercept

`Enterprise::Webhooks::WhatsappEventsJob` trata `field=calls` **antes** de mensagens. Gateways **não** devem passar por esse prepend — payloads sem `entry/changes` não disparam `call_event?`.

### 2.4 Resolução de canal

- URL: `/webhooks/whatsapp/:phone_number` → `find_by(phone_number:)`
- Payload WABA: `object=whatsapp_business_account` → match por `display_phone_number` + `phone_number_id`

**Impacto:** gateway com webhook por `instance_id` precisa de rota dedicada **ou** mapear `instance_name` → `phone_number` no `provider_config`.

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

**Mitigação:** para providers não oficiais, prepend `MessageWindowService` retornando `nil` (sem janela) ou capability `session_window: false` no provider.

### 3.2 `process_response` assume formato Meta

```34:41:app/services/whatsapp/providers/base_service.rb
    if response.success? && parsed_response['error'].blank?
      parsed_response['messages'].first['id']
```

**Impacto:** gateways com `{ key: { id: "..." } }` (Evolution) ou `{ messageId: "..." }` (Z-API) falham ao extrair `source_id`.

**Mitigação:** override `process_response` no provider filho ou helper `extract_message_id(response)`.

### 3.3 Campanhas e CSAT

- `Whatsapp::OneoffCampaignService#validate_provider!` → só `whatsapp_cloud`
- `CsatTemplateManagementService` → paths cloud-only

**Impacto:** nenhum para MVP gateway — features simplesmente indisponíveis.

---

## 4. Frontend

### 4.1 Setup de inbox

`Whatsapp.vue` oferece Cloud e Twilio; 360dialog via `?provider=360dialog`. **Sem card gateway.**

**Mitigação:** card fork em `Whatsapp.vue` com `// FORK:` import ou componente em `custom/`.

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
| `useWhatsappCallSession` | frontend (~456 linhas) | `/whatsapp_calls` Meta |
| `actionCable.js` | frontend | Filtra `provider === 'whatsapp'` |
| `voice_call.permission_granted` | backend broadcast | **Sem handler FE** |

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

- [ ] Provider key definido (`evolution`, `zapi`, `notificame`, …)
- [ ] Contrato webhook congelado (exemplo JSON real)
- [ ] Mapeamento `source_id` (telefone vs `@s.whatsapp.net` vs LID)
- [ ] Estratégia auth webhook documentada
- [ ] Decisão janela 24h (manter regra Chatwoot ou bypass)
- [ ] Decisão templates (sync local vs texto livre)
- [ ] Rota webhook: reutilizar `/webhooks/whatsapp/:phone` ou dedicada
- [ ] `rg "FORK:"` e `bin/fork-inventory` após cada fase
