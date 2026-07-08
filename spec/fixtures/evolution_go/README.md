# Fixtures Evolution Go — `spec/fixtures/evolution_go/`

Templates para specs do provider `evolution_go`. Contrato primário: [postman-validation.md](../../doc/feature/whatsapp-provider/evolution-go/postman-validation.md) e [decisions.md](../../doc/feature/whatsapp-provider/evolution-go/decisions.md).

Substituir por capturas reais no [E2E](../../doc/feature/whatsapp-provider/evolution-go/validation-checklist.md) com instância do operador.

---

## Arquivos esperados

| Arquivo | Origem | Uso |
|---------|--------|-----|
| `send_text_response.json` | `POST /send/text` | `EvolutionGoService#process_response` → `data.Info.ID` |
| `postman-environment.json` | Template | Variáveis para testes manuais |
| `message_inbound.json` | Webhook `MESSAGE` | `EvolutionGoNormalizer` |
| `message_normalized.json` | Output do normalizer | Spec expectativa flat |
| `connection_event.json` | Webhook `CONNECTION` | `ConnectionService#handle_event` |
| `qrcode_event.json` | Webhook `QRCODE` | Wizard QR |
| `read_receipt.json` | Webhook `READ_RECEIPT` | Fase 2 statuses |
| `message_edit.json` | Webhook edit | `MessageEditSyncService` |
| `message_revoke.json` | Webhook delete/revoke | `MessageDeleteSyncService` |
| `history_sync.json` | Webhook `HISTORY_SYNC` | `HistorySyncProcessor` (⚠️ sintética) |
| `message_inbound_group.json` | Webhook `MESSAGE` grupo | `EvolutionGoNormalizer` group path (⚠️ sintética) |
| `message_inbound_location.json` | Webhook `MESSAGE` location | `EvolutionGoNormalizer` location path |
| `pair_response.json` | `POST /instance/pair` | Pair API + `ConnectionService#pair!` |

---

## Contrato documentado (implementar com estes valores)

| Campo | Valor |
|-------|-------|
| Path send | `POST /send/text` |
| Auth send | `apikey: {instance_token}` |
| Body send | `{ "number": "...", "text": "..." }` |
| `source_id` outbound | `data.Info.ID` |
| `source_id` inbound 1:1 | `data.key.id` |
| `source_id` inbound grupo | JID `@g.us` completo |
| Texto simples | `message.conversation` |
| Eventos webhook | `MESSAGE`, `CONNECTION`, `QRCODE`, `READ_RECEIPT`, delete/edit, `HISTORY_SYNC`, `GROUP`* |
| Pair response | `data.PairingCode` |
| Location inbound | `message.locationMessage.degreesLatitude/Longitude` |

\* `GROUP` apenas quando `ignore_groups: false`

---

## Preencher no E2E

| Campo | Valor confirmado |
|-------|------------------|
| Versão Go | _preencher_ |
| Data E2E | _preencher_ |
| JID / phone | _campo exato no status_ |
| `Connected` casing | _PascalCase vs camelCase_ |
| advanced-settings body | Fase 2 |
| Download mídia | Fase 2 — ADR §25 |

---

## Notas

- Não misturar com `spec/fixtures/evolution/` (Evolution API Node)
- Sanitizar tokens antes de commitar fixtures reais
