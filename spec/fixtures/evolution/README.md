# Fixtures Evolution — webhooks e API

Payloads JSON capturados do servidor Evolution local v**2.3.6** (`http://localhost:8080`, código em `/root/evolution-api`).

Validação: [validation-checklist.md](../../../doc/feature/whatsapp-provider/evolution-api/validation-checklist.md) · T0 jun/2026.

**Versão alvo:** [evolution-target-version.txt](../../../doc/feature/whatsapp-provider/evolution-api/evolution-target-version.txt)

---

## Validação sendText

| Campo | Resultado |
|-------|-----------|
| Versão Evolution | **2.3.6** (`GET /` → `version`) |
| Body aceito | **`text` plano** — `{"number":"…","text":"…"}` |
| Body rejeitado | `textMessage.text` nested → HTTP **400** (`instance requires property "text"`) |
| HTTP status (sucesso) | **201** |
| `source_id` path | **`key.id`** confirmado (ex.: `3EB0C6D7F8BC03700FBB95`) |

Instância spike: `cw-spike-1781996187`. sendText executado em instância conectada `MATHEUS-66981128433-TESTE` (spike instance permanece `connecting` sem scan QR).

---

## Arquivos

| Arquivo | Origem | Uso no spec |
|---------|--------|-------------|
| `instance_create_response.json` | `POST /instance/create` | ConnectionService provision |
| `webhook_set_response.json` | `POST /webhook/set/:instance` | ApiClient#set_webhook |
| `instance_connect_response.json` | `GET /instance/connect/:instance` | QR fetch |
| `connection_state_connecting.json` | `GET /instance/connectionState/:instance` | Status polling |
| `messages_upsert_text.json` | Webhook `MESSAGES_UPSERT` (dados reais DB) | Normalizer Fase 1 |
| `messages_upsert_text_normalized.json` | Saída `EvolutionNormalizer` | Normalizer Fase 1 |
| `messages_upsert_image.json` | `MESSAGES_UPSERT` imagem | Normalizer Fase 2 |
| `messages_update_read.json` | `MESSAGES_UPDATE` | Status read |
| `connection_update_open.json` | Webhook `CONNECTION_UPDATE` (estrutura v2.3.6) | ConnectionService |
| `qrcode_updated.json` | Webhook `QRCODE_UPDATED` (QR real, base64 truncado) | Wizard QR |
| `send_text_response.json` | Resposta `POST /message/sendText` | EvolutionService#process_response |

---

## Notas

- `instance` nos envelopes webhook = `test-instance` (alinhar com factory do spec)
- `apikey` nos fixtures usa token real da instância spike (valor de teste local)
- QR `base64` truncado nos fixtures para manter diff legível; prefixo `data:image/png;base64,` preservado
- Integração Chatwoot legada na Evolution: `GET /chatwoot/find` → `enabled: false` (novas instâncias); disable via API exige body completo — ver `ApiClient#disable_chatwoot_integration`
