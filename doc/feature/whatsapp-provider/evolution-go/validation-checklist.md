# Checklist E2E — integração Evolution Go

Validação **durante** a Fase 1, contra uma **instância Evolution Go já provisionada pelo operador**. Não é pré-requisito para iniciar código — contratos vêm de [postman-validation.md](./postman-validation.md) e [decisions.md](./decisions.md).

**Variáveis:** `BASE_URL`, `GLOBAL_API_KEY`, `INSTANCE_TOKEN`, `FRONTEND_URL` (público para webhook), `TEST_PHONE`

**Postman:** [Evolution GO collection](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go) · environment em `spec/fixtures/evolution_go/postman-environment.json`

---

## 0. Pré-requisitos (operador)

- [ ] Instância Evolution Go acessível em `BASE_URL`
- [ ] Licença ativa no painel Go
- [ ] `GLOBAL_API_KEY` configurado no servidor
- [ ] `FRONTEND_URL` do Chatwoot alcançável pelo servidor Go (webhook)
- [ ] Versão registrada em [evolution-target-version.txt](./evolution-target-version.txt)

---

## 1. REST — conexão e envio

### 1.1 Criar instância

```bash
curl -sS -X POST "${BASE_URL}/instance/create" \
  -H "apikey: ${GLOBAL_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"${INSTANCE}"'",
    "token": "'"${INSTANCE_TOKEN}"'"
  }' | tee /tmp/evogo-create.json
```

- [ ] HTTP 2xx
- [ ] Resposta contém `data.token`
- [ ] Salvar token → `provider_config.instance_token`

### 1.2 Conectar + webhook Chatwoot

```bash
WEBHOOK_URL="${FRONTEND_URL}/webhooks/evolution_go/${INSTANCE}?token=${WEBHOOK_SECRET}"

curl -sS -X POST "${BASE_URL}/instance/connect" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "webhookUrl": "'"${WEBHOOK_URL}"'",
    "subscribe": ["MESSAGE", "CONNECTION", "QRCODE"],
    "rabbitmqEnabled": "disabled",
    "websocketEnable": "disabled",
    "natsEnabled": "disabled"
  }' | tee /tmp/evogo-connect.json
```

- [ ] HTTP 2xx
- [ ] Webhook recebe `CONNECTION` ou `QRCODE`

### 1.3 QR e status

```bash
curl -sS "${BASE_URL}/instance/qr" \
  -H "apikey: ${INSTANCE_TOKEN}" | tee /tmp/evogo-qr.json

curl -sS "${BASE_URL}/instance/status" \
  -H "apikey: ${INSTANCE_TOKEN}" | tee /tmp/evogo-status.json
```

- [ ] QR retornado; scan → connected
- [ ] `Connected` + `LoggedIn` true
- [ ] JID presente → `phone_number` do channel

### 1.4 Send text

```bash
curl -sS -X POST "${BASE_URL}/send/text" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"number": "'"${TEST_PHONE}"'", "text": "ping evogo"}' \
  | tee spec/fixtures/evolution_go/send_text_response.json
```

- [ ] HTTP 2xx · `data.Info.ID` presente
- [ ] Mensagem chega no WhatsApp

---

## 2. Webhook inbound

Enviar mensagem do celular para o número conectado.

- [ ] POST em `/webhooks/evolution_go/:instance_name`
- [ ] Salvar: `message_inbound.json`, `connection_event.json`, `qrcode_event.json`
- [ ] Normalizer → conversa no Chatwoot
- [ ] Echo `fromMe` não duplica

---

## 2b. Fase 2 (opcional)

- [ ] `GET`+`PUT /instance/{id}/advanced-settings` — anotar casing dos campos
- [ ] `POST /message/downloadimage` vs `downloadmedia` — ADR §25
- [ ] Reconnect: confirmar que `POST /instance/connect` preserva webhook (ADR §23–24)

---

## 3. Outbound Chatwoot → Go

- [ ] Agente responde no Chatwoot
- [ ] `source_id` = `data.Info.ID`
- [ ] Mensagem no WhatsApp

---

## 4. Regressão

- [ ] Providers `whatsapp_cloud`, `default`, `evolution` inalterados

---

## 5. Documentar resultados

- [ ] [evolution-target-version.txt](./evolution-target-version.txt)
- [ ] [postman-validation.md](./postman-validation.md) — checklist pós-E2E
- [ ] [status.md](./status.md) — fechar G1–G4
- [ ] `spec/fixtures/evolution_go/README.md`
