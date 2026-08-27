# Status — Provider Evolution Go

**Escopo do fork:** integração Chatwoot ↔ Evolution Go (REST + webhooks).

**Última revisão:** 27/ago/2026 (LID/PN §37 + dedup lock por inbox §38) · **Integração completa; E2E operador pendente**

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
| Outbound delete sync (`sync_delete_to_whatsapp`) | ✅ · sync WA first; API fail → 422 sem soft-delete local |
| UX settings (avisos, polling import, confirmações) | ✅ |
| Diagnóstico (`evolution_go_diagnostics`, test webhook) | ✅ |
| `convert_markdown_inbound`, `sync_edit_to_whatsapp` + UI edit outgoing | ✅ 17/jul/2026 |
| Import histórico (`HISTORY_SYNC` + `POST /chat/history-sync`) | ✅ código · ⚠️ fixture sintética |
| Grupos WhatsApp (`ignore_groups: false`) | ✅ · GroupInfo/JoinedGroup + warm/dedup · automação/auto-assign skip `@g.us` · Sync contact grupo · bubble sender · ⚠️ E2E |
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
| Avatar enrichment backoff (`avatar_attempted_at`, timeout 12s) | ✅ 13/jul/2026 · **18/jul LID-first + timeout 30m** |
| Contacts refresh paced (3s stagger + lock TTL) | ✅ 17/jul/2026 |
| Sync contact from conversation MoreActions | ✅ 2/ago/2026 · grupo → `GroupMetadataFetchJob`; 1:1 → `ContactEnrichmentJob` `force: true` |
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
| 1:1 LID vs PN (inbound persist + LID-only) | ✅ 27/ago/2026 · ADR §37 |
| Dedup lock por inbox (dois canais Go na mesma conta) | ✅ 27/ago/2026 · ADR §38 |
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
- Outbound delete: `DeleteSyncService` sync WA first no `destroy` (API fail → 422, CW intacto); anti-loop `@evolution_go_delete_synced_inline`; revert legado restaura `content` + flag
- Outbound edit (opt-in): `MessageContentEditService` sync WA first (`raise_errors`) + `POST …/evolution_go_edit` + `MessageEditModal` / badge (sem prefixo no texto)
- Import contatos: `ImportService`, `ContactsImporter`, enrichment (`/user/info` + PictureURL/PictureID; `/user/avatar` backoff 6h; ambos non-retryable)
- Import stuck `running` com toggles off → `abort_disabled_import!` → `idle`
- `CorruptMediaRepair` / rake `evolution_go:repair_corrupt_media`
- `PeerContactInboxResolver`, `ProviderConfigMerger`, `UrlSafetyGuard`
- 1:1 LID: `JidResolver#addressing_jid`; normalizer não dropa LID-only; `whatsapp_lid_inbound?`; enrichment promove PN→LID (ADR §37)
- Dedup inbound/`fromMe`: `EvolutionGo::MessageDedupLock` por inbox (ADR §38)
- Refresh manual de perfis: `ContactsRefreshService` (stagger 3s + lock TTL) + `POST …/evolution_go_refresh_contacts`
- Sync per-contact (menu ⋮): `POST …/contacts/:id/evolution_go_sync` — grupo → `GroupMetadataFetchJob`; 1:1 → `ContactEnrichmentJob` `force: true`
- Import histórico: `MessagesImporter`, `HistorySyncProcessor`, evento `HISTORY_SYNC`
- Diagnóstico: `DiagnosticsService`, `WebhookTestService`, `MutationStatsRecorder`
- Grupos: dispatcher `GROUP`/`GROUP_INFO`/`JOINED_GROUP`; `warm_cache_from_name!` + `schedule_metadata_fetch!` (Redis 5 min); naming `*(GROUP)`; automation + auto-assignment skip `@g.us`; `useGroupMessageSender` no bubble
- `sync_settings!` / `sync_proxy!` (advanced-settings + delete proxy)

### Frontend
- Wizard `EvolutionGo.vue` (server check, regex `instance_name`)
- `EvolutionGoSettingsPage.vue` — seções agrupadas, avisos amber, import messages, irreversível (delete/edit sync)
- `EvolutionGoHealthPage.vue` — conexão + logout + painel diagnóstico + sync webhook + teste webhook
- `useEvolutionGoImportStatus.js` — polling 5s enquanto `import_status === 'running'`
- `MessageContextMenu` — confirmação delete com aviso WhatsApp quando `sync_delete_to_whatsapp`
- ActionCable + polling QR

### API Chatwoot (custom controllers)
- Inbox: `GET evolution_go_connection`, `POST evolution_go_reconnect`, `POST evolution_go_logout`, `POST evolution_go_server_check` (collection)
- Inbox: `GET evolution_go_diagnostics`, `POST evolution_go_test_webhook`, `POST evolution_go_sync_webhook`, `POST evolution_go_pair`, `POST evolution_go_import`
- Inbox: `POST evolution_go_refresh_contacts`
- Messages: `POST …/messages/:id/evolution_go_react`, `POST …/messages/:id/evolution_go_edit`
- Contacts: `POST …/contacts/:id/evolution_go_sync` (grupo → metadata; 1:1 → enrichment)

### Specs
- Normalizer, READ_RECEIPT, ApiClient, job (MESSAGE + READ_RECEIPT + delete/edit + GroupInfo/JoinedGroup)
- Delete/edit sync services, import pipeline
- Fixture `spec/fixtures/evolution_go/history_sync.json` (sintética)
- Fixtures `message_inbound_group.json` / `message_inbound_group_lid.json` / `webhook_group_info.json` / `webhook_joined_group.json`
- AutomationRuleListener + AssignmentService + Conversation auto-assign skip `@g.us`
- Sync contact API group vs 1:1 routing

---

## Defaults novos inboxes (`ProviderConfigDefaults`)

| Campo | Default |
|-------|---------|
| `mark_inbound_deleted` | `true` |
| `mark_inbound_edited` | `true` |
| `import_on_connect` | `false` |
| `import_contacts` | `false` |
| `import_messages` | `false` |
| `days_limit_import_messages` | `100` (message **count** for history-sync, legacy key name) |
| `convert_markdown_inbound` | `true` |
| `convert_markdown_outbound` | `true` |
| `sync_delete_to_whatsapp` | `false` (opt-in) |
| `sync_edit_to_whatsapp` | `false` (opt-in) |
| `mark_read_on_reply` | `false` |
| `mark_read_on_open` | `true` |
| `sign_msg` | `false` |
| `sign_delimiter` | `"\n"` |
| `send_random_delay` | `false` |
| `notify_send_errors_private` | `true` |
| `ignore_from_me_echo` | `true` |
| `merge_brazil_contacts` | `true` |
| `send_templates_as_text` | `true` |

Lista completa: [provider-config-mapping.md](./provider-config-mapping.md). Inboxes existentes **não** são migrados — só novos inboxes recebem estes defaults.

---

## Próximo passo

1. **E2E** — [validation-checklist.md](./validation-checklist.md) com servidor Go real (sync webhook, pair, location, logout, grupos, typing presence, reply context, **edit plaintext vs `secretEncryptedMessage`**, revoke)
2. **Proxy edit** — aguarda validação `advanced-settings` (UI hoje: banner create-only)
3. **Fase 3 restante** — poll / link outbound (fora do MVP inbox)
4. **Edit/delete** — UI + anti-loop + plaintext protocol ✅ 17/jul; E2E com fixture real de produção; encrypted-only permanece skip residual ([#92](https://github.com/evolution-foundation/evolution-go/issues/92))
