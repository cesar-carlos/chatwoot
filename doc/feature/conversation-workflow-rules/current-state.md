# Conversation Workflow — Estado atual

Referência do código em jun/2026 após menu independente **Regras de conversa**, refactor UX e correções pós-sprint.

---

## Menu independente + UX

| Item | Detalhe |
|------|---------|
| Menu sidebar | **Regras de conversa** → `/settings/conversation-rules` (CRUD de regras) |
| Legacy | **Fluxo de Conversa** → `/settings/conversation-workflow` (auto-resolve + atributos obrigatórios) |
| i18n | Namespace `CONVERSATION_RULES` (en + pt_BR) |
| UX | Empty state, busca com contador filtrado (`COUNT_FILTERED`), cards enriquecidos, form por seções, migração com confirmação, clone client-side |
| SLA exemplo | `helpers/i18nHelper.js` — `getTieredSlaExample(tm)` evita bug de `t(returnObjects)` |
| `send_attachment` | Oculto na UI (`DISALLOWED_ACTIONS`); backend não executa |

Componentes em `conversationRules/components/`:

- `ConversationRulesList.vue` — draggable rows, legacy/migrate banners, modals
- `ConversationRuleForm.vue` — seções (Identificação, Gatilho, Escopo, Condições, Ações)
- `ConversationRuleRow.vue`, `ConversationRulesEmptyState.vue`, `ConversationRulesFeatureDisabled.vue`
- `FormSection.vue`, `FormSwitchRow.vue`

---

## UI

| Item | Caminho |
|------|---------|
| **Regras de conversa (rules CRUD)** | `/accounts/:accountId/settings/conversation-rules` |
| Gatilhos (6 tipos) | `conversation_inactivity`, `agent_no_reply`, `first_response_overdue`, `unassigned_too_long`, `pending_stale`, `customer_no_reply` |
| UX gatilhos | Cards selecionáveis, labels contextuais de duração, presets, preview `POST preview_count`, abas na lista |
| Página rules | `app/javascript/dashboard/routes/dashboard/settings/conversationRules/index.vue` |
| Rules list + row + form | `conversationRules/components/ConversationRulesList.vue`, `ConversationRuleRow.vue`, `ConversationRuleForm.vue` |
| Helpers / form UI | `conversationRules/helpers/durationHelper.js`, `i18nHelper.js`, `FormSection.vue`, `FormSwitchRow.vue`, `ConversationRulesEmptyState.vue`, `ConversationRulesFeatureDisabled.vue` |
| **Fluxo de Conversa (legacy)** | `/accounts/:accountId/settings/conversation-workflow` |
| Página legacy | `app/javascript/dashboard/routes/dashboard/settings/conversationWorkflow/index.vue` |
| Auto-resolve (legacy) | `app/javascript/dashboard/routes/dashboard/settings/account/components/AutoResolve.vue` (oculto após migração; banner → conversation-rules) |
| Required attrs | `app/javascript/dashboard/components-next/ConversationWorkflow/ConversationRequiredAttributes.vue` |
| Sidebar | `Sidebar.vue` — **Fluxo de Conversa** + **Regras de conversa** (oculto se ambas feature flags off) |
| Permissão | `administrator` |
| featureHelper | `conversation_rules` (`// FORK:` — doc interna, sem URL pública) |

**Regras de conversa** (`conversation_rules_index`):

- `index.vue` — `SettingsLayout` (loading), `BaseSettingsHeader` (search, count, add), empty state, feature-disabled card
- `ConversationRulesList` — draggable rows, legacy/migrate banners, modals
- `ConversationRuleForm` — seções (Identificação, Gatilho, Escopo, Condições, Ações), `DurationInput` com unidade, validação inline

**Fluxo de Conversa** (`conversation_workflow_index`):

- `auto_resolve_conversations` → `AutoResolve` (até `workflow_rules_migrated_at`)
- `conversation_required_attributes` → `ConversationRequiredAttributes`

---

## Workflow rules (backend)

| Item | Caminho |
|------|---------|
| Model | `custom/app/models/conversation_workflow_rule.rb` |
| Executions (dedup) | `custom/app/models/conversation_workflow_rule_execution.rb` |
| Scheduler | `custom/app/jobs/custom/conversation_workflow/scheduler_job.rb` |
| Per-message | `custom/app/jobs/custom/conversation_workflow/schedule_on_message_job.rb` |
| Per-message scheduler | `schedule_on_message_scheduler.rb` — incoming (`agent_no_reply`, `first_response_overdue`) + outgoing (`customer_no_reply`) |
| Preview API | `POST /conversation_workflow_rules/preview_count` |
| Executor | `custom/app/services/custom/conversation_workflow/rule_executor.rb` |
| Action wrapper | `custom/app/services/custom/conversation_workflow/action_service.rb` |
| Scopes | `scopes/inactivity_scope.rb`, `scopes/agent_no_reply_scope.rb` |
| Conditions | `conditions_filter.rb` → `AutomationRules::ConditionsFilterService` |
| Business hours | `business_hours_elapsed_calculator.rb` |
| Resolve | `custom/app/services/custom/conversations/resolve_service.rb` |
| Automation events | `automation_event_dispatcher.rb` |
| API | `custom/app/controllers/api/v1/accounts/conversation_workflow_rules_controller.rb` |
| Policy | `custom/app/policies/conversation_workflow_rule_policy.rb` |
| Rake migrate | `lib/tasks/conversation_workflow.rake` (`conversation_workflow:migrate_legacy`) |

