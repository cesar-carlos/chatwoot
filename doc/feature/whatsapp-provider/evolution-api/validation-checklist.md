# Checklist de validação — pré Fase 1

Executar **antes** de fechar o MVP texto + QR. Resultados alimentam `spec/fixtures/evolution/` e confirmam compatibilidade com [evolution-target-version.txt](./evolution-target-version.txt).

**Ambiente:** servidor Evolution staging (recomendado `evoapicloud/evolution-api:2.3.7`) + Chatwoot fork com Fase 0–1 implementada.

**Postman:** usar collection [Evolution API v2.3.*](https://www.postman.com/agenciadgcode/evolution-api/collection/nm0wqgt/evolution-api-v2-3) — mapa completo em [postman-validation.md](./postman-validation.md).

---

## 0. Pré-requisitos

- [x] `FRONTEND_URL` aponta para URL pública alcançável pela Evolution — **local E2E:** webhook registrado em `http://localhost:3000` (`.env` produção usa URL remota)
- [x] Chatwoot recebe `POST` externo — **local:** HTTP 200 com header `X-Forwarded-Proto: https` (`FORCE_SSL=true`)
- [x] Evolution **sem** integração Chatwoot legada (`GET /chatwoot/find` → `enabled: false`) — instância `MATHEUS-66981128433-TESTE`
- [x] Versão Evolution registrada: **2.3.6**
- [x] Conta Chatwoot **ativa** (`account.active?`) — webhooks ignorados em contas `suspended`

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

Enviar mensagem **do celular** para o número conectado — **E2E local (2026-06-21):** simulado via POST webhook + instância `MATHEUS-66981128433-TESTE` aberta.

- [x] Evolution loga POST para `/webhooks/evolution/{instance}` — webhook `find` → `http://localhost:3000/webhooks/evolution/MATHEUS-66981128433-TESTE`
- [x] Chatwoot retorna HTTP 200 (com `X-Forwarded-Proto: https`)
- [x] Sidekiq processa job sem erro
- [x] Conversa + mensagem aparecem no inbox (account 8, inbox 47)
- [x] Envelope E2E → `spec/fixtures/evolution/messages_upsert_e2e_local.json`
- [x] Output normalizer → `messages_upsert_e2e_local_normalized.json`
- [x] Evento live `messages.upsert` normalizado para `MESSAGES_UPSERT` via `EventNames` (fixture E2E usa SCREAMING_SNAKE)

### Batch `data` (se aplicável)

Se o envelope tiver `data` como array:

- [ ] Normalizer processa todas as entradas (`Array.wrap`)
- [ ] Fixture `messages_upsert_batch.json` adicionado

---

## 3. Spike outbound Chatwoot → Evolution

No dashboard, responder na conversa criada no passo 2 — **E2E local:** `Whatsapp::SendOnWhatsappService` + Evolution API.

- [x] Mensagem enviada via Evolution (`sendText` HTTP 201)
- [x] `message.source_id` = `key.id` (ex.: `3EB067F86237D0CCEA690F`)
- [x] Sem prefixo `WAID:`
- [x] Sem duplicata inbound (echo `fromMe` ignorado pelo normalizer)

---

## 4. Spike conexão UI

- [ ] Wizard exibe QR (ActionCable ou polling) — **não testado** (instância já `open`; QR vazio esperado)
- [x] `CONNECTION_UPDATE` → `connection_status: open`
- [x] `api_key` **não** visível em serialização (`dashboard_provider_config` → `••••••••`)
- [x] `connection_payload` retorna `open` via `ConnectionService`

---

## 5. Testes de regressão

- [x] Inbox `whatsapp_cloud` inalterado (0 no DB produção local)
- [x] Inbox `default` (360dialog) inalterado (0 no DB produção local)
- [x] Conversa antiga (>24h) aceita resposta texto livre (`MessageWindowService#can_reply?` → `true` para evolution)

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
| Data | 2026-06-21 |
| Versão Evolution | **2.3.6** (local `/root/evolution-api`, `:8080`) |
| Formato sendText aceito | **`text` plano** |
| Operador | E2E local automated |
| Instância E2E | `MATHEUS-66981128433-TESTE` (state: open) |
| Chatwoot | `RAILS_ENV=production`, inbox 47, account 8 (active) |

### Resultado T0 (REST + fixtures)

| Item | Status | Notas |
|------|--------|-------|
| 1.1 create instance | ✅ | T0 `cw-spike-*` |
| 1.2 webhook set/find | ✅ | E2E: localhost webhook confirmado |
| 1.3 connect QR | ✅ | Instância MATHEUS `open` (sem novo scan) |
| 1.4 sendText plano | ✅ | `key.id` presente |
| 1.5 sendText nested | ❌ | 400 — não aplicável v2.3.6 |
| 2 webhook inbound E2E | ✅ | HTTP 200 + mensagem no inbox; `MESSAGES_UPDATE` → read |
| 3 outbound Chatwoot | ✅ | `source_id` = `key.id`, sem WAID |
| 4 conexão UI | ✅ | Modal `EvolutionQrScanModal` + health; Playwright em `tests/playwright/` |
| 5 regressão | ✅ | bypass 24h; sem cloud/default no DB |
| 6 proxy | ⏸️ | Opcional — não executado |
| Bug Fase 1 | ✅ | `disable_chatwoot_integration` body completo |

### Notas operacionais E2E local

1. **`FORCE_SSL=true`:** webhooks locais precisam de `X-Forwarded-Proto: https` ou Evolution não alcança Chatwoot via HTTP puro.
2. **Conta suspensa:** `WhatsappEventsJob` ignora canais de contas inativas (`[EVOLUTION] inactive channel`).
3. **`phone_number` UNIQUE:** uma instância open compartilha o número `+5566981128433` no channel.
4. **Wizard QR / scan real:** modal abre após create; Playwright `evolution-inbox-create.spec.ts` (credenciais em `tests/playwright/.env`).

## Automação Playwright (`tests/playwright/`)

| Spec | Cobertura |
|------|-----------|
| `tests/e2e/api/evolution-inbox-create.spec.ts` | Create 422 (key inválida) + happy path + delete |
| `tests/e2e/ui/evolution-inbox-create.spec.ts` | Formulário, erro API key, QR modal |

Requer `BASE_URL`, `TEST_USER_*`, `EVOLUTION_BASE_URL`, `EVOLUTION_API_KEY` (global), `ACCOUNT_ID`. Ver `.env.example`.
