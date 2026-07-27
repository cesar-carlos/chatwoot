# Inbox History Migration — Estado atual

Inventário do que existe no codebase após o suporte a **WhatsApp-like A → B**, **API/Webhook A → B** e **cross-channel WA ↔ API** (histórico/leitura), incluindo hardening de UI/erros (27/jul/2026).

---

## O que funciona

| Capacidade | Detalhe |
|------------|---------|
| Entrada UI | Aba **Move history** nas settings WhatsApp-like **ou** API (`isAWhatsAppChannel \|\| isAPIInbox`) |
| Destino | Select: mesma família **ou** WA↔API; exclui a própria inbox (`Number(id)`); empty state se não houver destino |
| Preview | Contagem de conversas / contact sessions antes de confirmar |
| Confirmação | Digitar o nome da inbox origem (`woot-confirm-delete-modal`) + count |
| Escopo | **Todas** as conversas / `contact_inboxes` da origem |
| Remount | `conversation.inbox_id` + `contact_inbox_id`; `messages.inbox_id`; reporting/SLA; limpa bot assignee se não estiver no destino |
| Merge | Conversa mais recente do peer **no destino** (inclui resolved) é o container; quando o source tem múltiplas convs por contato sem peer no destino, processadas em ordem decrescente de id — a **mais nova** vira container, as mais antigas são merged + activity note |
| Merge FKs | Limpa `conversation_workflow_rule_executions`; reparent/resolve `AppliedSla` + CSAT |
| Merge metadata | Labels + `custom_attributes` + `additional_attributes` (destino vence em conflito) |
| Cleanup | Remove `ContactInbox` órfão na origem com `delete` (não `destroy!`) após move bem-sucedido |
| Grupos Evolution | `source_id` `@g.us` só entre Evolution ↔ Evolution Go; grupo → API gera UUID novo; aviso UI Evolution→Cloud |
| Grupos via API inbox | Contatos de grupo oriundos de API inbox têm o JID `@g.us` em `contact.identifier`; resolver usa esse JID ao migrar para destino Evolution family (API → WA Evolution) |
| API identity | Preserva `source_id` opaco só em API→API; colisão com outro contato → `failed` |
| Cross-channel identity | Nunca copia UUID/JID entre famílias; WA destino deriva phone (sem phone → `failed`); API destino gera UUID e **reusa** CI do contato; grupos com JID em `contact.identifier` → recuperado para destino Evolution |
| WA same-family | Preserva/`converte` `source_id` (funciona sem phone se o id for válido) |
| Anti-steal | Cria CI sem `ContactInboxBuilder` steal path |
| Progresso | Polling enquanto `pending` **ou** `running` (5s); toast ao `completed` — "Completed" se sem falhas, "Completed with N failure(s)" se `stats.failed > 0`; link para inbox destino incluso |
| Stats | `moved`, `merged`, `skipped`, `failed`, `total` — **por conversa** (sem inflar `failed` em CI vazio) |
| Auth | Administrator nas duas inboxes |
| Lock | `Inbox.lock` (ordem por id) no POST + `blocking_progress`; stale (>2h) → failed |
| Job | `mark_failed!` em falha fatal **sem** re-raise (sem retry Sidekiq inútil) |
| Calls | Remount `inbox_id`; merge reparenta `conversation_id` + `inbox_id` |
| Colisão `source_id` | Fail closed (não usa steal do ContactInboxBuilder) |
| FKs | `source_inbox_id`/`target_inbox_id` cascade; `requested_by_id` nullify |
| Erros DB | Tabela ausente → HTTP 503 `unavailable` (não 500 genérico) |

---

## O que não existe / limitações

