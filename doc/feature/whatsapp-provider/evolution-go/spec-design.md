# Spec design — classes `custom/` Evolution Go

> **Nota (jul/2026):** Contratos históricos de planejamento — a implementação em `custom/` é a fonte de verdade. Divergências conhecidas foram corrigidas nesta revisão (downloadmedia only, history-sync body, user_check array).

Contratos públicos das classes do provider. Espelha [../evolution-api/spec-design.md](../evolution-api/spec-design.md).

---

## `Custom::Whatsapp::EvolutionGo::ApiError`

```ruby
class Custom::Whatsapp::EvolutionGo::ApiError < StandardError
  attr_reader :status, :body, :base_message

  def initialize(message = nil, status: nil, body: nil)
    @status = status
    @body = body
    @base_message = message
    super(log_message)
  end

  def log_message   # inclui status + body — para logs
  def user_message  # versão amigável para UI — sem detalhe interno em produção

  def self.compose_message(message, status, body)
  def self.extract_message(body)  # dig('error', 'message') || body['message'] || body.to_s
end
```

Elevar quando `response.code >= 400` no `ApiClient#raise_unless_success!`. Mensagens `error.message` do OpenAPI Go em `user_message` — ver [error-handling.md](./error-handling.md).

---

## `Custom::Whatsapp::EvolutionGo::ApiClient`

```ruby
# initialize(base_url:, global_api_key: nil, instance_token: nil, instance_name: nil)

# Health (sem auth)
def server_ok                    # GET /server/ok

# Admin (global_api_key)
def create_instance(name:, token: nil, proxy: nil)  # POST /instance/create
def list_instances                                     # GET /instance/all
def delete_instance(instance_id)                       # DELETE /instance/delete/{instanceId}
def instance_info(instance_id)                         # GET /instance/info/{instanceId}
def delete_proxy(instance_id)                          # DELETE /instance/proxy/{instanceId}

# Instance (instance_token)
def connect(webhook_url:, subscribe:, **opts)          # POST /instance/connect
def disconnect                                         # POST /instance/disconnect
def logout                                             # DELETE /instance/logout
def qr_code                                            # GET /instance/qr
def pair(phone:, subscribe: nil)                       # POST /instance/pair
def connection_status                                  # GET /instance/status
def send_text(number:, text:, quoted: nil)             # POST /send/text
def send_media(number:, type:, url:, caption: nil, filename: nil)  # Fase 2 — POST /send/media

# Fase 2
def get_advanced_settings(instance_id)                 # GET /instance/{id}/advanced-settings
def update_advanced_settings(instance_id, settings:)    # PUT /instance/{id}/advanced-settings
def download_media(message_payload)                    # POST /message/downloadmedia only (no downloadimage fallback)
def react(number:, id:, reaction:, from_me: false, participant: nil)  # POST /message/react

# private
def admin_headers    # { 'apikey' => global_api_key }
def instance_headers # { 'apikey' => instance_token }
def unwrap(response) # response.parsed_response['data'] || {}
def dig_field(hash, *keys)  # casing-tolerant lookup — ver §26 decisions.md
def post(path, body, headers:)
def get(path, headers:)
```

**Diferença vs Evolution API client:** dual auth; sem `set_webhook` separado; `connect` inclui webhook.

### `dig_field` — normalização de casing (ADR §26)

```ruby
# Tenta cada chave e variantes camelCase/PascalCase no hash
def dig_field(hash, *keys)
  return nil if hash.blank?

  keys.lazy.map { |key|
    variants = [key, key.to_s.camelize(:lower), key.to_s.camelize]
    variants.map { |k| hash[k] }.find(&:present?)
  }.find(&:present?)
end

# Exemplos:
# dig_field(data, 'connected', 'Connected')
# dig_field(data, 'jid', 'myJid', 'JID', 'MyJid')
# dig_field(settings, 'reject_call', 'rejectCall', 'rejectCalls')
```

### `download_media` (ADR §25)

```ruby
def download_media(message_payload)
  post('/message/downloadmedia', { message: message_payload }, headers: instance_headers)
end
```

Sem fallback `/message/downloadimage` — endpoint ausente do swagger atual (jul/2026).

---

## `Custom::Whatsapp::EvolutionGo::ConnectionService`

