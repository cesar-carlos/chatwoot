# Spec design — classes `custom/` Z-API

Contratos públicos das classes do provider antes da implementação. Espelha [../evolution-api/spec-design.md](../evolution-api/spec-design.md).

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
```

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
```

Router por `type` — ver [decisions.md §12](./decisions.md).

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
