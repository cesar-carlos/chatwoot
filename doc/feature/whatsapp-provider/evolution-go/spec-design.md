# Spec design — classes `custom/` Evolution Go

Contratos públicos das classes do provider antes da implementação. Espelha [../evolution-api/spec-design.md](../evolution-api/spec-design.md).

---

## `Custom::Whatsapp::EvolutionGo::ApiClient`

```ruby
# initialize(base_url:, global_api_key: nil, instance_token: nil, instance_name: nil)

# Admin (global_api_key)
def create_instance(name:, token: nil, proxy: nil)  # POST /instance/create
def list_instances                                     # GET /instance/all
def delete_instance(instance_id)                       # DELETE /instance/delete/{instanceId}
def disconnect                                         # POST /instance/disconnect (spike path)
def logout                                             # POST /instance/logout (spike path)

# Instance (instance_token)
def connect(webhook_url:, subscribe:, **opts)          # POST /instance/connect
def qr_code                                            # GET /instance/qr
def pair(phone:)                                       # POST /instance/pair
def connection_status                                  # GET /instance/status
def send_text(number:, text:, quoted: nil)             # POST /send/text
def send_media(number:, mediatype:, media:, caption: nil)  # Fase 2

# private
def admin_headers    # { 'apikey' => global_api_key }
def instance_headers # { 'apikey' => instance_token }
def unwrap(response) # extrair .data de wrappers Go
def post(path, body, headers:)
def get(path, headers:)
```

**Diferença vs Evolution API client:** dual auth; sem `set_webhook` separado; `connect` inclui webhook.

---

## `Custom::Whatsapp::EvolutionGo::ConnectionService`

```ruby
# initialize(channel) — Channel::Whatsapp provider evolution_go

def provision_new_inbox!(params)  # create + generate webhook_secret + connect
def connect_existing!(params)     # token + instance_name informados
def handle_event(envelope)        # CONNECTION, QRCODE webhooks
def sync_phone_number!            # GET status → jid (PascalCase ou camelCase)
def reconnect!                    # disconnect + connect com webhookUrl + subscribe
def broadcast_connection_event(type, payload)
def webhook_url                   # FRONTEND_URL/webhooks/evolution_go/{name}?token={secret}
```

---

## `Custom::Whatsapp::Providers::EvolutionGoService`

```ruby
# < Whatsapp::Providers::BaseService

def send_message(phone_number, message)
def validate_provider_config?        # GET /instance/status com instance_token
def media_url(_media_id); end      # Fase 2
def api_headers; end

# protected
def process_response(response)
  parsed = response.parsed_response
  parsed.dig('data', 'Info', 'ID') || parsed.dig('data', 'messageId')
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
  # fromMe, @g.us, status@broadcast
end

def extract_phone(key)
  # remoteJid / remoteJidAlt / LID
end
```

**Eventos suportados:**

| `event` | Output |
|---------|--------|
| `MESSAGE` | `{ contacts:, messages: }` |
| `READ_RECEIPT` | `{ statuses: }` (Fase 2) |
| `CONNECTION`, `QRCODE` | `nil` — ConnectionService |

---

## `Custom::Webhooks::EvolutionGoController`

```ruby
# before_action :authenticate_webhook!
# POST create → WhatsappEventsJob.perform_later(params.merge(...))

def authenticate_webhook!
  # lookup by instance_name
  # validate ?token= vs webhook_secret
end
```

---

## `validate_provider_config?`

Validação em duas camadas (wizard vs inbox existente):

| Check | API | Header |
|-------|-----|--------|
| Servidor alcançável | `GET /server/ok` | nenhum |
| Token instância válido | `GET /instance/status` | `apikey: instance_token` |
| Admin key (só wizard) | `GET /instance/all` | `apikey: global_api_key` |

Retorna `true` se status HTTP 2xx e `Connected`/`connected` truthy (aceitar ambos casings).

---

## Registry

```ruby
# custom/config/initializers/messaging_provider_registry.rb
MessagingProvider::Registry.register('evolution_go') do |channel|
  Custom::Whatsapp::Providers::EvolutionGoService.new(whatsapp_channel: channel)
end
```

---

## Prepend job (sketch)

```ruby
module Custom::Webhooks::WhatsappEventsJob
  def perform(params = {})
    return super(params) unless evolution_go_envelope?(params)

    channel = find_evolution_go_channel(params)
    return unless channel

    case params['event']
    when 'MESSAGE'
      normalized = Custom::Whatsapp::Webhooks::EvolutionGoNormalizer
        .new(channel, params).perform
      super(normalized.merge(phone_number: channel.phone_number)) if normalized.present?
    when 'CONNECTION', 'QRCODE'
      Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel).handle_event(params)
    when 'READ_RECEIPT'
      # Fase 2
    end
  end
end
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
└── README.md
```
