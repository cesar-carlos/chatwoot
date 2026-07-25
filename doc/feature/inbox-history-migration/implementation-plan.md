# Inbox History Migration — Plano de implementação (as-built)

Documento **as-built** do MVP entregue em 25/jul/2026. Fonte normativa para manutenção; decisões em [implementation-decision-tree.md](./implementation-decision-tree.md).

---

## Objetivo

Permitir que um **administrador** mova todo o histórico de conversas/mensagens de uma inbox WhatsApp A para outra inbox WhatsApp B na mesma account, preservando identidade de canal e mesclando peers que já existam em B.

---

## Fases entregues

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | Migration + model `InboxHistoryMigration` | ✅ |
| 2 | `CompatibilityGuard` | ✅ |
| 3 | `Remounter` (sem conflito) | ✅ |
| 4 | `ConversationMerger` (com conflito) | ✅ |
| 5 | `HistoryMigrationService` + Job | ✅ |
| 6 | Rotas + controller prepend | ✅ |
| 7 | UI settings + polling + i18n EN | ✅ |
| 8 | Specs `spec/custom/…` | ✅ |
| 9 | Docs `doc/feature/inbox-history-migration/` | ✅ |

---

## Detalhe técnico

### 1. Compatibilidade (`compatible?`)

```ruby
(whatsapp_like?(source) && whatsapp_like?(target)) ||
  (source.api? && target.api?) ||
  (whatsapp_like?(source) && target.api?) ||
  (source.api? && whatsapp_like?(target))
```

`whatsapp_like?` = `inbox.whatsapp? || inbox.twilio_whatsapp?`

Mesma `account_id`, `source.id != target.id`, nenhuma migration `blocking_progress` em A ou B.

- API→API preserva `contact_inbox.source_id` no builder (sessão opaca).
- WA↔API: **nunca** copia `source_id` entre famílias; destino WA deriva phone (sem phone → peer `failed`); destino API gera UUID e reusa CI existente do contato (idempotente).
- WA↔WA: preserva/`converte` `source_id` (Twilio↔Cloud); funciona sem `phone_number` se o id for válido.
- Criação de CI **sem** steal do `ContactInboxBuilder`.
- Outbound no destino cross-channel não é requisito.
### 2. Remount (sem conversa no destino)

1. ContactInbox no destino (reusa CI do contato se existir; senão source_id portátil / phone / UUID)
2. Transaction:
   - `conversation.update!(inbox_id:, contact_inbox_id:)`
   - limpar assignee se não for member de B
   - `Message` / `ReportingEvent` / `SlaEvent` → `inbox_id = B`
3. `Conversations::UnreadCounts::Refresher`

### 3. Merge (já existe conversa no destino)

1. Conversa mais recente do `contact_inbox` de B (**inclui resolved**)
2. Reparent: messages, mentions, participants (sem colidir UNIQUE), notifications, CSAT, reporting, SLA
3. Labels + `custom_attributes` + `additional_attributes` (destino vence em chave duplicada via `merge`)
4. Abortar destroy se origem ainda tiver messages
5. `source_conversation.destroy!`

### 4. Orquestração

```ruby
source_inbox.contact_inboxes.find_each do |ci|
  ci.with_lock { ... Remounter ou ConversationMerger ... }
  touch_heartbeat! a cada 25 peers
end
```

Status: `pending` → `running` → `completed` | `failed`.

### 5. API / UI

- `POST …/inboxes/:id/move_history` `{ target_inbox_id }`
- `GET …/inboxes/:id/move_history_status` (expira stale pending/running)
- Tab `move-history` em `Settings.vue` quando `isAWhatsAppChannel || isAPIInbox`
- Destinos: mesma família **ou** WA↔API; empty state; mostra destino + progresso + falhas parciais
- Lock: `Inbox.lock` no POST + `pending`/`running` frescos bloqueiam novo start

### 6. Calls / colisões

- Remounter atualiza `calls.inbox_id`; Merger reparenta `conversation_id` + `inbox_id`
- Colisão de `source_id` no destino com outro contato → `failed` (sem steal)

---

## Schema

```ruby
create_table :inbox_history_migrations do |t|
  t.references :account, null: false, foreign_key: true
  t.bigint :source_inbox_id, null: false
  t.bigint :target_inbox_id, null: false
  t.bigint :requested_by_id
  t.string :status, null: false, default: 'pending'
  t.jsonb :stats, null: false, default: {}
  t.text :error_message
  t.datetime :started_at
  t.datetime :heartbeat_at
  t.datetime :completed_at
  t.timestamps
end
```

---

## Aceite (MVP)

- [x] Admin move histórico WhatsApp A → B
- [x] Agente recebe 401/unauthorized
- [x] Destino incompatível (ex.: Email) → `incompatible_channels`
- [x] API ↔ WhatsApp permitido (histórico; identity nativa no destino)
- [x] Conversa sem peer em B → remount (`moved`)
- [x] Peer já em B → merge (`merged`)
- [x] UI mostra status/stats via poll
- [x] Specs verdes

### Comando de teste

```bash
bundle exec rspec \
  spec/custom/services/custom/inboxes/history_migration/compatibility_guard_spec.rb \
  spec/custom/services/custom/inboxes/history_migration/remounter_spec.rb \
  spec/custom/services/custom/inboxes/history_migration/conversation_merger_spec.rb \
  spec/custom/services/custom/inboxes/history_migration_service_spec.rb \
  spec/custom/controllers/custom/api/v1/accounts/inboxes_controller_move_history_spec.rb
```

### Go-live

1. `bundle exec rails db:migrate` (migration `20260725120824_fork_create_inbox_history_migrations`)
2. Restart web + Sidekiq worker
3. `assets:precompile` se necessário (aba Vue nova)
4. Smoke: Settings inbox WhatsApp → Move history → escolher destino → confirmar

---

## Project Rules Applied

| Regra | Aplicação |
|-------|-----------|
| `custom/` | Model, services, job, Vue page |
| `# FORK:` / `// FORK:` mínimo | routes, except list, Settings import/tab, API client |
| Um service = uma ação | Guard / Remounter / Merger / Orchestrator |
| i18n EN only | `en.yml` + `inboxMgmt.json` |
| Specs em `spec/custom/` | Mirror do overlay |

---

*Última atualização: 25/jul/2026*
