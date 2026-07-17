# Fixtures webhook Wavoip

JSON de referência para specs e `PayloadNormalizer`. Inclui payloads simulados e live (caller/receiver).

**DTO:** [architecture.md §3.5](../architecture.md#35-dto-normalizado) (`Voice::Dto::WebhookCallEvent`).

**Schema oficial:** [Webhook (Beta)](https://wavoip.gitbook.io/api/webhook-beta.md) · [official-docs.md](../official-docs.md)

Cópias espelhadas em `spec/fixtures/files/wavoip/` quando usadas por RSpec.

| Arquivo | Evento |
|---------|--------|
| `call_create_inbound_ring.json` | `CALL` CREATE `INCOMING_RING` |
| `call_create_outbound.json` | `CALL` CREATE `OUTGOING_RING` |
| `call_create_inbound_live_e2e.json` / `*_caller_receiver.json` | Live inbound |
| `call_create_outbound_live_e2e.json` / `*_outcoming_*.json` | Live outbound |
| `call_update_active.json` | `CALL` UPDATE `ACTIVE` |
| `call_update_ended.json` | `CALL` UPDATE `ENDED` |
| `call_update_handled_remotely.json` | `CALL` UPDATE `HANDLED_REMOTELY` |
| `record_update.json` | `RECORD` |
| `device_update.json` / `device_update_live_ingress.json` | `DEVICE` |
| `call_duplicate_type_field.json` | Duplicate `type` key (last wins after `JSON.parse`) |

Uso em spec:

```ruby
payload = JSON.parse(file_fixture('wavoip/call_create_inbound_ring.json').read)
normalized = Wavoip::Webhooks::PayloadNormalizer.new(payload).to_h
```
