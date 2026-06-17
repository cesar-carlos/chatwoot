# Arquitetura atual do WhatsApp no Chatwoot

Como o Chatwoot abstrai (e onde não abstrai) providers WhatsApp hoje. Referências de código do fork em jun/2026.

---

## Modelo e dispatch de provider

```28:70:app/models/channel/whatsapp.rb
  PROVIDERS = %w[default whatsapp_cloud].freeze
  ...
  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end
```

| Campo / método | `default` (360dialog) | `whatsapp_cloud` |
|---|---|---|
| `provider_config` | `api_key` | `api_key`, `phone_number_id`, `business_account_id`, `webhook_verify_token`, `source`, `calling_enabled` |
| Validação remota | POST webhook config 360dialog | GET `message_templates` Graph API |
| Webhook auto-setup | Não (só na validação) | `after_create` + `WebhookSetupService` |
| Chamadas | `voice_calling_supported?` → **false** | **true** (Enterprise) |

**Nota:** 360dialog é BSP **oficial** (parceiro Meta), não API não oficial. Serve como referência de "segundo provider no mesmo `Channel::Whatsapp`".

---

## BaseService — contrato mínimo

```11:32:app/services/whatsapp/providers/base_service.rb
class Whatsapp::Providers::BaseService
  def send_message(_phone_number, _message); end
  def send_template(_phone_number, _template_info, _message); end
  def sync_template; end          # typo no comentário; implementação usa sync_templates
  def validate_provider_config; end
  def error_message; end
  # + helpers: process_response, create_button/list payloads
end
```

Implementações concretas também expõem `media_url`, `api_headers`; cloud adiciona CSAT template CRUD via `CsatTemplateService`.

---

## Diagrama — fluxo de providers e incoming

```mermaid
flowchart TB
  subgraph Transport
    WC[Webhooks::WhatsappController]
    WEJ[Webhooks::WhatsappEventsJob]
  end

  subgraph Domain
    CH[Channel::Whatsapp]
    PS[provider_service]
  end

  subgraph Providers
  B[BaseService]
  C[WhatsappCloudService]
  D[Whatsapp360DialogService]
  end

  subgraph Incoming
  IMS[IncomingMessageService<br/>flat payload]
  IMC[IncomingMessageWhatsappCloudService<br/>entry/changes/value]
  IMB[IncomingMessageBaseService]
  end

  WC --> WEJ
  WEJ -->|provider switch| IMS
  WEJ -->|whatsapp_cloud| IMC
  IMS --> IMB
  IMC --> IMB
  CH --> PS
  PS --> C
  PS --> D
  C --> B
  D --> B
  CH -->|delegate| PS
```

---

## Webhooks

- **Rota:** `POST/GET /webhooks/whatsapp/:phone_number` (`config/routes.rb`)
- **Controller:** `Webhooks::WhatsappController` — verificação Meta (`MetaTokenVerifyConcern`), assinatura HMAC só para `whatsapp_cloud`
- **Job:** `Webhooks::WhatsappEventsJob` — mutex por contato, echo `smb_message_echoes` (cloud), dispatch:

```79:86:app/jobs/webhooks/whatsapp_events_job.rb
  def handle_message_events(channel, params)
    case channel.provider
    when 'whatsapp_cloud'
      Whatsapp::IncomingMessageWhatsappCloudService.new(...).perform
    else
      Whatsapp::IncomingMessageService.new(...).perform
    end
  end
```

**Enterprise** (`enterprise/app/jobs/enterprise/webhooks/whatsapp_events_job.rb`): intercepta `field=calls` e `call_permission_reply` **antes** de mensagens — 100% formato Meta.

---

## Incoming messages

- **Base compartilhada:** `Whatsapp::IncomingMessageBaseService` — statuses, dedup Redis, contatos, mídia, reply context, unsupported
- **360dialog / flat payload:** `params` direto com `contacts` + `messages` (ver spec)
- **Cloud / nested:** `params[:entry][0][:changes][0][:value]` via `IncomingMessageWhatsappCloudService`
- Download de mídia: 360dialog usa URL direta; cloud faz GET intermediário na Graph API

---

## Envio

- `Whatsapp::SendOnWhatsappService` → `channel.send_message` / `channel.send_template`
- Janela 24h: `Conversations::MessageWindowService` força template fora da janela
- Campanhas one-off: **somente** `whatsapp_cloud` (`Whatsapp::OneoffCampaignService#validate_provider!`)

---

## Frontend — setup de inbox

| Componente | Função |
|---|---|
| `Whatsapp.vue` | Seleção: WhatsApp Cloud (embedded/manual) ou Twilio |
| `CloudWhatsapp.vue` | Manual: `provider: 'whatsapp_cloud'` + IDs Meta |
| `360DialogWhatsapp.vue` | Legado; acesso via `?provider=360dialog` (não no seletor principal) |
| `WhatsappEmbeddedSignup.vue` | OAuth Meta via `useWhatsappEmbeddedSignup` |
| `WhatsappCall.vue` / `whatsapp_call` | Canal separado no `ChannelFactory` — embedded signup + enable calling |
| `WhatsappCallingPage.vue` | Settings: enable/disable calling (só cloud) |

`inboxMixin.js`: `isAWhatsAppCloudChannel`, `is360DialogWhatsAppChannel`; voz via `getVoiceCallProvider()` → `'whatsapp'` se `voice_enabled`.

---

## 360dialog vs cloud — o que já existe vs cloud-only

| Área | default/360dialog | whatsapp_cloud |
|------|-------------------|----------------|
| Texto, mídia link, interativos | ✅ `Whatsapp360DialogService` | ✅ |
| Templates aprovados | ✅ sync `/configs/templates` + namespace | ✅ Graph sync |
| Status delivery | ✅ flat `statuses` | ✅ nested |
| Reply/context | Parcial (sem `whatsapp_reply_context` no 360) | ✅ |
| Voice messages (PTT) | ❌ | ✅ `voice: true` + content-type |
| Embedded signup | ❌ | ✅ |
| Campanhas | ❌ | ✅ |
| CSAT template API | ❌ | ✅ |
| Coexistence echoes | ❌ | ✅ |
| Chamadas | ❌ | ✅ Enterprise |

---

## Acoplamento Meta Cloud API (lista para novo provider)

| Feature | Arquivos-chave | Só cloud? |
|---|---|---|
| Graph API `/messages`, `/media` | `WhatsappCloudService` | Envio cloud |
| Templates WABA sync | `fetch_whatsapp_templates` → Graph | Sim |
| Embedded Signup | `EmbeddedSignupService`, `TokenExchangeService`, `FacebookApiClient` | Sim |
| Webhook WABA subscribe | `WebhookSetupService`, `FacebookApiClient#subscribe_waba_webhook` | Sim |
| Health / reauth | `HealthService`, `ReauthorizationService` | Sim |
| SMB message echoes | `WhatsappEventsJob#message_echo_event?` | Sim |
| Campanhas WhatsApp | `OneoffCampaignService` | Sim |
| CSAT templates auto | `CsatTemplateService` | Sim |
| Chamadas WebRTC | `Enterprise::Whatsapp::Providers::WhatsappCloudService`, `IncomingCallService` | Sim |
| Assinatura webhook | `Webhooks::WhatsappController#meta_signature_verification_required?` | Cloud / embedded |

---

## Conclusão

O padrão de provider existe para **envio** e validação, mas **recebimento** e features avançadas estão acoplados ao formato de payload (flat vs nested Meta) ou exclusivos do cloud. Um terceiro provider precisa de normalizer de webhook e não deve editar os serviços cloud existentes.
