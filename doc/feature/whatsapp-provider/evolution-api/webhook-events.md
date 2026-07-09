# Webhook events — Evolution → Chatwoot

Formato dos webhooks que a Evolution envia ao Chatwoot e como o **`EvolutionNormalizer`** deve transformá-los para `IncomingMessageService`.

**Código Evolution:** `src/api/integrations/event/webhook/webhook.controller.ts` → `emit()`

---

## Envelope padrão

Evolution POST no `url` configurado em `/webhook/set`:

```json
{
  "event": "MESSAGES_UPSERT",
  "instance": "minha-instancia",
  "data": { },
  "destination": "https://chatwoot.example/webhooks/evolution/minha-instancia",
  "date_time": "2026-06-20T12:00:00.000Z",
  "sender": "5511888888888@s.whatsapp.net",
  "server_url": "https://evolution.example.com",
  "apikey": "INSTANCE-TOKEN"
}
```

| Campo | Uso no Chatwoot |
|-------|-----------------|
| `event` | Roteamento no prepend `WhatsappEventsJob` — ver **Formato do nome do evento** abaixo |
| `instance` | Validar `provider_config.instance_name` |
| `data` | Payload a normalizar |
| `apikey` | Auth opcional (validar contra `provider_config.api_key`) |

### Formato do nome do evento

Evolution API **v2.3+ em runtime** envia eventos em **minúsculas com ponto** (`messages.upsert`, `connection.update`). Fixtures de spike e OpenAPI usam **SCREAMING_SNAKE** (`MESSAGES_UPSERT`).

O fork normaliza em `Custom::Whatsapp::Evolution::EventNames` (controller + `WhatsappEventsJob`) antes do roteamento:

| Payload Evolution (live) | Após normalização |
|------------------------|-------------------|
| `messages.upsert` | `MESSAGES_UPSERT` |
| `messages.update` | `MESSAGES_UPDATE` |
| `contacts.upsert` | `CONTACTS_UPSERT` |
| `contacts.update` | `CONTACTS_UPDATE` |
| `connection.update` | `CONNECTION_UPDATE` |
| `qrcode.updated` | `QRCODE_UPDATED` |

Sem essa normalização, jobs executam em ~5–30ms sem criar mensagens (case não casa, sem erro visível).

### `webhookByEvents: true`

URL destino vira `{url}/messages-upsert` (evento em kebab-case). **Decisão:** usar `byEvents: false` e filtrar por `event` no job — URL única `POST /webhooks/evolution/:instance_name` (ver [decisions.md](./decisions.md) §1).

### `webhookBase64: true`

Mídia inline em base64 no `data.message` — útil Fase 2; MVP usa `false`.

### Headers customizados (opcional)

Evolution aceita `webhook.headers` em `POST /webhook/set` — incluindo `jwt_key` para assinar JWT no header da requisição (`webhook.controller.ts`).

| Abordagem | Quando usar |
|-----------|-------------|
| `apikey` no body do envelope | **Padrão fork** — [decisions.md §2](./decisions.md) |
| `headers: { "Authorization": "Bearer ..." }` | Se operador exigir header extra além do body |
| `jwt_key` no headers Evolution | Integrações que validam JWT — fora do MVP |

---

## Eventos necessários (MVP)

| Evento | Fase | Ação no Chatwoot |
|--------|------|------------------|
| `MESSAGES_UPSERT` | 1 | Normalizer → `IncomingMessageService` |
| `MESSAGES_UPDATE` | 2 | Status sent/delivered/read |
| `CONTACTS_UPSERT` | 2 | `ContactsSyncService` + `ContactEnrichmentJob` |
| `CONTACTS_UPDATE` | 2 | Idem — atualização de nome/foto |
| `CONNECTION_UPDATE` | 1 | Atualizar `connection_status` no channel |
| `QRCODE_UPDATED` | 1 | Exibir QR no wizard/settings |

Registrados em `ProviderConfig::WEBHOOK_EVENTS` e aplicados via `ApiClient#apply_webhook`:

