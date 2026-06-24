# Spec design — classes `custom/` Z-API

Contratos públicos das classes do provider antes da implementação. Espelha [../evolution-api/spec-design.md](../evolution-api/spec-design.md).

---

## `Custom::Whatsapp::Zapi::ApiError`

```ruby
class Custom::Whatsapp::Zapi::ApiError < StandardError
  attr_reader :status, :body, :base_message

  def initialize(message = nil, status: nil, body: nil)
    @status = status
    @body = body
    @base_message = message
    super(log_message)
  end

  def log_message   # inclui status + body — para logs
  def user_message  # mensagem amigável ao operador — em produção sem detalhe interno

  def self.compose_message(message, status, body)
  def self.extract_message(body)  # body é Hash (parsed JSON) ou string
end
```

Elevar quando `response.code >= 400` no `ApiClient`. Propagar até `ConnectionService` / `ZapiService` que decidem logar ou traduzir para UI.

---

## `Custom::Whatsapp::Zapi::ApiClient`

```ruby
# initialize(base_url:, instance_id:, instance_token:, client_token:)

def connection_status              # GET .../status
def instance_me                    # GET .../me
def qr_code_bytes                  # GET .../qr-code
def qr_code_image                  # GET .../qr-code/image
def phone_code(phone)              # GET .../phone-code/{phone}
def disconnect                     # GET .../disconnect
def restart                        # GET .../restart

def send_text(phone:, message:, **opts)   # POST .../send-text
def send_image(phone:, image:, caption: nil, **opts)  # Fase 2
def send_audio(phone:, audio:, **opts)                # Fase 2
def send_video(phone:, video:, **opts)                # Fase 2
def send_document(phone:, document:, extension:, **opts) # Fase 2
def read_message(phone:, message_id:)                   # Fase 2

def register_all_webhooks(url:, notify_sent_by_me: false)  # PUT .../update-every-webhooks
def register_webhook_received(url)       # PUT .../update-webhook-received
def register_webhook_delivery(url)       # PUT .../update-webhook-delivery
def register_webhook_message_status(url) # PUT .../update-webhook-message-status
def register_webhook_disconnected(url)   # PUT .../update-webhook-disconnected

def contacts(page: 1, page_size: 20)    # Fase 2 — GET .../contacts
def phone_exists?(phone)                 # Fase 2 — GET .../phone-exists/{phone}

# private
def instance_path(action)  # "/instances/#{id}/token/#{token}/#{action}"
def headers                # { 'Client-Token' => client_token, 'Content-Type' => 'application/json' }
def get(action)
def put(action, body)
def post(action, body)
```

**Diferença vs Evolution:** auth no path + `Client-Token`; sem `global_api_key`; webhooks via PUT dedicados ou bulk.

---

## `Custom::Whatsapp::Zapi::ConnectionEvents`

Responsável pelos **side-effects** dos eventos de conexão recebidos via webhook (análogo a `Evolution::ConnectionEvents`). Chamado dentro do `dispatch_zapi_event` do job prepend.

```ruby
# initialize(channel:)

def handle_connected(payload)
  # 1. channel.update provider_config: connection_status → connected
  # 2. sync phone_number ← payload['phone']
  # 3. ActionCable.server.broadcast "zapi:connection:{inbox.id}",
  #      { connection_status: 'connected', phone_number: ... }

def handle_disconnected(payload)
  # 1. channel.update provider_config: connection_status → disconnected
  # 2. ActionCable.server.broadcast "zapi:connection:{inbox.id}",
  #      { connection_status: 'disconnected' }
```

> **Motivo de separar do normalizer:** o `ZapiNormalizer` só parseia — não tem referência ao `channel` nem a `ActionCable`. `ConnectionEvents` detém os side-effects de estado.

---

## `Custom::Whatsapp::Zapi::ConnectionService`

```ruby
# initialize(channel:)

def setup_webhooks!       # gera secret se ausente; register_all_webhooks!
def register_webhooks_fallback!  # 4× PUT se bulk falhar
def sync_connection_status!
def fetch_qr_image        # base64 para wizard
def disconnect!
def sync_phone_number!    # GET /me ou webhook ConnectedCallback
```

**Fluxo wizard (credenciais manuais):**

```
1. Validar provider_config (instance_id, instance_token, client_token)
2. setup_webhooks!
3. sync_connection_status!
4. Se não connected → fetch_qr_image + ActionCable/polling
```

---

## `Custom::Whatsapp::Providers::ZapiService`

```ruby
# Herda MessagingProvider::BaseService (registry)

def send_message(phone_number, message)
def send_template(...)      # noop ou texto simples — sem templates WABA
def sync_templates          # noop
def validate_provider_config?
def process_response(response)  # → messageId
def media_url(_attachment)        # Fase 2 — URL pública para send-image etc.
```

---

## `Custom::Whatsapp::Webhooks::ZapiNormalizer`

