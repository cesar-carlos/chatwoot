# Tarefas — Provider Evolution Go

| ID | Tarefa | Status |
|----|--------|--------|
| I0 | Fase 0 — infra | ✅ |
| I1 | Fase 1 — MVP texto + QR + gates UI + health | ✅ |
| I1-fix | Correções revisão (prepend dev, CONNECTION, ignore_from_me_echo, server check) | ✅ |
| I2 | Fase 2 — mídia, READ_RECEIPT, settings, mark read | ✅ |
| I2b | Import contatos + enrichment + inbound delete/edit | ✅ |
| I2c | Outbound delete sync + settings save fix | ✅ |
| UX1 | UX settings (avisos, agrupamento, polling import, confirmações) | ✅ |
| UX2 | Diagnóstico + test webhook + `mutation_stats` | ✅ |
| UX3 | `convert_markdown_inbound`, proxy banner, i18n `mark_read_on_reply`, `sync_edit_to_whatsapp` | ✅ |
| I4 | Import histórico (`HISTORY_SYNC`, `MessagesImporter`, UI `import_messages`) | ✅ código · ⚠️ E2E |
| G1 | Grupos WhatsApp (`ignore_groups: false` → conversa por grupo) | ✅ código · ⚠️ E2E |
| E1 | Checklist E2E completo | ⚠️ pendente (operador) |
| I3 | Fase 3 — interativos, presence | ❌ |

## I2 — Fase 2 (concluída)

| # | Entrega |
|---|---------|
| 2.1 | `send_attachment_message` → `POST /send/media` |
| 2.2 | Mídia inbound (`MediaDownloadJob` + `download_media`) |
| 2.3 | `READ_RECEIPT` → statuses |
| 2.4 | Quote reply `{ messageId, participant }` |
| 2.5 | `sync_settings!` (advanced-settings) + `sync_proxy!` (delete) |
| 2.6 | `MarkReadService` ao abrir conversa |
| 2.7 | `EvolutionGoSettingsPage` + proxy remove UI |

## UX / operações (jul/2026)

| # | Entrega |
|---|---------|
| UX-1 | i18n avisos (`SYNC_DELETE_WARNING`, `IMPORT_RUN_WARNING`, `PROXY_CREATE_ONLY`, `INBOUND_ONLY_NOTE`) |
| UX-2 | Defaults novos inboxes (`mark_inbound_*` true, `import_on_connect` false) |
| UX-3 | `useEvolutionGoImportStatus` — polling import |
| UX-4 | Confirmação import manual + delete com sync WhatsApp no context menu |
| UX-5 | `GET evolution_go_diagnostics` + painel em `EvolutionGoHealthPage` |
| UX-6 | `POST evolution_go_test_webhook` |
| UX-7 | `mutation_stats` (`inbound_delete_skipped`, `inbound_edit_skipped`) |
| UX-8 | `sync_edit_to_whatsapp` + `EditSyncService` (MVP, sem UI nativa de editar mensagem) |

## I4 — Import histórico (código concluído)

| # | Entrega |
|---|---------|
| 4.1 | `ApiClient#history_sync` → `POST /chat/history-sync` |
| 4.2 | Handler `HISTORY_SYNC` + `HistorySyncProcessor` |
| 4.3 | `MessagesImporter` + fase `messages` no `Import::Runtime` |
| 4.4 | UI `import_messages` + `days_limit_import_messages` |

Ver [implementation-plan.md](./implementation-plan.md).

## G1 — Grupos WhatsApp (código concluído)

| # | Entrega |
|---|---------|
| G1.1 | `EvolutionGoPayloadAdapter` — group JID + participant |
| G1.2 | `EvolutionGoNormalizer` — `resolve_wa_id`, metadata, `evolution_go_participant_jid` |
| G1.3 | `IncomingMessageIdentifierHelper` — rota grupo para `evolution_go` |
| G1.4 | `ApiClient#group_info` + `GroupMetadataService` provider-aware |
| G1.5 | `PhoneOutgoingSyncService` — outbound para grupo |
| G1.6 | Fixture `message_inbound_group.json` + specs normalizer |
