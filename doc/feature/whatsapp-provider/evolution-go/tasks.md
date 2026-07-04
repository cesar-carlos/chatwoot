# Tarefas — Provider Evolution Go

| ID | Tarefa | Status |
|----|--------|--------|
| I0 | Fase 0 — infra | ✅ |
| I1 | Fase 1 — MVP texto + QR + gates UI + health | ✅ |
| I1-fix | Correções revisão (prepend dev, CONNECTION, ignore_from_me_echo, server check) | ✅ |
| I2 | Fase 2 — mídia, READ_RECEIPT, settings, mark read | ✅ |
| E1 | Checklist E2E | ⚠️ pendente (operador) |
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

Ver [implementation-plan.md](./implementation-plan.md) § Fase 2.