**Scheduler:** `TriggerScheduledItemsJob` (cron `*/5 * * * *`) → `Custom::ConversationWorkflow::SchedulerJob` + legacy `Account::ConversationsResolutionSchedulerJob` (skip se migrado).

**Feature flags:** `auto_resolve_conversations`, `conversation_agent_no_reply_rules`.

---

## Auto-resolve (legacy)

Continua em `accounts.settings` (`auto_resolve_*`). Após `rake conversation_workflow:migrate_legacy`, `workflow_rules_migrated_at` desliga `Conversations::ResolutionJob` para a conta.

---

## `waiting_since`

Campo em `conversations.waiting_since`. Usado por:

- Fila “Não atendidas” (UI)
- Scope `agent_no_reply` em workflow rules
- Dedup por `waiting_since_epoch`

---

## Required attributes na resolução

| Item | Detalhe |
|------|---------|
| Storage | `accounts.settings.conversation_required_attributes[]` (Enterprise) |
| Runtime humano | Frontend — `ResolveAction.vue`, `ChatList.vue` |
| Runtime sistema | `Custom::Conversations::ResolveService` com `skip_required_attributes: true` |

---

## Automação (integração Fase 4)

Eventos sintéticos disparados após match de workflow rule:

- `conversation_inactivity_threshold`
- `conversation_agent_no_reply`

Constantes em `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` (`// FORK:`).

---

## FORK upstream

| Arquivo | Alteração |
|---------|-----------|
| `app/jobs/trigger_scheduled_items_job.rb` | `Custom::ConversationWorkflow::SchedulerJob.perform_later` |
| `app/jobs/account/conversations_resolution_scheduler_job.rb` | skip se `workflow_rules_migrated_at` |
| `app/jobs/conversations/resolution_job.rb` | early return se migrado |
| `config/routes.rb` | `conversation_workflow_rules` CRUD |
| `config/features.yml` | `conversation_agent_no_reply_rules` |
| `conversationWorkflow/index.vue` | legacy AutoResolve + Required Attributes only |
| `conversationRules/index.vue` | mount rules list (feature-flag gated) |
| `settings.routes.js` | `// FORK:` import + spread `conversationRules.routes` |
| `Sidebar.vue` | `// FORK:` sidebar entry **Regras de conversa** |
| `app/services/message_templates/template/auto_resolve.rb` | optional `message:` for workflow template reuse |

---

## Pós-correções (sprints 1–3)

| Área | Correção |
|------|----------|
| `Current.executed_by` | `RuleExecutor#execute_pipeline` owns lifecycle; workflow `ActionService` does not reset |
| Resolve | `ResolveService` uses `update!(status: :resolved)` — pending resolves correctly |
| Actions | `ActionService < AutomationRules::ActionService`; webhook prefix `workflow_rule.*` |
| Per-message scope | `ScopeMatcher` applied in `perform_for_conversation` |
| Dedup | insert-first via `claim_execution!` + `RecordNotUnique` |
| UI conditions | `ConditionRow` bindings + `workflowFilterTypes` mirror automation form |
| UX | reorder (vuedraggable), delete/toggle modals, validation, feature flags, unattended route/count |
| Legacy guard | `legacy_auto_resolve_active` on create + `POST migrate_legacy` + banner |
| Template | `TemplateMessageSender` delegates to `MessageTemplates::Template::AutoResolve` |
| Specs | `spec/custom/**` + extended legacy job specs |

---

## Deploy

Checklist obrigatório antes de go-live:

1. **Migrations** — `RAILS_ENV=production bundle exec rails db:migrate` (tabelas `conversation_workflow_rules`, `conversation_workflow_rule_executions`, índices em `conversations`)
2. Verificar: `RAILS_ENV=production bundle exec rails runner "puts ConversationWorkflowRule.table_exists?"`
3. **Assets** — `RAILS_ENV=production bundle exec rails assets:precompile`
4. **Processos** — `pm2 restart chatwoot-web chatwoot-worker`
5. Hard-refresh no browser; smoke test em `/settings/conversation-rules` (GET API 200, criar/editar regra)

---

## Limitações conhecidas

| Limitação | Detalhe |
|-----------|---------|
| `BULK_ACTIONS_LIMIT` | 100 conversas por execução do scheduler |
| Cron backstop | `SchedulerJob` a cada 5 min (complementa job per-message) |
| `send_attachment` | Não suportado — oculto na UI; ação loga warning se presente via API |
| `ActionService` | Erros por ação engolidos (`StandardError`) — sem feedback ao admin na UI |
| Histórico de execuções | Tabela `conversation_workflow_rule_executions` existe; sem UI de auditoria |

---

*Última atualização: jun/2026 — 6 gatilhos, UX cards/presets/preview, abas na lista*