| Evento | Uso |
|--------|-----|
| `MESSAGES_DELETE` | Apagar mensagem no Chatwoot (inbound) |
| `MESSAGES_EDITED` | Edição de mensagem |
| `GROUPS_UPSERT` / `GROUP_UPDATE` | Atualizar metadata/nome do contato-grupo |

### Alias e eventos não tratados

| Evento | Uso |
|--------|-----|
| `SEND_MESSAGE_UPDATE` | Alias de edição — mesmo handler que `MESSAGES_EDITED` |
| `SEND_MESSAGE` | Não tratado pelo dispatcher |

Lista completa: `EventController.events` em `src/api/integrations/event/event.controller.ts`

---

## `MESSAGES_UPSERT` — estrutura `data`

`data` é um **messageRaw** Baileys ou um **Array** de messageRaw — o normalizer deve usar `Array.wrap(data)` ([decisions.md §13](./decisions.md)).

Payload único — referência `whatsapp.baileys.service.ts` ~1353:

```json
{
  "key": {
    "remoteJid": "5511999999999@s.whatsapp.net",
    "remoteJidAlt": "5511999999999@s.whatsapp.net",
    "fromMe": false,
    "id": "3EB0XXXX",
    "addressingMode": "pn",
    "participant": null,
    "participantAlt": null
  },
  "pushName": "João",
  "message": {
    "conversation": "Olá!"
  },
  "messageType": "conversation",
  "messageTimestamp": 1718880000
}
```

### Variações importantes

| Caso | `remoteJid` | Phone para Chatwoot |
|------|-------------|---------------------|
| Contato normal | `5511...@s.whatsapp.net` | Dígitos antes de `@` |
| LID | `xxx@lid` + `remoteJidAlt` | Usar `remoteJidAlt` se JID termina `@lid` **ou** `addressingMode === 'lid'` |
| Grupo | `120363...@g.us` | `wa_id` = JID completo do grupo; contato sem `phone_number`; ver `GroupContactService` |
| Status | `status@broadcast` | **Ignorar** |
| Echo `fromMe: true` | — | Ignorar ou tratar para evitar duplicação com outbound |

**Código referência LID:** `chatwoot.service.ts` → `createConversation()` linhas ~590–593.

---

## Normalizer — payload canônico Chatwoot

Target para `Whatsapp::IncomingMessageService` (formato 360dialog-like):

```json
{
  "contacts": [
    {
      "profile": { "name": "João" },
      "wa_id": "5511999999999"
    }
  ],
  "messages": [
    {
      "from": "5511999999999",
      "id": "3EB0XXXX",
      "timestamp": "1718880000",
      "type": "text",
      "text": { "body": "Olá!" }
    }
  ]
}
```

### Mapeamento texto

| Evolution `messageType` / conteúdo | `type` canônico |
|-----------------------------------|-----------------|
| `conversation` | `text` |
| `extendedTextMessage` | `text` |
| `imageMessage` | `image` |
| `documentMessage` | `document` |
| `audioMessage` | `audio` |
| `videoMessage` | `video` |
| `stickerMessage` | `sticker` |
| `locationMessage` / `liveLocationMessage` | `location` |
| `contactMessage` / `contactsArrayMessage` | `contacts` |
| `buttonsResponseMessage` / `templateButtonReplyMessage` | `text` (label/id selecionado) |
| `listResponseMessage` | `text` (row id / title) |
| `reactionMessage` | `text` placeholder `[Reaction message]` |

Reply threading: `contextInfo.stanzaId` → `message.context.id` (paridade com Go).

### Mídia inbound

- Com `webhookBase64: false`: URL de download via API Evolution ou mídia no próprio payload após `getBase64FromMediaMessage` no lado Evolution (não disponível no webhook) — **Fase 2:** usar URL pública temporária ou endpoint Evolution de mídia.
- Override `download_attachment_file` no provider se necessário.

---

## `MESSAGES_UPDATE` — status

```json
{
  "event": "MESSAGES_UPDATE",
  "data": {
    "key": { "id": "3EB0XXXX", "remoteJid": "5511...@s.whatsapp.net", "fromMe": true },
    "update": { "status": 3 }
  }
}
```