```ruby
def normalize(payload)           # router por payload['type']
def normalize_received(payload)  # ReceivedCallback → flat inbound
def normalize_status(payload)    # MessageStatusCallback → statuses[]
def normalize_delivery(payload)  # DeliveryCallback → opcional
def normalize_connection(payload) # Connected/Disconnected

def extract_source_id(payload)
def extract_phone(payload)
def extract_content(payload)     # text.message, image.caption, etc.
def extract_attachments(payload) # imageUrl, audioUrl, ...
def ignore?(payload)            # fromMe, isGroup, isNewsletter
```

**Saída inbound (flat):**

```ruby
{
  source_id: 'D241XXXX...',
  phone: '5511999999999',
  content: 'texto',
  content_type: 'text', # image, audio, video, document, location, contact
  attachments: [],      # [{ url:, file_type: }]
  contact_name: '...',  # senderName
  raw: payload
}
```

---

## `Custom::Webhooks::ZapiController`

Espelha [EvolutionController](../../../custom/app/controllers/webhooks/evolution_controller.rb):

```ruby
def process_payload
  Webhooks::WhatsappEventsJob.perform_later(
    sanitized_job_payload.merge(instance_id: params[:instance_id], channel_id: @channel.id)
  )
  head :ok
end

def authenticate_webhook!
  @channel = Channel::Whatsapp.where(provider: 'zapi')
    .where("provider_config->>'instance_id' = ?", params[:instance_id]).first
  return head :not_found unless @channel

  stored = @channel.provider_config['webhook_token'].to_s.strip
  query = params[:token].to_s.strip
  return head :unauthorized unless stored.present? &&
    ActiveSupport::SecurityUtils.secure_compare(query, stored)

  # Opcional: validar payload['instanceId'] == params[:instance_id]
end

private

def sanitized_job_payload
  # Strip Rails router metadata + query auth token (não persistir no job payload)
  params.to_unsafe_hash.except('controller', 'action', 'instance_id', 'token')
end
```

> `instance_id` e `token` são adicionados de volta explicitamente via `.merge(instance_id: ..., channel_id: ...)`. Diferença de Evolution: sem campo `apikey` para remover — Z-API não embute credenciais no body do webhook.

---

## Prepend `WhatsappEventsJob`

Espelha padrão Evolution — early return se não for envelope Z-API:

```ruby
def perform(params = {})
  params = params.with_indifferent_access
  return super(params) unless zapi_envelope?(params)

  channel = find_zapi_channel(params)
  return unless channel

  dispatch_zapi_event(channel, params)
end

def zapi_envelope?(params)
  params[:type].present? && params[:instance_id].present?
end

# Router por payload['type']
def dispatch_zapi_event(channel, params)
  normalizer = Custom::Whatsapp::Webhooks::ZapiNormalizer.new
  conn_events = Custom::Whatsapp::Zapi::ConnectionEvents.new(channel: channel)

  case params[:type]
  when 'ReceivedCallback'
    return if normalizer.ignore?(params)
    normalized = normalizer.normalize_received(params)
    ::Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: normalized).perform
  when 'MessageStatusCallback'
    normalized = normalizer.normalize_status(params)
    update_message_status(channel, normalized)
  when 'DeliveryCallback'
    handle_delivery(channel, params)          # log erro se params['error'].present?
  when 'ConnectedCallback'
    conn_events.handle_connected(params)
  when 'DisconnectedCallback'
    conn_events.handle_disconnected(params)
  else
    Rails.logger.debug { "[Zapi] ignored event type=#{params[:type]}" }
  end
end
```

> `DeliveryCallback` no MVP: logar `error` se presente (ex: `SHADOW_BAN`, número inexistente); status principal controlado por `MessageStatusCallback`.

---

## `ZapiConnectionChannel` (ActionCable)

Espelha `EvolutionConnectionChannel`:

```ruby
class ZapiConnectionChannel < ApplicationCable::Channel
  def subscribed
    inbox = current_account.inboxes.find(params[:inbox_id])
    channel = inbox.channel
    reject and return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'zapi'
    reject and return unless inbox_accessible?(inbox)

    stream_from "zapi:connection:#{inbox.id}"
  end
end
```

Frontend `useZapiConnection.js` subscreve `zapi:connection:{inbox_id}` e reage a `connection_status` + `phone_number` para o Step 2 do wizard.

---

## Registry

```ruby
# custom/config/initializers/messaging_provider_registry.rb
MessagingProvider::Registry.register(
  'zapi',
  service_class: Custom::Whatsapp::Providers::ZapiService,
  capabilities: %i[unlimited_session]
)
```

---

## Fixtures (`spec/fixtures/zapi/`)

| Arquivo | Origem |
|---------|--------|
| `received_text.json` | doc [on-message-received-examples](https://developer.z-api.io/webhooks/on-message-received-examples.md) |
| `received_image.json` | idem |
| `delivery_success.json` | [on-message-send-examples](https://developer.z-api.io/webhooks/on-message-send-examples.md) |
| `status_read.json` | provider-comparison + doc status |
| `disconnected.json` | [on-whatsapp-disconnected](https://developer.z-api.io/webhooks/on-whatsapp-disconnected.md) |
| `send_text_response.json` | [send-text](https://developer.z-api.io/message/send-text.md) |
| `status_connected.json` | [instance/status](https://developer.z-api.io/instance/status.md) |