```ruby
# initialize(channel) — Channel::Whatsapp provider evolution_go

def provision_new_inbox!(params)  # create + generate webhook_token + connect
def connect_existing!(params)     # token + instance_name informados (global_api_key opcional)
def handle_event(envelope)        # CONNECTION, QRCODE webhooks
def sync_phone_number!            # GET status → jid via ApiClient#dig_field
def reconnect!                    # disconnect (opcional) + connect com webhookUrl + subscribe — ADR §23/§24
def sync_settings!(settings)      # PUT advanced-settings — Fase 2
def broadcast_connection_event(type, payload)
def webhook_url                   # FRONTEND_URL/webhooks/evolution_go/{name}?token={secret}
```

**Reconnect:** sempre `connect` com webhook — **não** chamar `POST /instance/reconnect` (ADR §24).

---

## `Custom::Whatsapp::Providers::EvolutionGoService`

```ruby
# < Whatsapp::Providers::BaseService

def send_message(phone_number, message)
def validate_provider_config?        # server_ok + GET /instance/status
def media_url(_media_id); end      # Fase 2
def api_headers; end

# protected
def process_response(response)
  parsed = response.parsed_response
  client.dig_field(parsed['data'] || {}, 'Info')&.dig('ID') ||
    parsed.dig('data', 'Info', 'ID') ||
    parsed.dig('data', 'messageId')
end
```

---

## `Custom::Whatsapp::Webhooks::EvolutionGoNormalizer`

```ruby
# initialize(channel, envelope)
# envelope: { 'event', 'instance', 'data' }

def perform
# return nil if filtered
# return { contacts:, messages: } flat hash
# ou { statuses: } para READ_RECEIPT (Fase 2)

def filtered?(data)
  # ignore_from_me_echo, ignore_groups (config); status@broadcast sempre
end

def extract_phone(key)
  # remoteJid / remoteJidAlt / LID
end
```

**Eventos suportados:**

| `event` | Output |
|---------|--------|
| `MESSAGE` | `{ contacts:, messages: }` |
| `READ_RECEIPT` | `{ statuses: }` via `EvolutionGoReadReceiptNormalizer` |
| `CONNECTION`, `QRCODE` | `nil` — ConnectionService |

---

## `Custom::Webhooks::EvolutionGoController`

```ruby
# before_action :authenticate_webhook!

def process_payload
  Webhooks::WhatsappEventsJob.perform_later(
    sanitized_job_payload.merge(
      evolution_go_instance_name: params[:instance_name],
      channel_id: @channel.id
    )
  )
  head :ok
end

def authenticate_webhook!
  @channel = Channel::Whatsapp.where(provider: 'evolution_go')
    .where("provider_config->>'instance_name' = ?", params[:instance_name]).first
  return head :not_found unless @channel

  secret = @channel.provider_config['webhook_token'].to_s.strip
  query_token = params[:token].to_s.strip
  bearer = request.headers['Authorization'].to_s.remove(/^Bearer /i).strip
  provided = query_token.presence || bearer
  return head :unauthorized unless secret.present? &&
    provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)
end

private

def sanitized_job_payload
  payload = params.to_unsafe_hash.except('controller', 'action', 'instance_name', 'token')
  payload.delete('instance')
  payload
end
```

> **Segurança de envelope:** o key `evolution_go_instance_name` em vez de `instance_name`/`instance` é intencional — impede que a detecção `evolution_envelope?` do prepend Node intercepte eventos Go. Ver [decisions.md §27](./decisions.md).

---

## `validate_provider_config?`

Validação em camadas (wizard vs inbox existente):

| Check | API | Header |
|-------|-----|--------|
| Servidor alcançável | `GET /server/ok` | nenhum |
| Token instância válido | `GET /instance/status` | `apikey: instance_token` |
| Admin key (modo criar) | `GET /instance/all` | `apikey: global_api_key` |

Retorna `true` se `server_ok` 2xx e `dig_field(status, 'connected', 'Connected')` truthy.

---

## `EvolutionGoConnectionChannel` (ActionCable)

Espelha `EvolutionConnectionChannel` (implementado para evolution node):

```ruby
class EvolutionGoConnectionChannel < ApplicationCable::Channel
  def subscribed
    inbox = current_account.inboxes.find(params[:inbox_id])
    channel = inbox.channel
    reject and return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
    reject and return unless inbox_accessible?(inbox)

    stream_from "evolution_go:connection:#{inbox.id}"
  end
end
```

`ConnectionService#broadcast_connection_event` emite para `evolution_go:connection:{inbox.id}`. Frontend `evolutionGoCableRegistry.js` + `useEvolutionGoQrSession.js` subscrevem para QR + connection status.

---

## Registry

