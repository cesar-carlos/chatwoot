# Mapeamento de features — `evolution_go` no Chatwoot

Checklist feature a feature vs código. Complementa [../feature-mapping.md](../feature-mapping.md) com detalhes específicos Evolution Go.

**Última sync código:** 17/jul/2026 · **Legenda:** ✅ implementado · ⚠️ parcial / E2E · ❌ N/A · 🔧 prepend/FORK

---

## Mensagens — outbound

| Feature Chatwoot | API Evolution Go | Fase | Componente |
|------------------|------------------|------|------------|
| Texto | `POST /send/text` | ✅ | `EvolutionGoService#send_message` |
| Mídia | `POST /send/media` | ✅ | `send_attachment_message` |
| Location | `POST /send/location` | ✅ | `send_location_message` |
| Contact card | `POST /send/contact` | ✅ | `send_contact_card_message` |
| Link preview | `POST /send/link` | ❌ | Não wired no service |
| Sticker | `POST /send/sticker` | ✅ | via attachment path |
| Poll | `POST /send/poll` | ❌ | Não wired |
| Voice note PTT | — | ❌ | Não documentado Go |
| Templates WABA | — | ❌ | `send_templates_as_text` → texto |
| Reply/quote | `quoted: { messageId, participant }` | ✅ | outbound quoted |
| Input select → buttons/list | `POST /send/button`, `/send/list` | ✅ parcial | `dispatch_input_select` |
| Interativos Meta (CW) | — | ❌ | Sem paridade WABA |
| CSAT survey | — | ❌ | — |
| Campanhas | — | ❌ | — |
| `source_id` | `data.Info.ID` | ✅ | `process_response` |
| Typing | `POST /message/presence` | ✅ | `TypingListener` → `PresenceSyncJob` → `ApiClient#set_presence` (skip private notes) |
| Mark read outbound | `POST /message/markread` | ✅ | `mark_read_on_reply`, `mark_read_on_open` |
| Delete for everyone | `POST /message/delete` | ✅ | `sync_delete_to_whatsapp` + `DeleteSyncService` (API fail reverte soft-delete local) |
| Edit message | `POST /message/edit` | ✅ | `sync_edit_to_whatsapp` + UI context menu + `MessageContentEditService` → `EditSyncService` — ADR §35 |
| React | `POST /message/react` | ✅ | Context menu + `ReactSyncService` |

---

## Mensagens — inbound

