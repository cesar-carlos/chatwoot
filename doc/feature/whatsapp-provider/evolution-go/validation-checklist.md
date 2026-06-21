# Checklist de validação — pré Fase 1 (Evolution Go)

Executar **antes** de fechar o MVP texto + QR. Resultados alimentam `spec/fixtures/evolution_go/` e confirmam compatibilidade com [evolution-target-version.txt](./evolution-target-version.txt).

**Postman:** [Evolution Go collection](https://www.postman.com/agenciadgcode/evolution-api/collection/nk736ze/evolution-go)

**Ambiente:** Evolution Go Docker (`evoapicloud/evolution-go:latest`) + licença ativada + Chatwoot fork Fase 0–1.

---

## 0. Pré-requisitos

- [ ] Licença Evolution Go ativada (Magic Link no painel)
- [ ] `GLOBAL_API_KEY` configurado no `.env` do servidor Go
- [ ] PostgreSQL auth + users DB acessíveis
- [ ] `FRONTEND_URL` público para webhook
- [ ] Versão Go registrada: `_______________` (image tag ou `GET /server/ok`)

---

## 1. Spike REST (manual)

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
- [ ] Resposta contém `data.token` (ou token informado)
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
- [ ] Webhook recebe evento `CONNECTION` ou `QRCODE` ao conectar

### 1.3 QR

```bash
curl -sS "${BASE_URL}/instance/qr" \
  -H "apikey: ${INSTANCE_TOKEN}" | tee /tmp/evogo-qr.json
```

- [ ] QR retornado (base64 ou pipe-separated)
- [ ] Escanear → status connected

```bash
curl -sS "${BASE_URL}/instance/status" \
  -H "apikey: ${INSTANCE_TOKEN}" | tee /tmp/evogo-status.json
```

- [ ] `data.connected` e `data.loggedIn` true
- [ ] `data.myJid` presente → futuro `phone_number`

### 1.4 sendText

```bash
curl -sS -X POST "${BASE_URL}/send/text" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"number": "'"${TEST_PHONE}"'", "text": "ping evogo"}' \
  | tee spec/fixtures/evolution_go/send_text_response.json
```

- [ ] HTTP 2xx
- [ ] Resposta contém `data.Info.ID` (PascalCase whatsmeow)
- [ ] Mensagem chega no WhatsApp

> Path oficial confirmado: `POST /send/text` — ver [send-a-text-message](https://docs.evolutionfoundation.com.br/evolution-go/send-a-text-message). Não usar `/message/sendText`.

---

## 2. Spike webhook inbound

Enviar mensagem **do celular** para o número conectado.

- [ ] Chatwoot recebe POST em `/webhooks/evolution_go/:instance_name`
- [ ] Body `event: MESSAGE`
- [ ] Salvar fixture: `spec/fixtures/evolution_go/message_inbound.json`
- [ ] Normalizer produz `{ contacts:, messages: }` válido
- [ ] Conversa criada no Chatwoot
- [ ] Echo `fromMe` **não** duplica

---

## 3. Spike outbound Chatwoot → Go

- [ ] Agente responde no Chatwoot
- [ ] `EvolutionGoService#send_message` usa path validado em §1.4/1.5
- [ ] `source_id` persistido
- [ ] Mensagem chega no WhatsApp

---

## 4. Regressão

- [ ] Providers `whatsapp_cloud`, `default` inalterados
- [ ] Se `evolution` existir — inalterado

---

## 5. Documentar resultados

Atualizar após spike:

- [ ] [evolution-target-version.txt](./evolution-target-version.txt)
- [ ] [postman-validation.md](./postman-validation.md) — ⚠️ → ✅
- [ ] [api-reference.md](./api-reference.md) — path send definitivo
- [ ] `spec/fixtures/evolution_go/README.md` com notas de validação
