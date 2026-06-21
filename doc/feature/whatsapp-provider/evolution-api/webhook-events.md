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
| `event` | Roteamento no prepend `WhatsappEventsJob` |
| `instance` | Validar `provider_config.instance_name` |
| `data` | Payload a normalizar |
| `apikey` | Auth opcional (validar contra `provider_config.api_key`) |

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
| `CONNECTION_UPDATE` | 1 | Atualizar `connection_status` no channel |
| `QRCODE_UPDATED` | 1 | Exibir QR no wizard/settings |

### Eventos opcionais (fases posteriores)

| Evento | Uso |
|--------|-----|
| `MESSAGES_DELETE` | Apagar mensagem no Chatwoot |
| `MESSAGES_EDITED` | Edição de mensagem |
| `CONTACTS_UPSERT` | Sync contato |
| `SEND_MESSAGE` | Echo outbound (cuidado com duplicação) |

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
| LID | `xxx@lid` + `remoteJidAlt` | Usar `remoteJidAlt` se `addressingMode === 'lid'` |
| Grupo | `120363...@g.us` | Ver `ignore_jids` / `groups_ignore` |
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

Status Baileys (mapear para canônico):

| Baileys | Canônico |
|---------|----------|
| 0 / PENDING | `sent` |
| 1 / SERVER_ACK | `sent` |
| 2 / DELIVERY_ACK | `delivered` |
| 3 / READ | `read` |
| 4 / PLAYED | `read` |

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

Ação: exibir no wizard; não passar por `IncomingMessageService`.

**Rota alternativa:** polling `GET /instance/connect/:instanceName` se webhook não chegar.

---

## Filtros no normalizer (antes de normalizar)

Ordem sugerida — espelha `eventWhatsapp()`:

1. `event` não suportado → return
2. `data.key.remoteJid === 'status@broadcast'` → ignore
3. `groups_ignore` + JID termina `@g.us` → ignore (redundante se setting Evolution ativo, mas defesa em profundidade)
4. `ignore_jids` contém `@g.us` e é grupo → ignore
5. `ignore_jids` contém `@s.whatsapp.net` e é contato → ignore
6. `ignore_jids` contém JID exato → ignore
7. `fromMe: true` no UPSERT → ignore (outbound já criado pelo Chatwoot)

---

## Auth do webhook no Chatwoot

Evolution **não** assina com HMAC Meta. Opções:

| Opção | Implementação |
|-------|---------------|
| Token na URL (secundário) | `/webhooks/evolution/:instance_name?token=SECRET` |
| Header / body | Validar `apikey` do envelope contra `provider_config.api_key` (**primário**) |
| IP allowlist | Fora do escopo MVP |

`Custom::Webhooks::EvolutionController` — rota dedicada; **não** reutilizar `Webhooks::WhatsappController` (formato Meta). Ver [decisions.md](./decisions.md) §1–2 e [spec-design.md §5](./spec-design.md).

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

## Prepend `WhatsappEventsJob` — pseudocódigo

```ruby
# custom/app/jobs/custom/webhooks/whatsapp_events_job.rb
def perform(params = {})
  channel = find_channel(params)
  return super(params) unless channel&.provider == 'evolution'

  case params['event']
  when 'MESSAGES_UPSERT', 'MESSAGES_UPDATE'
    Array.wrap(params['data']).each do |data_item|
      normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer
        .new(channel, params.merge('data' => data_item)).perform
      super(normalized.merge(phone_number: channel.phone_number)) if normalized
    end
  when 'CONNECTION_UPDATE', 'QRCODE_UPDATED'
    Custom::Whatsapp::Evolution::ConnectionService.new(channel).handle_event(params)
  else
  end
end
```

**Nota:** o job upstream recebe `params` do controller WhatsApp — pode ser necessário rota dedicada ou aceitar envelope Evolution no mesmo endpoint com detecção por formato (`params['event'].present?`).

---

## Rota webhook — decisão

| Opção | Prós | Contras |
|-------|------|---------|
| **A** — `/webhooks/whatsapp/:phone` | Padrão existente | Controller espera formato Meta/360dialog — precisa detecção |
| **B** — `/webhooks/evolution/:instance_name` | Formato claro | Nova rota + `# FORK:` em `routes.rb` |

**Decisão fechada:** opção **B** — `POST /webhooks/evolution/:instance_name`. Ver [decisions.md](./decisions.md) §1–2.

**ADR job dedicado:** prepend escolhido no MVP; alternativa `EvolutionWebhookJob` — [decisions.md §16](./decisions.md).

Ver [../implementation-decision-tree.md](../implementation-decision-tree.md) §6.
