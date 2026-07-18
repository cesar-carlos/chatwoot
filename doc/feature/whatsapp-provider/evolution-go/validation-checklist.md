# Checklist E2E — integração Evolution Go

Validação operacional contra uma **instância Evolution Go já provisionada pelo operador**. Código das fases 0–4 já implementado — este checklist confirma contratos reais vs fixtures sintéticas. Referências: [postman-validation.md](./postman-validation.md), [decisions.md](./decisions.md), [webhook-events.md](./webhook-events.md).

**Variáveis:** `BASE_URL`, `GLOBAL_API_KEY`, `INSTANCE_TOKEN`, `WEBHOOK_TOKEN`, `FRONTEND_URL` (público para webhook), `TEST_PHONE`

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
WEBHOOK_URL="${FRONTEND_URL}/webhooks/evolution_go/${INSTANCE}?token=${WEBHOOK_TOKEN}"

curl -sS -X POST "${BASE_URL}/instance/connect" \
  -H "apikey: ${INSTANCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "webhookUrl": "'"${WEBHOOK_URL}"'",
    "subscribe": ["MESSAGE", "SEND_MESSAGE", "SEND_MESSAGE_UPDATE", "CONNECTION", "QRCODE", "READ_RECEIPT", "MESSAGE_DELETE", "MESSAGES_DELETE", "MESSAGES_EDITED", "MESSAGE_EDIT", "HISTORY_SYNC"],
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
- [ ] `POST /message/downloadmedia` inbound mídia — ADR §25 (sem `downloadimage`)
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

## 4b. UX / sync / import (jul/2026)

- [ ] Settings toggles persistem após F5 (`channel.provider_config`)
- [ ] Import contatos — status `running` → polling atualiza UI
- [ ] Cliente apaga mensagem no WA → reflete no CW (`mark_inbound_deleted`): texto original permanece + destaque deleted + aviso i18n
- [ ] Cliente edita mensagem no WA → reflete no CW com plaintext (`IsEdit` + `editedMessage`; ID = `protocolMessage.key.ID`); se só `secretEncryptedMessage`, CW não muda e **não** cria unsupported (log `skipped encrypted edit envelope`) — salvar fixture real dos dois casos
- [ ] Contato envia mídia view once → CW mostra aviso localizado (`VIEW_ONCE_MEDIA_UNAVAILABLE` / `view_once_unavailable`), não `[Unsupported message type]` genérico
- [ ] Meta AI (ou bot `@bot`) responde no WA → CW mostra texto de `richResponseMessage.submessages[].messageText`, não `[Unsupported message type]`; rich só-imagem → `[AI message]`
- [ ] Agente apaga/edita no celular → reflete no CW (mesmo com `ignore_from_me_echo: true` se vier em `MESSAGE` / `SEND_MESSAGE` protocol); edit só se payload tiver texto
- [ ] Agente apaga com `sync_delete_to_whatsapp` — confirmação + delete no WA (só outgoing); falha API **reverte** soft-delete local
- [ ] Edit outbound (`sync_edit_to_whatsapp`): **agente e admin** veem Edit → modal → WA sync first → CW; falha API não altera CW; badge “Edited” sem prefixo no texto; caption de mídia editável
- [ ] Refresh contatos paced (~3s) + PictureURL; import stuck `running` com toggles off → `idle`
- [ ] Painel diagnóstico exibe webhook URL e `mutation_stats`
- [ ] `POST evolution_go_test_webhook` retorna `ok: true`
- [ ] `POST evolution_go_sync_webhook` atualiza `webhook_subscribe` no channel
- [ ] `rake evolution_go:sync_webhooks` sincroniza todos os inboxes Go
- [ ] Logout na health page desconecta sessão (`POST evolution_go_logout`)
- [ ] Pairing code via `POST evolution_go_pair` com `{ phone }` retorna `pairing_code`
- [ ] Location inbound (`message_inbound_location.json`) → attachment no Chatwoot
- [ ] Location outbound (agente envia pin) → `POST /send/location`
- [ ] `POST /chat/history-sync` body `{ count, messageInfo }` (`count` = mensagens, não dias) + evento `HISTORY_SYNC` real (salvar fixture)
- [ ] Contato inbound (`contactMessage`) → attachment contact no Chatwoot
- [ ] Reply no WhatsApp → mensagem no CW com `in_reply_to_external_id` (contextInfo.stanzaId)
- [ ] Button/list reply inbound → texto com label selecionado
- [ ] Typing no dashboard → `POST /message/presence` (`composing` / `paused`); nota privada não envia
- [ ] Mark-read ao abrir conversa de grupo (`@g.us`) envia `/message/markread`
- [ ] Contato 1:1 inbound enriquece avatar/perfil (`ContactEnrichmentJob`)
- [ ] Contato com `@lid` sem avatar: Sync / inbound usa `/user/avatar` com LID (não só phone); timeout grava `avatar_timeout_at` (30 min), não cooldown 6h; LID vazio + PN timeout → só 30 min (não 6h prematuro)
- [ ] Menu ⋮ → **Sync contact info** / **Sincronizar dados do contato** (só inbox Evolution Go) → toast “started”; nome/avatar atualizam em alguns segundos (`force: true`)
- [ ] Echo celular (`SEND_MESSAGE` / `fromMe`) aparece como outgoing no Chatwoot
- [ ] `evolution_go_server_check` bloqueia URLs internas (SSRF guard)
- [ ] Reação do cliente no WA → chip na mensagem alvo (sem `[Reaction message]`)
- [ ] Trocar / remover reação do cliente atualiza o chip
- [ ] Context menu → **Reações** → expandir painel → emoji → aparece no WhatsApp e chip no CW (optimistic UI; rollback se falhar)
- [ ] Contato com `identifier` `@lid`: reação outbound gruda no WA (não só chip local)
- [ ] Remover reação no context menu limpa o chip do agente
- [ ] Clique no chip destacado (`user:self`) remove a reação do negócio
- [ ] Reagir no dashboard após echo `fromMe` **substitui** (não duplica) o chip
- [ ] Lista de conversas sobe (`last_activity_at`) sem unread artificial
- [ ] Inbox `evolution` (Node): mesma UX + `sendReaction`
- [ ] Após E2E Go: anotar resultado de `/message/react` em `evolution-target-version.txt`
- [ ] Context menu → Forward → modal com recentes + busca; encaminhar texto/mídia para até 5 chats do mesmo inbox
- [ ] Destino recebe mensagem no WhatsApp; no CW aparece badge “Forwarded”
- [ ] Agente permanece na conversa atual após encaminhar; toast de sucesso/parcial/falha

