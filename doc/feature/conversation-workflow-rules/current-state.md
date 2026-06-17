# Conversation Workflow — Estado atual

Referência do código em jun/2026 antes da evolução para regras configuráveis.

---

## UI

| Item | Caminho |
|------|---------|
| Rota | `/accounts/:accountId/settings/conversation-workflow` |
| Página | `app/javascript/dashboard/routes/dashboard/settings/conversationWorkflow/index.vue` |
| Auto-resolve | `app/javascript/dashboard/routes/dashboard/settings/account/components/AutoResolve.vue` |
| Required attrs | `app/javascript/dashboard/components-next/ConversationWorkflow/ConversationRequiredAttributes.vue` |
| Sidebar | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` |
| Permissão | `administrator` |

A página monta dois blocos condicionais por feature flag:

- `auto_resolve_conversations` → `AutoResolve`
- `conversation_required_attributes` → `ConversationRequiredAttributes`

---

## Auto-resolve (backend)

| Campo | Storage | Uso |
|-------|---------|-----|
| `auto_resolve_after` | `accounts.settings` | Minutos de inatividade |
| `auto_resolve_message` | idem | Template ao cliente antes de resolver |
| `auto_resolve_ignore_waiting` | idem | Exclui conversas com `waiting_since` |
| `auto_resolve_label` | idem | Uma etiqueta antes de resolver |

**Validação:** `AccountSettingsSchema` — mín. 10 min, máx. ~999 dias.

**Scheduler:** `TriggerScheduledItemsJob` (cron `*/5 * * * *`) → `Account::ConversationsResolutionSchedulerJob` → `Conversations::ResolutionJob`.

**Escopo atual:**

```ruby
# conversation_inactivity — scopes em Conversation
resolvable_not_waiting: open + last_activity_at old + waiting_since IS NULL
resolvable_all:         open + last_activity_at old
```

- Apenas status **`open`** (não `pending`, não `snoozed`)
- Exclui `contact_id: nil`
- Limite por execução: `Limits::BULK_ACTIONS_LIMIT`

**Pipeline fixo no job:**

1. `MessageTemplates::Template::AutoResolve` (se mensagem configurada)
2. `conversation.add_labels(auto_resolve_label)` (se configurada)
3. `conversation.toggle_status` → `resolved`

**Sem filtro por inbox.**

---

## `waiting_since` (existente, não usado em regras)

Campo em `conversations.waiting_since` (indexado).

| Evento | Efeito |
|--------|--------|
| Primeira mensagem incoming enquanto `waiting_since` blank | Define `waiting_since = created_at` |
| Cliente manda outra mensagem antes de resposta | **Não reinicia** — mantém timestamp original |
| Agente humano responde (`User` ou `external_echo`) | Zera (`nil`) |
| Bot / Captain responde | Zera (exceto `preserve_waiting_since: true`) |
| Nota privada | **Não zera** |
| Mensagem de automação (`automation_rule_id`) | **Não** conta como resposta humana |

**UI relacionada:** fila “Não atendidas” — `filterByUnattended` usa `!firstReplyOn || !!waitingSince`.

**Relatórios:** `ReportingEventListener#reply.created` usa `waiting_since` para reply time.

---

## Required attributes na resolução

| Item | Detalhe |
|------|---------|
| Storage | `accounts.settings.conversation_required_attributes[]` (Enterprise) |
| Config UI | `ConversationRequiredAttributes.vue` |
| Runtime | `useConversationRequiredAttributes.js` |
| Enforcement | **Somente frontend** — `ResolveAction.vue`, `ChatList.vue`, bulk parcial |

**Bypass (sem validação):** auto-resolve job, automação, macros, API, widget, Captain.

---

## Automação (referência para reuso)

| Item | Detalhe |
|------|---------|
| Modelo | `AutomationRule` — `conditions` + `actions` + `event_name` |
| Eventos | `conversation_created`, `conversation_updated`, `conversation_opened`, `conversation_resolved`, `message_created` |
| **Sem** evento temporal | Não cobre inatividade nem `waiting_since` |
| Condições | `AutomationRules::ConditionsFilterService` — inclui `inbox_id`, labels, assignee, etc. |
| Ações | `AutomationRules::ActionService` → `ActionService` |
| UI | `AutomationRuleForm.vue`, `ConditionRow.vue`, `AutomationActionInput.vue` |
| Constantes | `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` |

**Workaround parcial hoje:** regra em `conversation_resolved` dispara **após** auto-resolve, com filtro por inbox — não cobre “agente não respondeu” nem ações **antes** de resolver.

---

## Captain auto-resolve (Enterprise, escopo separado)

- Job: `Captain::InboxPendingConversationsResolutionJob`
- Alvo: conversas **`pending`** em inboxes Captain (não email)
- Cutoff: **1 hora fixa** (independente de `auto_resolve_after` da UI)
- Modos: `captain_auto_resolve_mode` — `evaluated`, `legacy`, `disabled`

Não confundir com regras de Fluxos de Conversa para agentes humanos.

---

## Lacunas vs objetivo

| Necessidade | Gap atual | Planejado |
|-------------|-----------|-----------|
| Regra por inbox | Não filtra | Fase 2 — `inbox_ids` |
| Múltiplas ações | Só `auto_resolve_label` | Fase 1–2 — `actions[]` + wrapper |
| Agente não respondeu | `waiting_since` não usado em jobs | Fase 1–2 — `agent_no_reply` |
| Múltiplas regras | 1 config global | Fase 1 — tabela dedicada |
| Condições | Não existem | Fase 2 — ConditionsFilterService |
| Legacy duplo job | Risco na transição | Fase 1 — `workflow_rules_migrated_at` |
| Feature flag agent_no_reply | Não existe | Fase 2 — nova flag |

Ver [implementation-plan.md](./implementation-plan.md) para estado alvo.

---

*Última atualização: jun/2026*
