# Inbox History Migration — Estado atual

Inventário do que existe no codebase após o suporte a **WhatsApp-like A → B** e **API/Webhook A → B** (25/jul/2026).

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Entrada UI | Aba **Move history** nas settings WhatsApp-like **ou** API (`isAWhatsAppChannel \|\| isAPIInbox`) |
| Destino | Select filtrado pela **mesma família** (WA→WA, API→API) |
| Confirmação | Digitar o nome da inbox origem (`woot-confirm-delete-modal`) |
| Escopo | **Todas** as conversas / `contact_inboxes` da origem |
| Remount | `conversation.inbox_id` + `contact_inbox_id`; `messages.inbox_id`; reporting/SLA |
| Merge | Se `Conversations::Resolver#find` achar conversa no destino para o mesmo peer |
| Merge FKs | Limpa `conversation_workflow_rule_executions`; reparent/resolve `AppliedSla` + CSAT |
| Grupos Evolution | `source_id` `@g.us` só entre Evolution ↔ Evolution Go |
| API identity | Preserva `source_id` opaco; colisão com outro contato → `failed` |
| Progresso | Polling enquanto `pending` **ou** `running` (5s) |
| Stats | `moved`, `merged`, `skipped`, `failed`, `total` — **por conversa** |
| Auth | Administrator nas duas inboxes |
| Lock | Bloqueia `pending` e `running` frescos; stale (>2h) → failed (guard, job, status GET) |
| Calls | Remount `inbox_id`; merge reparenta `conversation_id` + `inbox_id` |
| Colisão `source_id` | Fail closed (não usa steal do ContactInboxBuilder) |
| FKs | `source_inbox_id`/`target_inbox_id` cascade; `requested_by_id` nullify |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Telegram / Email / Widget / Wavoip | Fora do escopo (identidade `source_id` incompatível) |
| Cross-channel (API ↔ WhatsApp) | Identidade UUID vs telefone/JID |
| Credenciais / `webhook_url` do canal | Só histórico; ops devem apontar integrações ao destino |
| Seleção parcial de conversas | Move a caixa inteira |
| Dry-run / resume parcial | Happy-path; falha por peer incrementa `failed` e segue |
| Cross-provider Evolution → Cloud com grupos | Grupo JID não é válido no Cloud; peer marcado `failed` |
| i18n pt/pt_BR | Regra do fork: só EN |

---

## Inventário de arquivos

### Banco / model

| Arquivo | Papel |
|---------|-------|
| `db/migrate/20260725120824_fork_create_inbox_history_migrations.rb` | Tabela `inbox_history_migrations` |
| `custom/app/models/inbox_history_migration.rb` | Status, stats, heartbeat |

### Application layer

| Arquivo | Papel |
|---------|-------|
| `custom/app/services/custom/inboxes/history_migration/compatibility_guard.rb` | Valida account / same-type (WA ou API) / lock |
| `custom/app/services/custom/inboxes/history_migration/remounter.rb` | Caso sem conflito |
| `custom/app/services/custom/inboxes/history_migration/conversation_merger.rb` | Caso com conflito |
| `custom/app/services/custom/inboxes/history_migration_service.rb` | Orquestra batches + stats (+ preserve `source_id` API) |
| `custom/app/jobs/custom/inboxes/history_migration_job.rb` | Sidekiq `low` |

### Transport

| Arquivo | Papel |
|---------|-------|
| `config/routes.rb` | `# FORK:` `move_history`, `move_history_status` |
| `app/controllers/api/v1/accounts/inboxes_controller.rb` | Except list + `prepend_mod_with` |
| `custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb` | Actions + payload |

### Frontend

| Arquivo | Papel |
|---------|-------|
| `custom/.../settingsPage/MoveInboxHistoryPage.vue` | UI + polling + filtro por família |
| `app/javascript/.../settings/inbox/Settings.vue` | Tab `move-history` (`// FORK:`) |
| `app/javascript/dashboard/api/inboxes.js` | `postMoveHistory` / `getMoveHistoryStatus` |
| `app/javascript/.../inboxes/channelActions.js` | Store actions |

### i18n

| Arquivo | Chaves |
|---------|--------|
| `config/locales/en.yml` | `errors.inbox_history_migration.*` |
| `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` | `INBOX_MGMT.TABS.MOVE_HISTORY`, `INBOX_MGMT.MOVE_HISTORY.*` |

### Specs

| Arquivo |
|---------|
| `spec/custom/services/custom/inboxes/history_migration/compatibility_guard_spec.rb` |
| `spec/custom/services/custom/inboxes/history_migration/remounter_spec.rb` |
| `spec/custom/services/custom/inboxes/history_migration/conversation_merger_spec.rb` |
| `spec/custom/services/custom/inboxes/history_migration_service_spec.rb` |
| `spec/custom/controllers/custom/api/v1/accounts/inboxes_controller_move_history_spec.rb` |

---

## API

```http
POST /api/v1/accounts/:account_id/inboxes/:id/move_history
Content-Type: application/json

{ "target_inbox_id": 123 }
```

```http
GET /api/v1/accounts/:account_id/inboxes/:id/move_history_status
```

Resposta (exemplo):

```json
{
  "id": 1,
  "status": "running",
  "stats": { "moved": 10, "merged": 2, "skipped": 0, "failed": 1, "total": 50 },
  "error_message": null,
  "source_inbox_id": 1,
  "target_inbox_id": 2,
  "started_at": "...",
  "heartbeat_at": "...",
  "completed_at": null,
  "created_at": "..."
}
```

Códigos de erro comuns: `same_inbox`, `different_accounts`, `incompatible_channels`, `already_running`, `target_not_found`.

---

## Dependências de runtime

- `ContactInboxBuilder` — gera / reusa `source_id` no destino
- `Conversations::Resolver#find` — detecta conversa existente (respeita `lock_to_single_conversation`)
- `Conversations::UnreadCounts::Refresher` — corrige unread Redis A/B
- `Custom::Whatsapp::Evolution::GroupContactService.group_jid?` — grupos

---

*Última atualização: 25/jul/2026*
