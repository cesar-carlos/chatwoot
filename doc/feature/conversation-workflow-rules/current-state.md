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
- `TriggerCardSelector.vue` — cards selecionáveis por trigger type (6 tipos)
- `DurationPresets.vue` — botões de preset de duração rápida
- `FormSection.vue`, `FormSwitchRow.vue`

---

## UI

| Item | Caminho |
|------|---------|
| **Regras de conversa (rules CRUD)** | `/accounts/:accountId/settings/conversation-rules` |
| Gatilhos (6 tipos) | `conversation_inactivity`, `agent_no_reply`, `first_response_overdue`, `unassigned_too_long`, `pending_stale`, `customer_no_reply` |
| UX gatilhos | Cards selecionáveis, labels contextuais de duração, presets, preview `POST preview_count`, abas na lista |
| Página rules | `app/javascript/dashboard/routes/dashboard/settings/conversationRules/index.vue` |
| Rules list + row + form | `conversationRules/components/ConversationRulesList.vue`, `ConversationRuleRow.vue`, `ConversationRuleForm.vue`, `TriggerCardSelector.vue`, `DurationPresets.vue` |
| Helpers / form UI | `conversationRules/helpers/durationHelper.js`, `i18nHelper.js`, `triggerHelper.js`, `FormSection.vue`, `FormSwitchRow.vue`, `ConversationRulesEmptyState.vue`, `ConversationRulesFeatureDisabled.vue` |
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
| Account mixin | `custom/app/models/custom/account.rb` — `has_many`, `workflow_rules_migrated?` |
| Message hook | `custom/app/models/custom/message.rb` + `custom/app/models/custom/message/workflow_rules_scheduler.rb` |
| Scheduler | `custom/app/jobs/custom/conversation_workflow/scheduler_job.rb` |
| Per-message job | `custom/app/jobs/custom/conversation_workflow/schedule_on_message_job.rb` |
| Per-message scheduler | `custom/app/services/custom/conversation_workflow/schedule_on_message_scheduler.rb` — incoming (`agent_no_reply`, `first_response_overdue`) + outgoing (`customer_no_reply`); skip se `respect_business_hours`; dedup Redis por epoch |
| Indexes | `index_conv_workflow_waiting`, `_inactivity`, `_pending_stale`, `_unassigned` |
| Preview API | `POST /conversation_workflow_rules/preview_count` |
| Account processor | `custom/app/services/custom/conversation_workflow/account_processor.rb` — itera regras com gate de feature flag |
| Executor | `custom/app/services/custom/conversation_workflow/rule_executor.rb` |
| Action wrapper | `custom/app/services/custom/conversation_workflow/action_service.rb` — `< AutomationRules::ActionService`; webhook prefix `workflow_rule.*` |
| Scope matcher | `custom/app/services/custom/conversation_workflow/scope_matcher.rb` — elegibilidade por conversa pós-SQL |
| Threshold matcher | `custom/app/services/custom/conversation_workflow/threshold_matcher.rb` — duration calendar ou business hours |
| Reference timestamp | `custom/app/services/custom/conversation_workflow/reference_timestamp.rb` — timestamp de referência + atributos de dedup por trigger |
| Conditions filter | `custom/app/services/custom/conversation_workflow/conditions_filter.rb` → `AutomationRules::ConditionsFilterService` |
| Conditions adapter | `custom/app/services/custom/conversation_workflow/conditions_rule_adapter.rb` — duck-typing de regra como AutomationRule |
| Template sender | `custom/app/services/custom/conversation_workflow/template_message_sender.rb` — `MessageTemplates::Template::AutoResolve` |
| Migrate legacy | `custom/app/services/custom/conversation_workflow/migrate_legacy_service.rb` |
| Preview count | `custom/app/services/custom/conversation_workflow/preview_count_service.rb` |
| Business hours | `custom/app/services/custom/conversation_workflow/business_hours_elapsed_calculator.rb` — minutos úteis via `inbox.working_hours` |
| Automation events | `custom/app/services/custom/conversation_workflow/automation_event_dispatcher.rb` — eventos sintéticos |
| Scopes (6) | `custom/app/services/custom/conversation_workflow/scopes/` — `inactivity_scope.rb`, `agent_no_reply_scope.rb`, `first_response_overdue_scope.rb`, `unassigned_too_long_scope.rb`, `pending_stale_scope.rb`, `customer_no_reply_scope.rb` |
| Resolve | `custom/app/services/custom/conversations/resolve_service.rb` |
| API | `custom/app/controllers/api/v1/accounts/conversation_workflow_rules_controller.rb` |
| Policy | `custom/app/policies/conversation_workflow_rule_policy.rb` |
| Rake migrate | `lib/tasks/conversation_workflow.rake` (`conversation_workflow:migrate_legacy`) |

**Scheduler:** `TriggerScheduledItemsJob` (cron `*/5 * * * *`) → `Custom::ConversationWorkflow::SchedulerJob` → `AccountProcessor` → `RuleExecutor` (+ legacy `Account::ConversationsResolutionSchedulerJob`, skip se migrado).

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

Eventos sintéticos disparados após match de workflow rule (`AutomationEventDispatcher`):

| Trigger | Evento Automação |
|---------|------------------|
| `conversation_inactivity` | `conversation_inactivity_threshold` |
| `agent_no_reply` | `conversation_agent_no_reply` |
| `first_response_overdue` | `conversation_first_response_overdue` |
| `unassigned_too_long` | `conversation_unassigned_too_long` |
| `pending_stale` | `conversation_pending_stale` |
| `customer_no_reply` | `conversation_customer_no_reply` |

