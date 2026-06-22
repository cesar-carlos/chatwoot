# Spec design — classes `custom/` Evolution Go

Contratos públicos das classes do provider antes da implementação. Espelha [../evolution-api/spec-design.md](../evolution-api/spec-design.md).

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
def download_media(message_payload)                    # POST /message/downloadimage → fallback downloadmedia

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
  post('/message/downloadimage', flatten_media_fields(message_payload), headers: instance_headers)
rescue ApiError => e
  raise e unless retriable_download_error?(e)

  post('/message/downloadmedia', { message: message_payload }, headers: instance_headers)
end
```

---

## `Custom::Whatsapp::EvolutionGo::ConnectionService`

```ruby
# initialize(channel) — Channel::Whatsapp provider evolution_go

def provision_new_inbox!(params)  # create + generate webhook_secret + connect
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

Validação em camadas (wizard vs inbox existente):

| Check | API | Header |
|-------|-----|--------|
| Servidor alcançável | `GET /server/ok` | nenhum |
| Token instância válido | `GET /instance/status` | `apikey: instance_token` |
| Admin key (modo criar) | `GET /instance/all` | `apikey: global_api_key` |

Retorna `true` se `server_ok` 2xx e `dig_field(status, 'connected', 'Connected')` truthy.

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

## Specs pós-fixtures (Fase 1)

Após E2E, adicionar specs com fixtures reais (não mocks inventados):

| Spec | Fixture |
|------|---------|
| `spec/custom/whatsapp/evolution_go/normalizer_spec.rb` | `message_inbound.json` |
| `spec/custom/whatsapp/evolution_go/api_client_spec.rb` | `send_text_response.json` |
| `spec/custom/webhooks/evolution_go_controller_spec.rb` | auth `?token=` |

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