Status Baileys (mapear para canônico) — alinhado com `EvolutionNormalizer#map_status` e enum Baileys v2.3.x:

| Código / nome | Significado Baileys | Canônico Chatwoot |
|---------------|---------------------|-------------------|
| `0` / `ERROR` | Erro | `failed` |
| `1` / `PENDING` | Pendente | `sent` |
| `2` / `SERVER_ACK` | Enviado ao servidor | `sent` |
| `3` / `DELIVERY_ACK` | Entregue | `delivered` |
| `4` / `READ` | Lida | `read` |
| `5` / `PLAYED` | Reproduzida (áudio/vídeo) | `read` |

**Formato flat Evolution (v2.3.7):** alguns webhooks enviam `keyId` + `status: "READ"` em vez de `update.status` numérico — o normalizer trata ambos (ver fixtures `messages_update_read.json` / `messages_update_delivered.json`).

Normalizer output:

```json
{
  "statuses": [
    {
      "id": "3EB0XXXX",
      "status": "read",
      "timestamp": "1718880001",
      "recipient_id": "5511999999999"
    }
  ]
}
```

Reuso: `IncomingMessageBaseService#process_statuses`.

---

## `CONNECTION_UPDATE`

```json
{
  "event": "CONNECTION_UPDATE",
  "data": {
    "instance": "minha-instancia",
    "state": "open",
    "statusReason": 200
  }
}
```

Ação: atualizar `provider_config.connection_status` e broadcast ActionCable `evolution:connection:{inbox_id}` ([decisions.md §17](./decisions.md)).

---

## `QRCODE_UPDATED`

```json
{
  "event": "QRCODE_UPDATED",
  "data": {
    "qrcode": {
      "base64": "data:image/png;base64,...",
      "code": "2@..."
    }
  }
}
```

Ação: persistir `last_qr_base64` / `last_qr_code`; broadcast ActionCable com `qrcode_base64` e `qrcode_code` (mesmas chaves que `GET …/evolution_connection`); não passar por `IncomingMessageService`.

**Rota alternativa:** polling `GET …/evolution_connection` (Chatwoot); busca QR em cache ou chama Evolution `connect` quando cache vazio e instância desconectada.

---

## Filtros no normalizer (antes de normalizar)

Ordem sugerida — espelha `eventWhatsapp()`:

1. `event` não suportado → return
2. `data.key.remoteJid === 'status@broadcast'` → ignore
3. `groups_ignore` + JID termina `@g.us` → ignore (redundante se setting Evolution ativo, mas defesa em profundidade)
4. `ignore_jids` contém `@g.us` e é grupo → ignore
5. `ignore_jids` contém `@s.whatsapp.net` e é contato → ignore
6. `ignore_jids` contém JID exato → ignore
7. `fromMe: true` no UPSERT → `PhoneOutgoingSyncService` (ou ignore se `ignore_from_me_echo` ativo)

---

## Auth do webhook no Chatwoot

Evolution **não** assina com HMAC Meta. Opções:

| Opção | Implementação |
|-------|---------------|
| Token na URL (secundário) | `/webhooks/evolution/:instance_name?token=SECRET` — validado contra `provider_config.webhook_token` (gerado no provision) |
| Header / body | Validar `apikey` do envelope contra `provider_config.api_key` (**primário**) |
| IP allowlist | Fora do escopo MVP |

`Webhooks::EvolutionController` (`custom/app/controllers/webhooks/evolution_controller.rb`) — rota dedicada; **não** reutilizar `Webhooks::WhatsappController` (formato Meta). Normaliza `event` via `EventNames` antes do enqueue. Ver [decisions.md](./decisions.md) §1–2 e [spec-design.md §5](./spec-design.md).

---

## Idempotência e retry

| Comportamento | Detalhe |
|---------------|---------|
| Evolution retry | `retryWebhookRequest` com backoff se Chatwoot não retorna 2xx |
| Chatwoot | Responder `200` imediato; processar no job async |
| Dedup | `IncomingMessageBaseService` — lock Redis por `source_id` |
| Logs | Não persistir `apikey` do envelope em logs de aplicação |