Constantes em `automation/constants.js` e `conversationRules/constants.js` (`WORKFLOW_AUTOMATION_EVENTS`).

---

## FORK upstream

| Arquivo | Alteração |
|---------|-----------|
| `app/jobs/trigger_scheduled_items_job.rb` | `Custom::ConversationWorkflow::SchedulerJob.perform_later` |
| `app/jobs/account/conversations_resolution_scheduler_job.rb` | skip se `account.workflow_rules_migrated?` |
| `app/jobs/conversations/resolution_job.rb` | early return se `account.workflow_rules_migrated?` |
| `config/routes.rb` | `resources :conversation_workflow_rules` (+ `reorder`, `migrate_legacy`, `preview_count`) |
| `config/features.yml` | flag `conversation_agent_no_reply_rules` |
| `app/services/message_templates/template/auto_resolve.rb` | optional `message:` override para reuso do template |
| `app/javascript/dashboard/helper/featureHelper.js` | entrada `conversation_rules` (feature helper) |
| `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` | eventos sintéticos (`conversation_inactivity_threshold`, `conversation_agent_no_reply`, etc.) |
| `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` | import + spread `conversationRules.routes` |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | entrada **Regras de conversa** (`conversation_rules_index`, feature-flag gated) |
| `app/javascript/dashboard/routes/dashboard/settings/conversationWorkflow/index.vue` | legacy AutoResolve + Required Attributes only |
| `app/javascript/dashboard/routes/dashboard/settings/conversationRules/index.vue` | mount rules list (feature-flag gated) |

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

## Correções pós-reavaliação (jun/2026)

| Área | Correção |
|------|----------|
| `ScopeMatcher` | Reescrito com `case/when` por trigger type — `pending_stale` e `customer_no_reply` estavam silenciosamente quebrados |
| `useWorkflowRule.js` | `buildPayload` e `watch(trigger_type)`: `pending_stale` agora salva `statuses: ['pending']` (era `['open']`) |
| `ScheduleOnMessageScheduler` | Chave Redis inclui epoch do `reference_time` — permite re-agendar novo episódio sem esperar TTL expirar |
| `ScheduleOnMessageJob` | Aceita `reference_epoch:` para deletar a chave Redis correta no `ensure` |
| Dead code | `ConversationWorkflowRuleExecution#already_executed?` removido — dedup usa insert-first |
| `RuleExecutor` | Guards redundantes removidos de `conversation_eligible?`; `customer_waiting_on_agent_reply?` movido para `ScopeMatcher` |

---

## Deploy

Checklist obrigatório antes de go-live:

1. **Migrations** — `RAILS_ENV=production bundle exec rails db:migrate` (tabelas `conversation_workflow_rules`, `conversation_workflow_rule_executions`, índices em `conversations`)
2. Verificar: `RAILS_ENV=production bundle exec rails runner "puts ConversationWorkflowRule.table_exists?"`
3. **Assets** — `RAILS_ENV=production bundle exec rails assets:precompile`
4. **Processos** — `pm2 restart chatwoot-web chatwoot-worker`
5. Hard-refresh no browser; smoke test em `/settings/conversation-rules` (GET API 200, criar/editar regra)

---

## Runtime: per-message vs cron

| Trigger | Per-message | Cron (*/5) | Notas |
|---------|:-----------:|:----------:|-------|
| `agent_no_reply` | ✅ incoming | ✅ | Skip se `respect_business_hours` |
| `first_response_overdue` | ✅ incoming | ✅ | Skip se já houve first reply |
| `customer_no_reply` | ✅ outgoing | ✅ | Skip se `respect_business_hours` |
| `conversation_inactivity` | ❌ | ✅ | Só cron |
| `unassigned_too_long` | ❌ | ✅ | Só cron; limpa dedup ao assign (`clear_unassigned_too_long_for!`) |
| `pending_stale` | ❌ | ✅ | Só cron |
| Qualquer + `respect_business_hours` | ❌ | ✅ | Delay Sidekiq não expressa horário útil |

## Índices de conversa (scheduler)

| Índice | WHERE | Triggers |
|--------|-------|----------|
| `index_conv_workflow_waiting` | `status = 0 AND waiting_since IS NOT NULL` | agent_no_reply, first_response_overdue |
| `index_conv_workflow_inactivity` | `status = 0` | conversation_inactivity |
| `index_conv_workflow_pending_stale` | `status = 2` | pending_stale |
| `index_conv_workflow_unassigned` | `status = 0 AND assignee_id IS NULL` | unassigned_too_long |

`customer_no_reply` usa subquery em `messages` (sem índice dedicado).

## Limitações conhecidas

| Limitação | Detalhe |
|-----------|---------|
| `BULK_ACTIONS_LIMIT` | 100 conversas por execução do scheduler / regra |
| Cron backstop | `SchedulerJob` a cada 5 min (complementa job per-message) |
| Business hours | Sem per-message — atraso até ~5 min após threshold em horário útil |
| `send_attachment` | Não suportado — oculto na UI; ação loga warning se presente via API |
| `ActionService` | Erros por ação engolidos (`StandardError`) — sem feedback ao admin na UI |
| Histórico de execuções | Tabela `conversation_workflow_rule_executions` existe; sem UI de auditoria |

---

*Última atualização: jul/2026 — índices extended, runtime per-message vs cron, 6 eventos Automação*
