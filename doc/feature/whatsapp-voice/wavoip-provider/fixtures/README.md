# Fixtures webhook Wavoip

JSON de referência para specs e `PayloadNormalizer`. **Substituir** pelos payloads reais capturados no spike (Fase 0).

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
