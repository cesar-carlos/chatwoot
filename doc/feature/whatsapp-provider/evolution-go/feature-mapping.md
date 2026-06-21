# Mapeamento de features — `evolution_go` no Chatwoot

Checklist feature a feature para implementação. Complementa [../feature-mapping.md](../feature-mapping.md) com detalhes específicos Evolution Go.

**Legenda:** ✅ adapter simples · ⚠️ não trivial · ❌ N/A MVP · 🔧 prepend/FORK

---

## Mensagens — outbound

| Feature Chatwoot | API Evolution Go | Fase | Componente |
|------------------|------------------|------|------------|
| Texto | `POST /send/text` | 1 | `EvolutionGoService#send_message` |
| Mídia | `POST /send/media` | 2 | `send_attachment_message` |
| Location | `POST /send/location` | 3 | — |
| Contact card | `POST /send/contact` | 3 | — |
| Link preview | `POST /send/link` | 3 | — |
| Sticker | `POST /send/sticker` | 3 | — |
| Poll | `POST /send/poll` | 3 | — |
| Voice note PTT | — | ❌ | Não documentado Go |
| Templates WABA | — | ❌ | `send_templates_as_text` → texto |
| Reply/quote | `quoted: { messageId, participant }` | 2 | override send |
| Interativos CW | — | ❌ | Sem paridade Meta buttons |
| CSAT survey | — | ❌ | — |
| Campanhas | — | ❌ | — |
| `source_id` | `data.Info.ID` | 1 | `process_response` |
| Typing | `POST /message/presence` | 3 | — |
| Mark read outbound | `POST /message/markread` | 2 | `mark_read_on_reply` |

---

## Mensagens — inbound

| Feature | Evento Go | Fase | Componente |
|---------|-----------|------|------------|
| Texto | `MESSAGE` | 1 | `EvolutionGoNormalizer` |
| Mídia | `MESSAGE` (imageMessage, etc.) | 2 | Normalizer + download |
| Status read | `READ_RECEIPT` | 2 | → `statuses[]` flat |
| Dedup | — | 1 | `lock_message_source_id!` (upstream) |
| Contato/conversa | — | 1 | `IncomingMessageBaseService` |
| Reply threading | `quoted` no data | 2 | `process_in_reply_to` |
| Reações | reaction no MESSAGE | 3 | ignorar ou placeholder |
| Grupos | `GROUP` / `@g.us` | ❌ MVP | filtrar |
| Echo fromMe | `MESSAGE` fromMe | 1 | filtrar |

---

## Templates e janela 24h

| Regra | Ação fork |
|-------|-----------|
| Janela 24h Meta | 🔧 `MessageWindowService` → `nil` |
| Templates Meta | `sync_templates` noop |
| UI template picker | ocultar |
| `send_template` | texto via `/send/text` |

---

## Webhooks

| Aspecto | Evolution Go |
|---------|--------------|
| Rota Chatwoot | `POST /webhooks/evolution_go/:instance_name` |
| Registro | `webhookUrl` no connect |
| Auth | `?token=webhook_secret` |
| Formato | `{ event, instance, data }` |
| Job | prepend `WhatsappEventsJob` |
| Mutex | Redis por inbox+sender (após normalizar) |

---

## Identificadores

| Fonte | `ContactInbox#source_id` |
|-------|--------------------------|
| Inbound `data.key.remoteJid` | dígitos antes de `@` |
| LID + alt | usar `remoteJidAlt` se presente |
| Outbound ID | `data.Info.ID` (string) |

---

## Instance / conexão

| Feature | API | Fase |
|---------|-----|------|
| Create | `POST /instance/create` | 1 |
| Connect + webhook | `POST /instance/connect` | 1 |
| QR | `GET /instance/qr` | 1 |
| Pairing | `POST /instance/pair` | 1 |
| Status | `GET /instance/status` | 1 |
| Disconnect | `POST /instance/disconnect` | 3 |
| Logout | `DELETE /instance/logout` | 3 |
| Delete | `DELETE /instance/delete/{id}` | 3 |

---

## Frontend

| UI | Fase | Doc |
|----|------|-----|
| Wizard 3 steps | 1 | [frontend-wizard-spec.md](./frontend-wizard-spec.md) |
| QR / pairing | 1 | idem |
| Connection badge | 2 | [inbox-business-rules.md](./inbox-business-rules.md) |
| Settings abas | 2 | idem |
| `isEvolutionGoWhatsAppChannel` | 1 | idem |

---

## Voz

| Feature | Evolution Go |
|---------|--------------|
| Webhook `CALL` | existe — projeto separado |
| Meta Calling API | ❌ |
| Canal Chatwoot | `whatsapp_call` cloud only |

Ver [../whatsapp-voice/README.md](../../whatsapp-voice/README.md).

---

## Fases × entregáveis

| Fase | Features |
|------|----------|
| **0** | Registry, PROVIDERS, prepends |
| **1** | Texto in/out, QR, connect, webhook, wizard |
| **2** | Mídia, READ_RECEIPT, markread, settings, proxy delete |
| **3** | Reply, presence, react, sticker, location |
| **4** | HISTORY_SYNC import |
