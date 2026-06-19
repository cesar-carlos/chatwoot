# Fixtures webhook Wavoip

JSON de referência para specs e `PayloadNormalizer`. **Substituir** pelos payloads reais capturados no spike (Fase 0).

**DTO esperado:** [contracts-and-ports.md §4.1](../contracts-and-ports.md#41-dto-normalizado-saída-do-parser--entrada-dos-handlers) (`Voice::Dto::WebhookCallEvent`).

**Schema oficial:** [Webhook (Beta)](https://wavoip.gitbook.io/api/wavoip-docs/webhook-beta.md) · [official-docs.md](../official-docs.md)

| Arquivo | Evento |
|---------|--------|
| `call_create_inbound_ring.json` | `CALL` CREATE `INCOMING_RING` |
| `call_create_outbound.json` | `CALL` CREATE `OUTGOING_RING` |
| `call_update_active.json` | `CALL` UPDATE `ACTIVE` |
| `call_update_ended.json` | `CALL` UPDATE `ENDED` |
| `call_update_handled_remotely.json` | `CALL` UPDATE `HANDLED_REMOTELY` |
| `record_update.json` | `RECORD` |
| `device_update.json` | `DEVICE` |

Uso em spec:

```ruby
payload = JSON.parse(file_fixture('wavoip/call_create_inbound_ring.json').read)
normalized = Wavoip::Webhooks::PayloadNormalizer.new(payload).to_h
```
