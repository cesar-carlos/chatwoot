# Status — Provider Evolution Go

**Escopo do fork:** integração Chatwoot ↔ Evolution Go (REST + webhooks).

**Última revisão:** 08/jul/2026 (code review + latency + bug fixes) · **Integração completa; E2E operador pendente**

---

## Resumo

| Área | Estado |
|------|--------|
| Fase 0 infra | ✅ |
| Fase 1 MVP texto + QR + health | ✅ |
| Fase 2 mídia, READ_RECEIPT, settings | ✅ |
| Import contatos + enrichment | ✅ |
| Inbound delete/edit (webhook → Chatwoot) | ✅ |
| Outbound delete sync (`sync_delete_to_whatsapp`) | ✅ |
| UX settings (avisos, polling import, confirmações) | ✅ |
| Diagnóstico (`evolution_go_diagnostics`, test webhook) | ✅ |
| `convert_markdown_inbound`, `sync_edit_to_whatsapp` (MVP) | ✅ |
| Import histórico (`HISTORY_SYNC` + `POST /chat/history-sync`) | ✅ código · ⚠️ fixture sintética |
| Grupos WhatsApp (`ignore_groups: false`) | ✅ código · ⚠️ fixture sintética |
| Webhook subscribe sync (`WebhookSubscribeSync`) | ✅ |
| Logout UI (health page) | ✅ |
| Pair API (`POST /instance/pair`) | ✅ |
| Location inbound/outbound | ✅ |
| GROUP webhook → metadata cache | ✅ |
| Diagnostics instance info/logs | ✅ |
| `user/check` em enrichment (opcional) | ✅ |
| `set_presence` spike (ApiClient) | ✅ |
| Gates UI (`isGatewayWhatsAppChannel`) | ✅ |
| Phone echo sync (`SEND_MESSAGE` / `fromMe`) | ✅ |
| Latency (webhook `:default`, debounce, async mark-read) | ✅ jul/2026 |
| `ProviderConfigMerger` atomic runtime writes | ✅ jul/2026 |
| `UrlSafetyGuard` on server check | ✅ jul/2026 |
| QR deferred to modal (no sync fetch on create) | ✅ jul/2026 |
| Read receipt batch processing | ✅ jul/2026 |
| `GET evolution_go_connection`, `POST evolution_go_logout`, `POST evolution_go_server_check` | ✅ |
| Fase 3 (interativos além de location, presence wiring) | ⚠️ parcial |

---

## Implementado

### Backend
- `EvolutionGo::*` services (ApiClient, ConnectionService, SettingsSync, Media*, Import*)
- `EvolutionGoService` + outbound (text, media, quote, mark read on reply/open)
- `EvolutionGoNormalizer` (text + media + markdown inbound)
- `READ_RECEIPT` no job prepend; `MarkReadService` ao abrir conversa
- Inbound delete/edit: `MessageDeleteSyncService`, `MessageEditSyncService` + eventos `MESSAGE` (revoke), `MESSAGE_DELETE`, `MESSAGES_EDITED`, etc.
- Outbound delete: `DeleteSyncService` + hook `EvolutionGoDeleteSync` em `Message`
- Outbound edit (opt-in): `EditSyncService` + hook `EvolutionGoEditSync` em `Message`
- Import contatos: `ImportService`, `ContactsImporter`, enrichment (`/user/info`, `/user/avatar`)
- Import histórico: `MessagesImporter`, `HistorySyncProcessor`, evento `HISTORY_SYNC`
- Diagnóstico: `DiagnosticsService`, `WebhookTestService`, `MutationStatsRecorder`
- Grupos: `EvolutionGoNormalizer` (group JID + participant), `GroupContactService` / `GroupParticipantService`, `ApiClient#group_info`, `GroupMetadataService` (provider-aware), `PhoneOutgoingSyncService` (outbound grupo)
- `sync_settings!` / `sync_proxy!` (advanced-settings + delete proxy)

### Frontend
- Wizard `EvolutionGo.vue` (server check, regex `instance_name`)
- `EvolutionGoSettingsPage.vue` — seções agrupadas, avisos amber, import messages, irreversível (delete/edit sync)
- `EvolutionGoHealthPage.vue` — conexão + logout + painel diagnóstico + sync webhook + teste webhook
- `useEvolutionGoImportStatus.js` — polling 5s enquanto `import_status === 'running'`
- `MessageContextMenu` — confirmação delete com aviso WhatsApp quando `sync_delete_to_whatsapp`
- ActionCable + polling QR

### API inbox (custom controller)
- `GET evolution_go_diagnostics`
- `POST evolution_go_test_webhook`
- `POST evolution_go_sync_webhook`
- `POST evolution_go_pair`
- `POST evolution_go_import`

### Specs
- Normalizer, READ_RECEIPT, ApiClient, job (MESSAGE + READ_RECEIPT + delete/edit)
- Delete/edit sync services, import pipeline
- Fixture `spec/fixtures/evolution_go/history_sync.json` (sintética)
- Fixture `spec/fixtures/evolution_go/message_inbound_group.json` (sintética)
- Normalizer group specs (3 exemplos)

---

## Defaults novos inboxes (`ProviderConfigDefaults`)

| Campo | Default |
|-------|---------|
| `mark_inbound_deleted` | `true` |
| `mark_inbound_edited` | `true` |
| `import_on_connect` | `false` |
| `convert_markdown_inbound` | `true` |
| `sync_delete_to_whatsapp` | `false` (opt-in) |
| `sync_edit_to_whatsapp` | `false` (opt-in) |
| `import_messages` | `false` |

Inboxes existentes **não** são migrados — só novos inboxes recebem estes defaults.

---

## Próximo passo

1. **E2E** — [validation-checklist.md](./validation-checklist.md) com servidor Go real (sync webhook, pair, location, logout, grupos)
2. **Presence wiring** — conectar `ApiClient#set_presence` ao typing indicator do dashboard
3. **Proxy edit** — aguarda validação `advanced-settings` (UI hoje: banner create-only)
