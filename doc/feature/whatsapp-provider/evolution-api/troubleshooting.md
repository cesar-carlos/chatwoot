# Troubleshooting — Provider Evolution

Sintomas comuns, causas prováveis e ações. Complementa [validation-checklist.md](./validation-checklist.md) e [migration-from-evolution-integration.md](./migration-from-evolution-integration.md).

---

## Conexão e QR

### QR não aparece no wizard

| Causa | Verificação | Ação |
|-------|-------------|------|
| Instância não criada | `GET /instance/connectionState/{instance}` | `POST /instance/create` ou corrigir `instance_name` |
| Botão **"Abrir leitor de QR"** sem ação | Modal não abriu após create | Atualizar assets (Ctrl+F5); ver [decisions.md §17](./decisions.md) — `EvolutionQrScanModal` |
| Webhook `QRCODE_UPDATED` não chega | Logs Evolution + firewall | Polling `GET /instance/connect/{instance}`; verificar URL pública Chatwoot |
| ActionCable desconectado | DevTools → WS | Ver [decisions.md §17](./decisions.md) — evento `evolution:connection` |
| Evolution sem licença (2.4+) | `GET /license/status` | Ativar em [licensing](https://docs.evolutionfoundation.com.br/licensing) |

### QR expira / loop de reconexão

- Evolution emite `QRCODE_UPDATED` repetidamente — normal até `CONNECTION_UPDATE` com `state: open`
- Se `close` imediato após `open`: sessão duplicada (WhatsApp Web em outro lugar) — `DELETE /instance/logout` e reconectar
- Proxy mal configurado (Fase 2): testar sem proxy; Evolution retorna `400 Invalid proxy` no set

### Proxy — sintomas específicos (Fase 2)

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| HTTP 400 ao salvar proxy | `testProxy` falhou — IP de saída igual ao direto | Trocar proxy; testar com `curl -x` manualmente |
| `connecting` eterno após proxy | Socket Baileys não reconectou | `POST /instance/restart/{instance}` |
| Proxy funciona no set mas WA não conecta | Protocolo errado (`socks5` vs `http`) | Confirmar `protocol` com fornecedor |
| OpenAPI `proxyHost` vs runtime `host` | Discrepância doc | Usar `host`/`port` — [documentation-links.md §6](./documentation-links.md) |
| Proxy global `.env` conflita | `PROXY_HOST` no servidor + proxy inbox | Instância enabled sobrescreve global — ver [implementation-analysis.md §17](./implementation-analysis.md) |

### `connection_status` preso em `connecting`

```http
GET {base_url}/instance/connectionState/{instance_name}
apikey: {api_key}
```

Se permanece `connecting` > 2 min: `POST /instance/restart/{instance_name}` e novo QR.

### Reconnect / logout / restart (Fase 3)

Operações disponíveis no dashboard (**Settings → WhatsApp → Evolution** tab) e via API Chatwoot:

| Ação | Endpoint Chatwoot | Evolution API |
|------|-------------------|---------------|
| Poll status + QR | `GET /api/v1/accounts/:account_id/inboxes/:id/evolution_connection` | `GET /instance/connectionState/{instance}` |
| Reconnect (novo QR) | `POST …/evolution_reconnect` | `GET /instance/connect/{instance}` |
| Logout sessão | `POST …/evolution_logout` | `DELETE /instance/logout/{instance}` |
| Restart instância | `POST …/evolution_restart` | `POST /instance/restart/{instance}` |

**Fluxo reconnect:** `ConnectionService#reconnect!` → `connect` → atualiza `last_qr_base64` → UI exibe QR no **modal** (`EvolutionQrScanModal`). Polling a cada **5s** na aba health e **3s** no modal até `connection_status: open`. QR expira em ~45s — refresh automático ou botão **Atualizar QR**.

**Throttle de API:** `refresh_connection_status!` usa cache de **15s** por channel; `fetch_qr_if_needed!` não chama Evolution novamente se já há QR em `provider_config` ou se um fetch ocorreu nos últimos **45s** (alinhado ao modal). Health page e `GET evolution_connection` respeitam esses caches — polling agressivo não deve gerar storm na Evolution API.

**Logout:** confirmação via modal na UI (`woot-confirm-modal`). Após logout, status → `close`; escanear QR novamente para reconectar.

**Restart:** útil após alterar proxy ou sessão presa em `connecting`. Pode exigir novo QR.

**Alerta desconexão:** webhook `CONNECTION_UPDATE` com `state: close` → `Broadcaster#broadcast_disconnected` → evento ActionCable `evolution.connection_closed` para agentes do inbox.

---

## Criação do inbox (wizard)

### HTTP 422 — `Failed to create Evolution instance`

| Sintoma | Causa | Ação |
|---------|-------|------|
| Toast com menção à **API key** / `AUTHENTICATION_API_KEY` | Chave errada no formulário | Usar valor de `AUTHENTICATION_API_KEY` no `.env` do servidor Evolution — **não** o token UUID por instância do Manager |
| `401` nos logs `[EVOLUTION]` | Mesma causa | Testar: `curl -X POST {base_url}/instance/create -H "apikey: SUA_CHAVE" …` → `201` = OK |
| `instance name already exists` | `instance_name` duplicado (índice único global) | Escolher outro nome ou apagar inbox/instância antiga |
| Cleanup `failed to delete instance … HTTP 404` | Provision falhou; instância remota nunca existiu | Esperado — ignorar; corrigir causa do 422 |

**Campo Chave da API (wizard):** aceita apenas a chave **global** do servidor Evolution (`AUTHENTICATION_API_KEY`). O token exibido no Manager **após** criar uma instância é outro valor e não serve para provisionar via Chatwoot.

### Duas caixas de entrada com o mesmo nome

| Causa | Ação |
|-------|------|
| Duplo clique em **Criar e exibir QR code** | Aguardar loading; botão fica desabilitado (`isSubmitting`) |
| Retentativa após sucesso (modal não abriu / página recarregada) | Apagar inbox duplicada; usar `instance_name` único na próxima vez |
| Backend | `validate_evolution_instance_name_available!` bloqueia `instance_name` já usado |

---

## Webhooks

### Mensagens inbound não chegam no Chatwoot

| Check | Comando / local |
|-------|-----------------|
| Webhook registrado | `GET {base_url}/webhook/find/{instance_name}` — **`null` = nunca provisionado**; recriar inbox ou `ConnectionService#register_webhook!` |
| URL correta | Deve ser `https://{FRONTEND_URL}/webhooks/evolution/{instance_name}` |
| `FRONTEND_URL` | Mesma variável usada por Telegram/SMS (`app/models/inbox.rb`) — deve ser URL **pública** |
| Auth | Body contém `apikey` — deve bater com `provider_config.api_key` |
| Formato `event` | Live v2.3 envia `messages.upsert` (ponto, minúsculas) — fork normaliza via `EventNames` ([webhook-events.md](./webhook-events.md)) |
| Integração legada | `GET /chatwoot/find/{instance}` com `enabled: true` desvia tráfego para inbox API antiga — desabilitar |
| Instância pré-provider | Inboxes criados antes do fork ou migrados da integração legada podem ter `GET /webhook/find/{instance}` → `null` — usar **Reconnect** no health ou `ConnectionService#register_webhook!` |
| Eventos | MVP: `MESSAGES_UPSERT`, `CONNECTION_UPDATE`, `QRCODE_UPDATED` |
| Logs Sidekiq | Job ~5–30ms sem `IncomingMessageService` → evento não casou, normalizer retornou `nil`, ou filtro inbound; buscar `[EVOLUTION] normalizer skipped` |
| Filtros | Grupo (`@g.us`), `fromMe: true` (eco do celular), `status@broadcast` ignorados por default |

### HTTP 401 no webhook

- `apikey` do envelope ≠ `provider_config.api_key` (trocou token após create?)
- Header `apikey` alternativo — ver [decisions.md §2](./decisions.md)

### HTTP 404 no webhook

- `instance_name` na URL ≠ `provider_config.instance_name`
- Índice único: outro channel já usa esse `instance_name` ([decisions.md §3](./decisions.md))

### Mensagens duplicadas

| Causa | Ação |
|-------|------|
| Integração legada **e** provider nativo ativos | `POST /chatwoot/set` → `enabled: false` |
| Echo `fromMe` | Normalizer deve ignorar — `ignore_from_me_echo: true` |
| Retry Evolution | Dedup Redis por `source_id` — ver [decisions.md §16](./decisions.md) |
| Job processado 2x | Sidekiq retry — idempotência em `IncomingMessageBaseService` |

---

## Envio outbound

### `sendText` retorna 400

1. Testar body plano: `{ "number": "5511...", "text": "teste" }`
2. Fallback OpenAPI: `{ "number": "...", "textMessage": { "text": "..." } }` — [decisions.md §4](./decisions.md)
3. Número sem DDI ou com `+` — normalizar no `ApiClient`

### Mensagem enviada mas sem `source_id` no Chatwoot

- Resposta Evolution usa `key.id`, não `messages[0].id` Meta
- `EvolutionService#process_response` override — [differences-from-official-whatsapp.md](./differences-from-official-whatsapp.md)

### Agente bloqueado por janela 24h

- Prepend `MessageWindowService` não aplicado ou `provider != 'evolution'`
- Verificar Fase 0 em [implementation-plan.md](./implementation-plan.md)

### Template Meta não envia

Esperado no modo Baileys — `send_templates_as_text` converte para texto livre.

---

## Licenciamento (Evolution 2.4.0+)

| Sintoma | Resposta HTTP | Ação |
|---------|---------------|------|
| API inteira bloqueada | `503 LICENSE_REQUIRED` | Manager → ativar licença ou `EVOLUTION_OPERATOR_EMAIL` |
| Só manager funciona | Rotas públicas: `/license/*`, `/health`, `/manager/**` | Ver [documentation-links.md § Compatibilidade](./documentation-links.md#compatibilidade-de-versão) |

**Recomendação fork:** permanecer em **2.3.7** até validar licenciamento em staging.

---

## LID e contatos

### Contato sem telefone / conversa errada

- WhatsApp LID: usar `remoteJidAlt` quando o JID termina `@lid` **ou** `addressingMode: lid` (Evolution nem sempre envia `addressingMode`)
- Log `[EVOLUTION] normalizer skipped … remoteJid=…@lid` sem `remoteJidAlt` → capturar envelope bruto e ajustar normalizer — [webhook-events.md](./webhook-events.md)

### `phone_number` UNIQUE violation

Um número = um `Channel::Whatsapp`. Segundo inbox com mesmo número falha na validação upstream.

---

## Import histórico (Fase 4)

| Sintoma | Causa |
|---------|-------|
| Import muito lento vs legado | Legado usava SQL direto; provider usa API rate-limited |
| Mensagens faltando | `days_limit_import_messages` ou paginação `findMessages` |
| Mídia placeholder | Equivalente a `CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE` |

---

## Logs úteis

| Onde | O quê |
|------|-------|
| Evolution API | `WebhookController` — retry com backoff em falha HTTP |
| Chatwoot Rails | `EvolutionController`, `WhatsappEventsJob` prepend — inclui `[EVOLUTION] normalizer skipped` e `unhandled event=` |
| Sidekiq | Dead jobs em webhook auth / normalizer |
| Redis | Lock dedup `source_id` em incoming |

---

## Quando escalar

1. Exportar envelope webhook bruto (sanitizar `apikey`)
2. Versão Evolution exata (`GET /` ou tag Docker)
3. Trecho `provider_config` (sem `api_key`)
4. Resultado [validation-checklist.md](./validation-checklist.md) que falhou