| Feature | Evento Go | Fase | Componente |
|---------|-----------|------|------------|
| Texto | `MESSAGE` | ✅ | `EvolutionGoNormalizer` |
| Mídia | `MESSAGE` (imageMessage, etc.) | ✅ | Normalizer + `ApiClient#download_media` |
| Location | `MESSAGE` locationMessage | ✅ | Normalizer |
| Contact card | `MESSAGE` contactMessage | ✅ | Normalizer → `contacts` payload |
| Button/list reply | `buttonsResponseMessage` / `listResponseMessage` | ✅ | texto com label selecionado |
| Status read | `READ_RECEIPT` | ✅ | → `statuses[]` flat (batch) |
| Dedup | — | ✅ | `lock_message_source_id!` (upstream) |
| Contato/conversa | — | ✅ | `IncomingMessageEvolutionGo` + enrichment Go |
| Reply threading | `contextInfo.stanzaId` / `stanzaID` | ✅ | `add_reply_context!` → `in_reply_to_external_id` |
| Quote outbound (própria msg) | `quoted.participant` via `instance_name` se phone `+55000…` | ✅ | `EvolutionGoServiceOutbound#channel_business_phone` |
| Avatar enrichment backoff | `/user/avatar` timeout 12s + `evolution_go_avatar_attempted_at` (6h); PictureURL/PictureID via `/user/info` | ✅ | `ContactEnrichmentService` |
| Contacts refresh (bulk) | paced enqueue 3s + dynamic lock TTL | ✅ | `ContactsRefreshService` |
| Client delete | `MESSAGE` revoke (`IsRevoke` / type 0) / `MESSAGE_DELETE` | ✅ | `MessageDeleteSyncService` (job sempre consome; soft-delete gated) |
| Client edit | `MESSAGES_EDITED` / protocol `IsEdit` + `editedMessage` | ✅ | `MessageEditSyncService` — plaintext ✅; `secretEncryptedMessage` sem texto → skip ([#92](https://github.com/evolution-foundation/evolution-go/issues/92)) |
| History import | `HISTORY_SYNC` | ✅ | `HistorySyncProcessor` · ⚠️ E2E |
| Reações | `reactionMessage` → `content_attributes.reactions` | ✅ | `ReactionsStore` + chip/menu; Node parity via `Evolution::*` |
| Pseudo-forward | — (sem API Go) | ✅ | Chatwoot-only · [message-forward/](../../message-forward/) · ADR §34 |
| Grupos | `MESSAGE` com `@g.us` | ✅ | Normalizer + `GroupContactService` quando `ignore_groups: false` · ⚠️ E2E |
| Echo fromMe | `MESSAGE` / `SEND_MESSAGE` fromMe | ✅ | filtrar ou `PhoneOutgoingSyncService` |

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
| Auth | `?token=webhook_token` |
| Formato | `{ event, instance, data }` |
| Job | prepend `WhatsappEventsJob` |
| Mutex | Redis por inbox+sender (após normalizar) |

---

## Identificadores

| Fonte | `ContactInbox#source_id` |
|-------|--------------------------|
| Inbound 1:1 `data.key.remoteJid` | dígitos antes de `@` |
| Inbound grupo `@g.us` | JID completo do grupo (`GroupContactService`) |
| Participante em grupo | `evolution_go_participant_jid` em `content_attributes` |
| LID + alt | usar `remoteJidAlt` se presente |
| Outbound ID | `data.Info.ID` (string) |

---

## Instance / conexão

| Feature | API | Fase |
|---------|-----|------|
| Create | `POST /instance/create` | ✅ |
| Connect + webhook | `POST /instance/connect` | ✅ |
| QR | `GET /instance/qr` | ✅ |
| Pairing | `POST /instance/pair` | ✅ |
| Status | `GET /instance/status` | ✅ |
| Disconnect | `POST /instance/disconnect` | ✅ |
| Logout | `DELETE /instance/logout` | ✅ (health UI) |
| Delete | teardown no destroy inbox | ✅ |

---

## Frontend

| UI | Fase | Doc |
|----|------|-----|
| Wizard form + connect + modal QR | ✅ | `EvolutionGo.vue` — [frontend-wizard-spec.md](./frontend-wizard-spec.md) |
| QR / pairing | ✅ | modal + pair API |
| Connection badge / health | ✅ | `EvolutionGoHealthPage` |
| Settings | ✅ | `EvolutionGoSettingsPage` |
| Diagnóstico + test webhook | ✅ | health page |
| Import polling | ✅ | `useEvolutionGoImportStatus` |
| Delete confirm WhatsApp sync | ✅ | `MessageContextMenu` |
| Gateway gates | ✅ | `isGatewayWhatsAppProvider` / `isGatewayWhatsAppInbox` |

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

| Fase | Features | Estado |
|------|----------|--------|
| **0** | Registry, PROVIDERS, prepends | ✅ |
| **1** | Texto in/out, QR, connect, webhook, wizard | ✅ |
| **2** | Mídia, READ_RECEIPT, markread, settings, proxy delete | ✅ |
| **3** | Location, contact, sticker, input_select→buttons/list, presence typing, reactions | ✅ (poll / link pendentes) |
| **4** | HISTORY_SYNC import | ✅ código · ⚠️ E2E fixture |
| **UX** | Avisos, diagnóstico, confirmações, grupos, delete/edit sync | ✅ |
