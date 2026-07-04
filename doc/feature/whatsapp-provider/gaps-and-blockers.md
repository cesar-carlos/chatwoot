# Lacunas e bloqueios no código atual

Inventário de pontos no Chatwoot que **impedem ou dificultam** providers alternativos. Baseado no código em jun/2026.

**Status consolidado:** [STATUS.md](./STATUS.md)

---

## Resumo executivo

| Severidade | Lacuna | Estado fork (jun/2026) |
|------------|--------|------------------------|
| 🔴 Bloqueante | `PROVIDERS` whitelist | ✅ **`evolution`**, **`evolution_go`** · ❌ `zapi`, `notificame` pendentes |
| 🔴 Bloqueante | Dispatch incoming gateway | ✅ prepend job + normalizer para **`evolution`** |
| 🟠 Alto | Janela 24h forçada | ✅ bypass para **`evolution`** via prepend |
| 🟠 Alto | `process_response` formato Meta | ✅ override em `EvolutionService` |
| 🟠 Alto | Formato webhook proprietário | ✅ `EvolutionNormalizer` |
| 🟡 Médio | Frontend só cloud/default | ⚠️ parcial — wizard Evolution em `custom/` |
| 🟡 Médio | `phone_number` UNIQUE global | Documentado — 1 inbox/número |
| 🟢 Baixo | Campanhas, CSAT, health cloud | Gates cloud-only — OK para gateway |
| 🟠 Alto | Autenticação do webhook `evolution` | ✅ **implementado** — token URL + `apikey` body/header, ver §2.1 (revisão jul/2026 corrigiu a doc, que ainda descrevia como pendente) |

---

## 1. Modelo `Channel::Whatsapp`

### 1.1 Whitelist de providers

**Upstream (sem fork):**

```ruby
PROVIDERS = %w[default whatsapp_cloud].freeze
```

**Fork atual:**

```29:30:app/models/channel/whatsapp.rb
  # FORK: gateway providers — evolution (Baileys/Node), evolution_go (whatsmeow/Go) (custom/)
  PROVIDERS = %w[default whatsapp_cloud evolution evolution_go].freeze
```

| Provider | Em `PROVIDERS` | Código `custom/` |
|----------|----------------|------------------|
| `evolution` | ✅ | ✅ |
| `evolution_go` | ✅ | ✅ Fase 0–1 (texto + QR + health) |
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

**Impacto:** gateways não passam por HMAC Meta — OK hoje (retorna `false`).

**Mitigação implementada (`evolution`):** `Webhooks::EvolutionController` dedicado (rota própria, não o controller Meta) exige `token` na URL **ou** `apikey` no body/header do webhook, validados com `ActiveSupport::SecurityUtils.secure_compare`; `apikey` é removida do payload antes de ir para o Sidekiq. Rate limit por instância+IP via Rack::Attack. **Ainda em aberto:** IP allowlist e teste explícito da variante via header `apikey` (hoje só body é testado).

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

- [x] Documentação completa
- [x] `# FORK:` `evolution_go` em PROVIDERS
- [x] Código `custom/.../evolution_go/` (Fase 0–1)
- [x] Gates UI `isGatewayWhatsAppChannel`
- [x] Health tab + wizard server check
- [ ] E2E com instância operador — [evolution-go/validation-checklist.md](./evolution-go/validation-checklist.md)
- [ ] Fase 2 — mídia, READ_RECEIPT, settings sync

### Outros gateways

- [ ] Z-API / NotificaMe — após piloto estável

---

## 9. Revisão de código e correções (2026-07-04)

Revisão completa do provider `evolution` (core/dispatch, webhook inbound, serviços REST/jobs, frontend). Achados e correções aplicadas nesta rodada:

| Área | Correção |
|------|----------|
| `EvolutionService#validate_provider_config?` | Cache de validação de conexão agora é invalidado em **qualquer** mudança de status (antes só invalidava se `state != 'open'`, deixando um `false` em cache logo após conectar) |
| `Custom::Channel::Whatsapp#sync_evolution_provider_to_api` | `settings_sync_error` só é limpo quando uma sync de fato ocorreu (antes era limpo mesmo sem chamada à API) |
| `EvolutionService#send_message` | Passou a capturar `ApiError` de rede/timeout e marcar a mensagem como `failed` com nota privada, em vez de deixá-la presa em "enviando" |
| `dashboard_provider_config` | `webhook_token` agora é mascarado como `api_key`/`proxy_password` |
| `Custom::Channel::Whatsapp#provider_service` | Fallback do registry para `'evolution'` sem serviço resolvido agora levanta erro explícito em vez de cair silenciosamente no provider 360dialog |
| `WebhookDispatcher` | `SEND_MESSAGE_UPDATE` (`send.message.update`) tratado como `MESSAGES_EDITED`; itens de payload malformados (`data` não-Hash) agora geram log em vez de serem ignorados silenciosamente |
| `Import::RemoteJidsCollector` | Corrigido para parsear o formato aninhado `{ contacts: { records: [...] } }` da API (antes só funcionava com array flat, podendo coletar zero JIDs silenciosamente) |
| `Import::Runtime` / `ImportService` | Recovery automático de import travado em `running` após crash, via heartbeat (`import_heartbeat_at`) — antes ficava bloqueado indefinidamente sem `force: true` manual |
| `Import::MessagesImporter` | Mensagens inbound do import agora usam o mesmo `MessageMutex` do caminho de webhook, evitando corrida com mensagens ao vivo |
| `PhoneOutgoingSyncService` | Dedup lock (Redis, TTL 1 dia) agora é liberado se o processamento falhar após ser adquirido — antes travava por até 24h; unlock só ocorre se o lock foi de fato adquirido por esta instância (não derruba lock de outro worker) |
| `ContactEnrichmentService` | `mark_enriched!` só roda se o fetch de perfil realmente teve sucesso — antes marcava como "enriquecido" mesmo em falha, escondendo o contato de novas tentativas por 24h |
| `ApiClient` | Retry único (com backoff curto) para timeout/erro de rede e para respostas 5xx; respostas não-JSON agora geram `ApiError` catchável em vez de `NoMethodError` opaco downstream |
| `EvolutionSettingsPage.vue` | Formulário não é mais resetado a cada atualização de `provider_config` vinda de polling/cable (só recarrega ao trocar de inbox); status de import continua atualizando ao vivo |
| `useEvolutionHealthConnection.js` | `restart()` só abre o modal de QR se o restart realmente teve sucesso |
| `EvolutionQrScanModal.vue` | `connectionStatus === 'close'` sem erro explícito de refresh agora é tratado como estado de espera (spinner), não como erro — evita UI de erro logo após um logout intencional |
| `EvolutionConnectionChannel` / `evolution_connection` (REST) | Autorização unificada como admin-only (`:update?`) — antes o cable aceitava administrador não atribuído ao inbox e o REST usava `:show?` (agente atribuído), permitindo combinações inconsistentes de acesso a dado sensível (QR/pairing code) |

Specs novos/atualizados cobrindo cada item acima em `spec/custom/` e `custom/app/javascript/dashboard/**/specs/`.