Ver [decisions.md §14](./decisions.md) · [troubleshooting.md](./troubleshooting.md).

---

## Pipeline inbound (código real)

Fluxo após `POST /webhooks/evolution/:instance_name`:

```
EvolutionController → WhatsappEventsJob (prepend) → WebhookDispatcher
  ├─ MESSAGES_UPSERT / MESSAGES_UPDATE → EvolutionNormalizer → MessageMutex → IncomingMessageService
  │     └─ fromMe: true → PhoneOutgoingSyncService (ou skip se ignore_from_me_echo)
  ├─ MESSAGES_DELETE → MessageDeleteSyncService (mutex)
  ├─ MESSAGES_EDITED → MessageEditSyncService (mutex)
  ├─ CONTACTS_UPSERT / CONTACTS_UPDATE → ContactsSyncJob (async)
  ├─ CONNECTION_UPDATE / QRCODE_UPDATED → ConnectionService#handle_event
  └─ outro evento → log warn com instance_name
```

**Arquivos:** `custom/app/controllers/webhooks/evolution_controller.rb`, `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb`, `custom/app/services/custom/whatsapp/evolution/webhook_dispatcher.rb`.

O prepend do job **não** normaliza inline — delega para `WebhookDispatcher#dispatch(channel, params)` após `EventNames.normalize` e lookup do channel por `instance_name`.

### Mutex e dedup

| Camada | Mecanismo |
|--------|-----------|
| Webhook inbound | `MessageMutex.with_lock(channel, sender_id)` — Redis `WHATSAPP_MESSAGE_MUTEX` por inbox + remetente |
| Mensagem inbound | `IncomingMessageBaseService` — lock por `source_id` |
| Reconciliação perdidas | `LostMessagesReconciliationService` — mesmo `MessageMutex` |
| Outbound phone | `PhoneOutgoingSyncService` — `MessageDedupLock`; lock ocupado propaga `LockAcquisitionError` para retry do job |

### Mídia inbound

Normalizer enfileira `MediaDownloadJob` → `MediaAttachmentService`. Lock Redis por `message_id` liberado em `ensure`; HTTP não-2xx levanta `ApiError` (retry do job).

### Status deferido

`MESSAGES_UPDATE` pode chegar antes da mensagem existir no Chatwoot — `DeferredStatusJob` retenta até 6×; exaustão loga `[EVOLUTION] deferred status dropped …`.

---

## Prepend `WhatsappEventsJob` — referência (não duplicar lógica aqui)

```ruby
# custom/app/jobs/custom/webhooks/whatsapp_events_job.rb (resumo)
def perform(params = {})
  params = params.with_indifferent_access
  return super(params) unless evolution_envelope?(params)

  params = params.merge(event: Custom::Whatsapp::Evolution::EventNames.normalize(params[:event]))
  channel = find_evolution_channel(params)
  return unless channel

  Custom::Whatsapp::Evolution::WebhookDispatcher.new.dispatch(channel, params)
end
```

Roteamento de eventos, `fromMe`, DELETE/EDIT e mutex: ver `webhook_dispatcher.rb` — **não** reimplementar no job.

**Nota:** o job upstream ainda expõe `process_events` (privado) usado pelo dispatcher após normalização.

---

## Rota webhook — decisão

| Opção | Prós | Contras |
|-------|------|---------|
| **A** — `/webhooks/whatsapp/:phone` | Padrão existente | Controller espera formato Meta/360dialog — precisa detecção |
| **B** — `/webhooks/evolution/:instance_name` | Formato claro | Nova rota + `# FORK:` em `routes.rb` |

**Decisão fechada:** opção **B** — `POST /webhooks/evolution/:instance_name`. Ver [decisions.md](./decisions.md) §1–2.

**ADR job dedicado:** prepend escolhido no MVP; alternativa `EvolutionWebhookJob` — [decisions.md §16](./decisions.md).

Ver [../implementation-decision-tree.md](../implementation-decision-tree.md) §6.
