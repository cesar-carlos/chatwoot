# Validação Postman — Z-API Collection

Revisão da collection **[Z-API Collection](https://go.postman.co/collection/1696280-cea57506-b9de-4e61-b4d5-227743bd8151)** via Postman MCP contra documentação do fork.

**Collection analisada:** fork `9985534-cdcfbd61-4ce9-451d-80a8-fe3c5cd6da6d` (Cesar Carlos, 23/jun/2026)

**Origem:** fork de `1696280-cea57506-b9de-4e61-b4d5-227743bd8151` (Z-API org, workspace público)

**Última revisão:** 23/jun/2026

---

## Como usar esta página com o Postman

1. Abrir o fork no Postman: [link](https://go.postman.co/collection/9985534-cdcfbd61-4ce9-451d-80a8-fe3c5cd6da6d)
2. Configurar environment:
   - `BASE_URL` = `https://api.z-api.io`
   - `INSTANCE_ID`, `INSTANCE_TOKEN`, `CLIENT_TOKEN` do painel Z-API
   - `PARTNER_AUTH_TOKEN` (opcional, API Partners)
3. Conferir método + path nas tabelas de [documentation-links.md](./documentation-links.md)
4. Para payloads de webhook, capturar exemplos reais e atualizar [webhook-events.md](./webhook-events.md)

---

## Inventário da collection (15 pastas raiz)

| Pasta | Requests (aprox.) | Relevância Chatwoot |
|-------|-------------------|---------------------|
| **Instance** | 15 | **Alta** — QR, status, disconnect |
| **Messages** | 37 | **Alta** — envio texto/mídia |
| **Webhooks** | 7 | **Alta** — configuração callbacks |
| **Contacts** | 7 | Média — sync contatos Fase 2 |
| **Chats** | 9 | Baixa — histórico não prioritário |
| **Message queue** | 3 | Baixa — debug operacional |
| **Partners** | 4 | Média — provisionamento automático |
| Mobile | 14 | Baixa — onboarding alternativo |
| Privacy | 8 | — |
| Groups | 17 | — (ignorar inbound) |
| Communities | 12 | — |
| Newsletter | 17 | — |
| Status | 2 | — |
| Calls | 1 | — |
| WhatsApp Business | ~25 | Fase futura |

**Total estimado:** ~180 requests na collection completa.

---

## Resumo — provider Chatwoot (Fase 1)

| Endpoint | Postman | Doc fork | Status |
|----------|---------|----------|--------|
| `GET .../status` | Instance → Status da instância | [documentation-links.md](./documentation-links.md) | ✅ Path confirmado |
| `GET .../qr-code` | Instance → Pegar QRCode - bytes | idem | ✅ |
| `GET .../qr-code/image` | Instance → Pegar QRCode - imagem | idem | ✅ |
| `GET .../disconnect` | Instance → Desconectar | idem | ✅ |
| `POST .../send-text` | Messages → Enviar texto simples | idem | ✅ |
| `PUT .../update-webhook-received` | Webhooks → Ao receber | [webhook-events.md](./webhook-events.md) | ✅ |
| `PUT .../update-webhook-delivery` | Webhooks → Ao enviar | idem | ✅ |
| `PUT .../update-webhook-message-status` | Webhooks → Status mensagens | idem | ✅ |
| `PUT .../update-webhook-disconnected` | Webhooks → Ao desconectar | idem | ✅ |
| `POST .../read-message` | Messages → Ler mensagens | Fase 2 | ✅ Path confirmado |
| `GET .../contacts` | Contacts → Pegar contatos | Fase 2 | ✅ |
| `POST /instances/integrator/on-demand` | Partners → Criar instância | Fase 2 | ✅ |

| **Conclusão Fase 1:** endpoints necessários existem na collection e seguem o padrão documentado. `PUT .../update-every-webhooks` confirmado na doc oficial (ausente na collection Postman). Pendente: fixtures E2E reais.

---

## Padrões confirmados (Postman MCP)

### URL base

```
https://api.z-api.io/instances/{INSTANCE_ID}/token/{INSTANCE_TOKEN}/{action}
```

### Headers

```
Client-Token: {CLIENT_TOKEN}
Content-Type: application/json
```

### Envio texto — body

```json
{
  "phone": "554499999999",
  "message": "Testando mensagem teste",
  "delayMessage": 15
}
```

### Configuração webhook — body

```json
{
  "value": "https://seu-chatwoot.com/webhooks/zapi/INSTANCE_ID/receive"
}
```

### Partners — criar instância

```
POST https://api.z-api.io/instances/integrator/on-demand
Authorization: Bearer {PARTNER_AUTH_TOKEN}
```

Body inclui URLs de callback inline (`receivedCallbackUrl`, `deliveryCallbackUrl`, etc.).

---

## Divergências / pontos de atenção

| # | Tema | Detalhe |
|---|------|---------|
| 1 | Webhooks | Doc pai citava **4** URLs; collection tem **7** (inclui `connected`, `chat-presence`, `received-delivery`) |
| 2 | Disconnect | Método `GET` (não `DELETE`/`POST` como Evolution) |
| 3 | Restart | Método `GET` |
| 4 | Mídia inbound | URLs temporárias (~30 dias) — download no job |
| 5 | `isGroup` | Filtrar no normalizer — Chatwoot não modela grupos |
| 6 | Echo outbound | Webhook `received-delivery` pode duplicar — desabilitar ou filtrar `fromMe` |
| 7 | Sem OpenAPI oficial no Postman | Inventário baseado na collection + developer.z-api.io |

---

## Próxima validação (E2E)

- [ ] Criar instância de teste no painel Z-API
- [ ] Conectar via QR e capturar resposta `GET /status`
- [ ] Registrar webhooks apontando para ngrok/staging
- [ ] Enviar texto e capturar payload `delivery` + `message-status`
- [ ] Receber mensagem externa e capturar payload `received`
- [ ] Salvar fixtures em `spec/fixtures/zapi/` (quando implementar código)