### 4c. Grupos (`ignore_groups: false`)

- [ ] Toggle **Ignorar grupos** desligado no inbox
- [ ] Enviar mensagem em grupo WhatsApp → **uma** conversa com nome do grupo
- [ ] `ContactInbox#source_id` = JID `@g.us` (não telefone do participante)
- [ ] Mensagens de participantes diferentes no mesmo grupo → mesma conversa
- [ ] Resposta do agente no Chatwoot → chega no grupo
- [ ] Salvar fixture real: `message_inbound_group.json`

---

## 6. Webhook subscribe sync

```bash
curl -sS -X POST "${CHATWOOT_BASE}/api/v1/accounts/${ACCOUNT_ID}/inboxes/${INBOX_ID}/evolution_go_sync_webhook" \
  -H "api_access_token: ${API_TOKEN}" | tee /tmp/evogo-sync-webhook.json
```

- [ ] HTTP 2xx
- [ ] `webhook_subscribe` inclui eventos canônicos (delete, edit, history)
- [ ] Com `ignore_groups: false`, lista inclui `GROUP`

## 7. Pairing code

```bash
curl -sS -X POST "${CHATWOOT_BASE}/api/v1/accounts/${ACCOUNT_ID}/inboxes/${INBOX_ID}/evolution_go_pair" \
  -H "api_access_token: ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"phone": "'"${TEST_PHONE}"'"}' | tee spec/fixtures/evolution_go/pair_response.json
```

- [ ] HTTP 2xx · `pairing_code` presente
- [ ] Código aceito no WhatsApp → `connection_status: open`

---

## 5. Documentar resultados

- [ ] [evolution-target-version.txt](./evolution-target-version.txt)
- [ ] [postman-validation.md](./postman-validation.md) — checklist pós-E2E
- [ ] [status.md](./status.md) — fechar G1–G4
- [ ] `spec/fixtures/evolution_go/README.md`
