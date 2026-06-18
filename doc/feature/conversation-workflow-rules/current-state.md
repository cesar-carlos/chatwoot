# Conversation Workflow — Estado atual

Referência do código em jun/2026 após implementação das regras configuráveis.

---

## UI

| Item | Caminho |
|------|---------|
| Rota | `/accounts/:accountId/settings/conversation-workflow` |
| Página | `app/javascript/dashboard/routes/dashboard/settings/conversationWorkflow/index.vue` |
| Rules list + form | `app/javascript/dashboard/components-next/ConversationWorkflow/ConversationWorkflowRulesList.vue`, `ConversationWorkflowRuleForm.vue` |
| Auto-resolve (legacy) | `app/javascript/dashboard/routes/dashboard/settings/account/components/AutoResolve.vue` (oculto após migração) |
| Required attrs | `app/javascript/dashboard/components-next/ConversationWorkflow/ConversationRequiredAttributes.vue` |
| Sidebar | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` |
| Permissão | `administrator` |

A página monta:

- `ConversationWorkflowRulesList` (quando `auto_resolve_conversations` ou `conversation_agent_no_reply_rules`)
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
| `conversationWorkflow/index.vue` | mount rules list (feature-flag gated) |
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

*Última atualização: jun/2026 — pós-correções sprint 1–3*
