# Checklist de validação — pré Fase 1

Executar **antes** de fechar o MVP texto + QR. Resultados alimentam `spec/fixtures/evolution/` e confirmam compatibilidade com [evolution-target-version.txt](./evolution-target-version.txt).

**Ambiente:** servidor Evolution staging (recomendado `evoapicloud/evolution-api:2.3.7`) + Chatwoot fork com Fase 0–1 implementada.

**Postman:** usar collection [Evolution API v2.3.*](https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3) — mapa completo em [postman-validation.md](./postman-validation.md).

---

## 0. Pré-requisitos

- [ ] `FRONTEND_URL` aponta para URL pública alcançável pela Evolution
- [ ] Chatwoot recebe `POST` externo (sem auth de firewall bloqueando Evolution)
- [ ] Evolution **sem** integração Chatwoot legada (`GET /chatwoot/find` → `enabled: false`)
- [ ] Versão Evolution registrada: `_______________`

---

## 1. Spike REST (manual)

Substituir variáveis e executar do operador ou CI de staging.

### 1.1 Criar instância

```bash
curl -sS -X POST "${BASE_URL}/instance/create" \
  -H "apikey: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "'"${INSTANCE}"'",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true,
    "groupsIgnore": true
  }' | tee /tmp/evolution-create.json
```

Opcional — proxy inline no create (formato `proxyHost`, não `host`):

```bash
# acrescentar ao JSON acima se proxy_enabled no wizard:
# "proxyHost": "proxy.example.com", "proxyPort": "8080", "proxyProtocol": "http"
```

- [ ] HTTP 2xx
- [ ] Resposta contém `hash` (instance token) e/ou `qrcode`
- [ ] Salvar `hash` → futuro `provider_config.api_key`

### 1.2 Registrar webhook Chatwoot

```bash
curl -sS -X POST "${BASE_URL}/webhook/set/${INSTANCE}" \
  -H "apikey: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "webhook": {
      "enabled": true,
      "url": "'"${FRONTEND_URL}"'/webhooks/evolution/'"${INSTANCE}"'",
      "byEvents": false,
      "base64": false,
      "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE", "QRCODE_UPDATED"]
    }
  }' | tee /tmp/evolution-webhook-set.json
```

- [ ] `GET ${BASE_URL}/webhook/find/${INSTANCE}` confirma URL e eventos

### 1.3 Conectar QR

```bash
curl -sS "${BASE_URL}/instance/connect/${INSTANCE}" \
  -H "apikey: ${API_KEY}" | tee /tmp/evolution-connect.json
```

- [ ] QR retornado (base64 ou pairing code)
- [ ] Escanear com WhatsApp → `connectionState` → `open`

```bash
curl -sS "${BASE_URL}/instance/connectionState/${INSTANCE}" \
  -H "apikey: ${API_KEY}"
```

### 1.4 sendText — formato plano

```bash
curl -sS -X POST "${BASE_URL}/message/sendText/${INSTANCE}" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"number": "'"${TEST_PHONE}"'", "text": "ping plano"}' \
  | tee spec/fixtures/evolution/send_text_response.json
```

- [ ] HTTP 2xx
- [ ] Resposta contém `key.id`
- [ ] Mensagem chega no WhatsApp

### 1.5 sendText — fallback OpenAPI (se 1.4 falhou)

```bash
curl -sS -X POST "${BASE_URL}/message/sendText/${INSTANCE}" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"number": "'"${TEST_PHONE}"'", "textMessage": {"text": "ping nested"}}'
```

- [ ] Registrar qual formato o servidor aceita em `spec/fixtures/evolution/README.md`

---

## 2. Spike webhook inbound

Enviar mensagem **do celular** para o número conectado.

- [ ] Evolution loga POST para `/webhooks/evolution/{instance}`
- [ ] Chatwoot retorna HTTP 200
- [ ] Sidekiq processa job sem erro
- [ ] Conversa + mensagem aparecem no inbox
- [ ] Salvar envelope bruto → `spec/fixtures/evolution/messages_upsert_text.json`
- [ ] Salvar output normalizer → `messages_upsert_text_normalized.json`

### Batch `data` (se aplicável)

Se o envelope tiver `data` como array:

- [ ] Normalizer processa todas as entradas (`Array.wrap`)
- [ ] Fixture `messages_upsert_batch.json` adicionado

---

## 3. Spike outbound Chatwoot → Evolution

No dashboard, responder na conversa criada no passo 2.

- [ ] Mensagem aparece no WhatsApp
- [ ] `message.source_id` no Chatwoot = `key.id` da resposta Evolution
- [ ] Sem prefixo `WAID:`
- [ ] Sem duplicata inbound (echo `fromMe`)

---

## 4. Spike conexão UI

- [ ] Wizard exibe QR (ActionCable ou polling)
- [ ] `CONNECTION_UPDATE` → badge `open`
- [ ] `api_key` **não** visível em GET inbox API (masked)

---

## 5. Testes de regressão

- [ ] Inbox `whatsapp_cloud` inalterado
- [ ] Inbox `default` (360dialog) inalterado
- [ ] Conversa antiga (>24h) aceita resposta texto livre (bypass janela)

---

## 6. Proxy (Fase 1 — se habilitado no wizard)

```bash
curl -sS -X POST "${BASE_URL}/proxy/set/${INSTANCE}" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "host": "proxy.example.com",
    "port": "8080",
    "protocol": "http"
  }'
```

- [ ] HTTP 2xx ou 400 documentado (proxy inválido)
- [ ] `GET /proxy/find/${INSTANCE}` reflete config
- [ ] WhatsApp reconecta após proxy (restart se necessário)

---

## 7. Registro

| Campo | Valor |
|-------|-------|
| Data | 2026-06-20 |
| Versão Evolution | **2.3.6** (local `/root/evolution-api`, `:8080`) |
| Formato sendText aceito | **`text` plano** — nested `textMessage` rejeitado (400) |
| Operador | spike-validation (T0) |

### Resultado T0 (REST + fixtures)

| Item | Status | Notas |
|------|--------|-------|
| 1.1 create instance | ✅ | `cw-spike-*`, hash + QR retornados |
| 1.2 webhook set/find | ✅ | URL + eventos confirmados |
| 1.3 connect QR | ✅ | base64 + code; instância spike `connecting` (sem scan) |
| 1.4 sendText plano | ✅ | HTTP 201, `key.id` presente (instância open existente) |
| 1.5 sendText nested | ❌ | 400 — fallback OpenAPI não aplicável nesta versão |
| 2 webhook inbound E2E | ⏸️ | Fixture de mensagem real via DB; E2E Chatwoot pendente |
| 3 outbound Chatwoot | ⏸️ | Requer dashboard + instância conectada via wizard |
| 4 conexão UI | ⏸️ | Fora do escopo REST spike |
| 5 regressão | ⏸️ | Manual |
| 6 proxy | ⏸️ | Fase 1 opcional |
| Bug Fase 1 | ✅ corrigido | `disable_chatwoot_integration` — body completo exigido pela Evolution |

Anexar fixtures ao PR da Fase 1.

---

## Automação futura

Contract tests com WebMock/VCR contra fixtures desta pasta — ver [spec-design.md § Testes](./spec-design.md).
