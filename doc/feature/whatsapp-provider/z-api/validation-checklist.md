# Checklist E2E — integração Z-API

Validação contra **instância Z-API de teste** (painel ou Partners). Contratos base: [api-reference.md](./api-reference.md) · [decisions.md](./decisions.md).

**Variáveis:** `BASE_URL`, `INSTANCE_ID`, `INSTANCE_TOKEN`, `CLIENT_TOKEN`, `FRONTEND_URL`, `WEBHOOK_TOKEN`, `TEST_PHONE`

**Postman:** [fork](https://go.postman.co/collection/9985534-cdcfbd61-4ce9-451d-80a8-fe3c5cd6da6d)

---

## 0. Pré-requisitos

- [ ] Conta Z-API ativa com instância de teste
- [ ] `Client-Token` configurado e ativado (se usado)
- [ ] `FRONTEND_URL` público HTTPS (ngrok/staging) para webhooks
- [ ] Número WhatsApp disponível para scan QR

---

## 1. REST — conexão

### 1.1 Status

```bash
curl -sS "${BASE_URL}/instances/${INSTANCE_ID}/token/${INSTANCE_TOKEN}/status" \
  -H "Client-Token: ${CLIENT_TOKEN}" | tee /tmp/zapi-status.json
```

- [ ] HTTP 200
- [ ] Campo `connected` presente

### 1.2 QR (imagem)

```bash
curl -sS "${BASE_URL}/instances/${INSTANCE_ID}/token/${INSTANCE_TOKEN}/qr-code/image" \
  -H "Client-Token: ${CLIENT_TOKEN}" | tee /tmp/zapi-qr.json
```

- [ ] Retorna imagem base64 ou URL renderizável
- [ ] Scan conecta → `connected: true`

### 1.3 Dados instância

```bash
curl -sS "${BASE_URL}/instances/${INSTANCE_ID}/token/${INSTANCE_TOKEN}/me" \
  -H "Client-Token: ${CLIENT_TOKEN}" | tee /tmp/zapi-me.json
```

- [ ] `connected: true` após pairing

---

## 2. Webhooks

### 2.1 Registrar URL única (preferido)

```bash
WEBHOOK_URL="${FRONTEND_URL}/webhooks/zapi/${INSTANCE_ID}?token=${WEBHOOK_TOKEN}"

curl -sS -X PUT "${BASE_URL}/instances/${INSTANCE_ID}/token/${INSTANCE_TOKEN}/update-every-webhooks" \
  -H "Client-Token: ${CLIENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"value": "'"${WEBHOOK_URL}"'", "notifySentByMe": false}' \
  | tee /tmp/zapi-webhooks.json
```

- [ ] HTTP 200 `{ "value": true }`
- [ ] Se 404/405 → usar fallback 4× PUT (§2.2)

### 2.2 Fallback — webhooks individuais

```bash
for path in update-webhook-received update-webhook-delivery update-webhook-message-status update-webhook-disconnected; do
  curl -sS -X PUT "${BASE_URL}/instances/${INSTANCE_ID}/token/${INSTANCE_TOKEN}/${path}" \
    -H "Client-Token: ${CLIENT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"value": "'"${WEBHOOK_URL}"'"}'
done
```

- [ ] Todos retornam 200

---

## 3. Envio texto

```bash
curl -sS -X POST "${BASE_URL}/instances/${INSTANCE_ID}/token/${INSTANCE_TOKEN}/send-text" \
  -H "Client-Token: ${CLIENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"phone": "'"${TEST_PHONE}"'", "message": "ping zapi"}' \
  | tee spec/fixtures/zapi/send_text_response.json
```

- [ ] HTTP 200
- [ ] `messageId` presente
- [ ] Webhook `DeliveryCallback` recebido
- [ ] Webhook `MessageStatusCallback` com progressão de status

---

## 4. Inbound

- [ ] Enviar mensagem **de outro celular** para o número conectado
- [ ] Capturar payload `ReceivedCallback` → salvar `spec/fixtures/zapi/received_text.json`
- [ ] Validar campos: `messageId`, `phone`, `text.message`, `fromMe: false`, `type`

### 4.1 Imagem (Fase 2)

- [ ] Capturar `received_image.json` com `image.imageUrl`
- [ ] Confirmar download HTTP da URL funciona nas primeiras 24h

---

## 5. Status e disconnect

- [ ] Marcar como lida no WhatsApp → capturar `MessageStatusCallback` READ
- [ ] Salvar `spec/fixtures/zapi/status_read.json`
- [ ] Desconectar instância no app WhatsApp → `DisconnectedCallback`
- [ ] Salvar `spec/fixtures/zapi/disconnected.json`

---

## 6. Integração Chatwoot (pós-código)

- [ ] Criar inbox `provider: 'zapi'` via wizard
- [ ] QR exibido e conexão concluída
- [ ] Mensagem inbound cria conversa
- [ ] Resposta agente entrega com `source_id`
- [ ] Status read na UI
- [ ] Disconnect refletido no settings

---

## 7. Partners API (Fase 2 — opcional)

```bash
curl -sS -X POST "${BASE_URL}/instances/integrator/on-demand" \
  -H "Authorization: Bearer ${PARTNER_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @spec/fixtures/zapi/partner_create_request.json
```

- [ ] Instância criada com callbacks inline
