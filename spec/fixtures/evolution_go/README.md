# Fixtures Evolution Go — `spec/fixtures/evolution_go/`

Templates para specs e validação do provider `evolution_go`. **Substituir por capturas reais** após [validation-checklist.md](../../doc/feature/whatsapp-provider/evolution-go/validation-checklist.md).

---

## Arquivos esperados

| Arquivo | Origem | Uso |
|---------|--------|-----|
| `send_text_response.json` | `POST /send/text` | `EvolutionGoService#process_response` → `data.Info.ID` |
| `message_inbound.json` | Webhook `MESSAGE` | `EvolutionGoNormalizer` |
| `message_normalized.json` | Output do normalizer | Spec expectativa flat |
| `connection_event.json` | Webhook `CONNECTION` | `ConnectionService#handle_event` |
| `qrcode_event.json` | Webhook `QRCODE` | Wizard QR |
| `read_receipt.json` | Webhook `READ_RECEIPT` | Fase 2 statuses |

---

## Validação send text (preencher no spike)

| Campo | Valor confirmado |
|-------|------------------|
| Path | `POST /send/text` |
| Auth header | `apikey: {instance_token}` |
| Body | `{ "number": "...", "text": "..." }` |
| `source_id` field | `data.Info.ID` — **confirmar** |
| Versão Go | _preencher_ |
| Data spike | _preencher_ |

---

## Validação inbound MESSAGE (preencher no spike)

| Campo | Valor confirmado |
|-------|------------------|
| `source_id` | `data.key.id` — **confirmar** |
| Texto simples | `message.conversation` |
| Texto formatado | `message.extendedTextMessage.text` — **confirmar** |
| Envelope auth | Sem `apikey` no body |

---

## Validação status (preencher no spike)

| Campo | Valor confirmado |
|-------|------------------|
| `Connected` / `connected` | _qual casing?_ |
| JID / phone | _campo:_ `myJid` / `jid` / outro |

---

## Notas

- Não misturar com `spec/fixtures/evolution/` (Evolution API Node)
- Sanitizar tokens antes de commitar fixtures reais
