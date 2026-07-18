# Status — Provider Evolution Go

**Escopo do fork:** integração Chatwoot ↔ Evolution Go (REST + webhooks).

**Última revisão:** 17/jul/2026 (edit/delete alinhados ao contrato Go plaintext · enrichment/refresh paced · UI Edit ✅) · **Integração completa; E2E operador pendente**

---

## Resumo

| Área | Estado |
|------|--------|
| Fase 0 infra | ✅ |
| Fase 1 MVP texto + QR + health | ✅ |
| Fase 2 mídia, READ_RECEIPT, settings | ✅ |
| Import contatos + enrichment | ✅ · query digits/LID · PictureURL/PictureID · `/user/info` non-retryable |
| Inbound delete (webhook → Chatwoot) | ✅ · revoke sempre consumido; soft-delete gated |
| Inbound edit (webhook → Chatwoot) | ✅ plaintext protocol · ⚠️ encrypted-only skip ([#92](https://github.com/evolution-foundation/evolution-go/issues/92)) |
| Phone/agent delete/edit sync (`fromMe`) | ✅ · edit só se payload tiver texto; sem invent-on-miss |
| Outbound delete sync (`sync_delete_to_whatsapp`) | ✅ · API fail reverte soft-delete local |
| UX settings (avisos, polling import, confirmações) | ✅ |
| Diagnóstico (`evolution_go_diagnostics`, test webhook) | ✅ |
| `convert_markdown_inbound`, `sync_edit_to_whatsapp` + UI edit outgoing | ✅ 17/jul/2026 |
| Import histórico (`HISTORY_SYNC` + `POST /chat/history-sync`) | ✅ código · ⚠️ fixture sintética |
| Grupos WhatsApp (`ignore_groups: false`) | ✅ código · ⚠️ fixture sintética |
| Webhook subscribe sync (`WebhookSubscribeSync`) | ✅ |
| Logout UI (health page) | ✅ |
| Pair API (`POST /instance/pair`) | ✅ |
| Location inbound/outbound | ✅ |
| GROUP webhook → metadata cache | ✅ |
| Diagnostics instance info/logs | ✅ |
| `user/check` em enrichment (opcional) | ✅ |
| `set_presence` + typing dashboard wiring | ✅ jul/2026 |
| Inbound reply context (`contextInfo.stanzaId` / `stanzaID`) | ✅ jul/2026 |
| Outbound quote `participant` com phone placeholder `+55000…` | ✅ 13/jul/2026 |
| Avatar enrichment backoff (`avatar_attempted_at`, timeout 12s) | ✅ 13/jul/2026 |
| Contacts refresh paced (3s stagger + lock TTL) | ✅ 17/jul/2026 |
| Sync contact from conversation MoreActions | ✅ 18/jul/2026 · `POST …/evolution_go_sync` · force info+avatar |
| Same-origin Active Storage download (alias hosts) | ✅ 13/jul/2026 |
| Inbound contact + button/list reply text | ✅ jul/2026 |
| Contact enrichment on inbound (Go path) | ✅ jul/2026 |
| Gates UI (`isGatewayWhatsAppChannel`) | ✅ |
| Phone echo sync (`SEND_MESSAGE` / `fromMe`) | ✅ |
| Unwrap `documentWithCaptionMessage` (PDF+caption) | ✅ jul/2026 |
| Meta AI / `richResponseMessage` (+ unwrap `botInvokeMessage`) | ✅ 18/jul/2026 |
| View-once unavailable (`IsUnavailable` / `view_once`) | ✅ jul/2026 |
| Inbound delete UX (keep text + highlight + i18n) | ✅ jul/2026 |
| Latency (webhook `:default`, debounce, async mark-read) | ✅ jul/2026 |
| `ProviderConfigMerger` atomic runtime writes | ✅ jul/2026 |
| `UrlSafetyGuard` on server check | ✅ jul/2026 |
| QR deferred to modal (no sync fetch on create) | ✅ jul/2026 |
| Read receipt batch processing | ✅ jul/2026 |
| `GET evolution_go_connection`, `POST evolution_go_logout`, `POST evolution_go_server_check` | ✅ |
| Fase 3 (poll / link outbound) | ⚠️ parcial |
| Message reactions (inbound chip + outbound menu) | ✅ 16/jul/2026 · improvements (actor/timeout/Node) · 18/jul LID + menu UX |
| Pseudo-forward (Chatwoot-only, same inbox) | ✅ 16/jul/2026 · ADR §34 |

---

## Implementado

### Backend
- `EvolutionGo::*` services (ApiClient, ConnectionService, SettingsSync, Media*, Import*)
- `EvolutionGoService` + outbound (text, media, quote, mark read on reply/open)
- `EvolutionGoNormalizer` (text + media + contact + reply context + button/list replies + richResponse/Meta AI + markdown inbound)
- Presence: `TypingListener` → `PresenceSyncJob` → `POST /message/presence`
- Contact enrichment on inbound via `IncomingMessageIdentifierHelper` + `ContactEnrichmentJob`
- `READ_RECEIPT` no job prepend; `MarkReadService` ao abrir conversa
- Inbound delete/edit: `MessageDeleteSyncService`, `MessageEditSyncService` + extractors (`IsEdit`/`IsRevoke`, `typeName`, protocol key ID)
- Encrypted edit envelope: job skip (`encrypted_edit`) — evita `[Unsupported message type]`; plaintext protocol atualiza CW
- Inbound/outbound reactions: `MessageReactionSyncService`, `ReactSyncService`, `ApiClient#react` + context menu
- Outbound delete: `DeleteSyncService` (API fail → reverte soft-delete local) + hook `EvolutionGoDeleteSync`
- Outbound edit (opt-in): `MessageContentEditService` sync WA first (`raise_errors`) + `POST …/evolution_go_edit` + `MessageEditModal` / badge (sem prefixo no texto)
- Import contatos: `ImportService`, `ContactsImporter`, enrichment (`/user/info` + PictureURL/PictureID; `/user/avatar` backoff 6h; ambos non-retryable)
- Import stuck `running` com toggles off → `abort_disabled_import!` → `idle`
- `CorruptMediaRepair` / rake `evolution_go:repair_corrupt_media`
- `PeerContactInboxResolver`, `ProviderConfigMerger`, `UrlSafetyGuard`
- Refresh manual de perfis: `ContactsRefreshService` (stagger 3s + lock TTL) + `POST …/evolution_go_refresh_contacts`
- Sync per-contact (menu ⋮): `POST …/contacts/:id/evolution_go_sync` → `ContactEnrichmentJob` `force: true` (só Evolution Go)
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
- `GET evolution_go_connection`
- `POST evolution_go_reconnect`
- `POST evolution_go_logout`
- `POST evolution_go_server_check` (collection)
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
| `days_limit_import_messages` | `100` (message **count** for history-sync, legacy key name) |

Inboxes existentes **não** são migrados — só novos inboxes recebem estes defaults.

---

## Próximo passo

1. **E2E** — [validation-checklist.md](./validation-checklist.md) com servidor Go real (sync webhook, pair, location, logout, grupos, typing presence, reply context, **edit plaintext vs `secretEncryptedMessage`**, revoke)
2. **Proxy edit** — aguarda validação `advanced-settings` (UI hoje: banner create-only)
3. **Fase 3 restante** — poll / link outbound (fora do MVP inbox)
4. **Edit/delete** — UI + anti-loop + plaintext protocol ✅ 17/jul; E2E com fixture real de produção; encrypted-only permanece skip residual ([#92](https://github.com/evolution-foundation/evolution-go/issues/92))