```ruby
# custom/config/initializers/messaging_provider_registry.rb
# Formato idêntico ao do provider 'evolution' implementado — não usar bloco
MessagingProvider::Registry.register(
  'evolution_go',
  Custom::Whatsapp::Providers::EvolutionGoService
)
```

> O format do registry usa a classe, não um bloco. Ver `custom/config/initializers/messaging_provider_registry.rb` para referência.

---

## Prepend job

> **CRÍTICO — collision com evolution node:** O prepend evolution Node detecta `evolution_envelope?` verificando `params[:event].present? && params[:instance].present?`. Evolution Go tem o mesmo formato de envelope — sem cuidado, o prepend Node interceptaria e **descartaria** silenciosamente os eventos Go. Solução: o controller Go injeta `evolution_go_instance_name:` (não `:instance_name`/`:instance`), tornando o envelope invisível para `evolution_node_envelope?`. Ver [decisions.md §27](./decisions.md).

```ruby
module Custom::Webhooks::WhatsappEventsJobEvolutionGo
  def perform(params = {})
    params = params.with_indifferent_access
    return super(params) unless evolution_go_envelope?(params)

    channel = find_evolution_go_channel(params)
    unless channel
      Rails.logger.warn("[EVOLUTION_GO] unknown channel_id=#{params[:channel_id]}")
      return super(params)  # propaga — não descarta silenciosamente
    end

    dispatch_evolution_go_event(channel, params)
  end

  private

  def evolution_go_envelope?(params)
    # Detectar pelo campo único injetado pelo EvolutionGoController
    params[:evolution_go_instance_name].present? || params[:channel_id] && find_evolution_go_channel(params)
  end

  def find_evolution_go_channel(params)
    channel_id = params[:channel_id]
    Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_go') if channel_id.present?
  end

  def dispatch_evolution_go_event(channel, params)
    params[:event] = Custom::Whatsapp::EvolutionGo::EventNames.normalize(params[:event])

    case params[:event].to_s.upcase
    when 'MESSAGE'
      process_message_event(channel, params)  # delete/edit, fromMe echo, normalizer
    when 'SEND_MESSAGE'
      process_send_message_event(channel, params)
    when 'MESSAGE_DELETE', 'MESSAGES_DELETE', 'DELETE'
      process_delete_event(channel, params)
    when 'MESSAGES_EDITED', 'MESSAGE_EDIT', 'SEND_MESSAGE_UPDATE'
      process_edit_event(channel, params)
    when 'READ_RECEIPT', 'RECEIPT'
      process_read_receipt_event(channel, params)
    when 'CONNECTION', 'QRCODE', 'LOGGED_OUT', ...
      ConnectionService.new(channel: channel).handle_event(params)
    when 'HISTORY_SYNC'
      Import::HistorySyncProcessor
    when 'GROUP', 'GROUP_INFO', 'JOINED_GROUP'
      # ignore_groups != false → return
      # warm_cache_from_name! (GroupName.Name / Name.Name) + schedule_metadata_fetch! (Redis 5 min)
    end
  end
end
```

> Implementação completa: `custom/app/jobs/custom/webhooks/whatsapp_events_job_evolution_go.rb`. Entrega via `InboundMessageProcessor` (não `super` direto no normalizer).

---

## Specs (implementados)

| Spec | Fixture / foco |
|------|----------------|
| `spec/custom/services/custom/whatsapp/webhooks/evolution_go_normalizer_spec.rb` | `message_inbound.json` |
| `spec/custom/services/custom/whatsapp/evolution_go/api_client_spec.rb` | HTTP client |
| `spec/custom/controllers/webhooks/evolution_go_controller_spec.rb` | auth `?token=` e Bearer |
| `spec/custom/jobs/custom/webhooks/whatsapp_events_job_evolution_go_spec.rb` | roteamento eventos |
| `spec/custom/services/custom/whatsapp/evolution_go/message_reaction_*_spec.rb` | reactions inbound |

---

## Reactions (ADR §33)

```ruby
# MessageReactionPayloadExtractor.extract_reaction_payload(data)
# → { key:, text:, remove:, reaction_message_id:, from_me:, participant: }

# MessageReactionSyncService.new(channel:, data:).perform
# → atualiza content_attributes['reactions'] na mensagem alvo

# ReactSyncService.new(message:, reaction:, user:).perform
# → POST /message/react + atualiza reactions locais (ator user)
```

---

## Fixtures esperados

```
spec/fixtures/evolution_go/
├── message_inbound.json
├── message_normalized.json
├── connection_event.json
├── qrcode_event.json
├── read_receipt.json
├── send_text_response.json
├── postman-environment.json
└── README.md
```