| Item | Motivo |
|------|--------|
| Telegram / Email / Widget / Wavoip | Fora do escopo (identidade `source_id` incompatível) |
| Outbound garantido após WA ↔ API | Cross-channel é arquivo de leitura/contexto; reply no destino não é requisito |
| Credenciais / `webhook_url` do canal | Só histórico; ops devem apontar integrações ao destino |
| Seleção parcial de conversas | Move a caixa inteira |
| Dry-run / resume parcial | Happy-path; falha por peer incrementa `failed` e segue (`completed` com falhas parciais na UI) |
| Cross-provider Evolution → Cloud com grupos | Grupo JID não é válido no Cloud; peer marcado `failed` (UI avisa) |
| Sub-jobs por lote | Ainda backlog (P2) para inboxes muito grandes |
| i18n pt/pt_BR | Regra do fork: só EN |

---

## Inventário de arquivos

### Banco / model

| Arquivo | Papel |
|---------|-------|
| `db/migrate/20260725120824_fork_create_inbox_history_migrations.rb` | Tabela `inbox_history_migrations` |
| `db/migrate/20260725154500_fork_add_inbox_fks_to_inbox_history_migrations.rb` | FKs cascade/nullify |
| `custom/app/models/inbox_history_migration.rb` | Status, stats, heartbeat |

### Application layer

| Arquivo | Papel |
|---------|-------|
| `custom/app/services/custom/inboxes/history_migration/compatibility_guard.rb` | Valida account / WA↔WA / API↔API / WA↔API / lock |
| `custom/app/services/custom/inboxes/history_migration/contact_inbox_resolver.rb` | Resolve/cria `ContactInbox` no destino (anti-steal) |
| `custom/app/services/custom/inboxes/history_migration/remounter.rb` | Caso sem conflito |
| `custom/app/services/custom/inboxes/history_migration/conversation_merger.rb` | Caso com conflito + activity note |
| `custom/app/services/custom/inboxes/history_migration_service.rb` | Orquestra batches + stats + cleanup CI órfão |
| `custom/app/jobs/custom/inboxes/history_migration_job.rb` | Sidekiq `low` |

### Transport

| Arquivo | Papel |
|---------|-------|
| `config/routes.rb` | `# FORK:` `move_history`, `move_history_status` |
| `app/controllers/api/v1/accounts/inboxes_controller.rb` | Except list + `prepend_mod_with` |
| `custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb` | Actions + payload + preview + 503 |

### Frontend

| Arquivo | Papel |
|---------|-------|
| `custom/.../settingsPage/MoveInboxHistoryPage.vue` | UI + polling + preview + warnings |
| `app/javascript/.../settings/inbox/Settings.vue` | Tab `move-history` (`// FORK:`) |
| `app/javascript/dashboard/api/inboxes.js` | `postMoveHistory` / `getMoveHistoryStatus` |
| `app/javascript/.../inboxes/channelActions.js` | Store actions |

### i18n

| Arquivo | Chaves |
|---------|--------|
| `config/locales/en.yml` | `errors.inbox_history_migration.*`, `conversations.activity.inbox_history_migration.*` |
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
  "created_at": "...",
  "preview": { "conversations_count": 50, "contact_inboxes_count": 48 }
}
```

Códigos de erro comuns: `same_inbox`, `different_accounts`, `incompatible_channels`, `already_running`, `target_not_found`, `unavailable` (503).

---

## Dependências de runtime

- `ContactInbox.create!` (anti-steal; **não** usa o steal path do `ContactInboxBuilder`)
- Destino sempre considera conversas resolved (não só `Conversations::Resolver`)
- `Conversations::UnreadCounts::Refresher` — corrige unread Redis A/B
- `Conversations::ActivityMessageJob` — nota de merge
- `Custom::Whatsapp::Evolution::GroupContactService.group_jid?` — grupos

---

## Go-live checklist (500 em status/move)

Se `GET/POST …/move_history*` retornar 500/503:

1. `bundle exec rails db:migrate` (migrations `20260725120824` + `20260725154500`)
2. Restart web + Sidekiq
3. Confirmar `InboxHistoryMigration` carrega no console

---

*Última atualização: 27/jul/2026 (revisão pós-deploy: ordem de merge, toast partial, normalização phone)*
