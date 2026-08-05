# Conversation Workflow Rules — Documentação

Evolução de **Fluxos de Conversa**: regras configuráveis de resolução automática e escalonamento quando o agente não responde, com filtro por caixa de entrada, condições e ações no estilo Automação.

**Estado:** implementado (Fases 1–4) — regras CRUD em menu independente **Regras de conversa** (`/settings/conversation-rules`); legacy **Fluxo de Conversa** mantém auto-resolve + atributos obrigatórios.

| Área | Status |
|------|--------|
| Auto-resolve por inatividade (`last_activity_at`) | ✅ Regras `conversation_inactivity` + migração legacy |
| Atributos obrigatórios na resolução | ✅ `Custom::Conversations::ResolveService` (Fase 4) |
| Filtro por inbox + condições | ✅ Fase 2 |
| Múltiplas ações | ✅ `Custom::ConversationWorkflow::ActionService` |
| Gatilho “agente não respondeu” (`waiting_since`) | ✅ `agent_no_reply` + flag `conversation_agent_no_reply_rules` |
| Gatilhos estendidos (jun/2026) | ✅ `first_response_overdue`, `unassigned_too_long`, `pending_stale`, `customer_no_reply` |
| Eventos sintéticos na Automação (6 eventos) | ✅ Fase 4 — `conversation_inactivity_threshold`, `conversation_agent_no_reply`, `conversation_first_response_overdue`, `conversation_unassigned_too_long`, `conversation_pending_stale`, `conversation_customer_no_reply` |
| Business hours | ✅ `BusinessHoursElapsedCalculator` (opt-in por regra) |
| Job per-message | ✅ `ScheduleOnMessageJob` + `ScheduleOnMessageScheduler` (dedup Redis por epoch — previne re-agendamento no mesmo episódio) |

---

## Go-live checklist

1. Habilitar feature flags na conta: `auto_resolve_conversations` e/ou `conversation_agent_no_reply_rules`
2. Rodar migrations em produção (`conversation_workflow_rules`, `conversation_workflow_rule_executions`)
3. Migrar legacy (UI banner **Migrar agora** ou `rake conversation_workflow:migrate_legacy`) se `auto_resolve_after > 0`
4. `assets:precompile` + restart web/worker (PM2)
5. Smoke test: `/settings/conversation-rules` — listar, criar, editar, clonar, reordenar; legacy em `/settings/conversation-workflow` inalterado

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Implementar / manter** | [implementation-plan.md](./implementation-plan.md) |
| **Por que esta abordagem** | [implementation-decision-tree.md](./implementation-decision-tree.md) |
| **Regras de negócio** | [business-rules.md](./business-rules.md) |
| **Estado atual do código** | [current-state.md](./current-state.md) |
| **Histórico da reavaliação** | [improvements-backlog.md](./improvements-backlog.md) |

---

## Objetivos do produto

1. **Várias regras** por conta (não config global única).
2. Seis gatilhos temporais (ver [business-rules.md](./business-rules.md) §1):
   - Inatividade / cliente não respondeu (`auto_resolve_conversations`)
   - Agente não respondeu / first response / unassigned / pending stale (`conversation_agent_no_reply_rules`)
3. Filtro por **inbox** + **condições** (assignee, team, labels, priority).
4. **Múltiplas ações** via `Custom::ConversationWorkflow::ActionService` (wrapper sobre `ActionService`).
5. **Escalonamento em níveis** = múltiplas regras com durações distintas.
6. Migração segura de `auto_resolve_*` legacy com guard anti-duplo job.
7. Fork: `custom/` + `# FORK:` mínimo upstream.

---

## Decisões fechadas

### Arquitetura (Fase 0)

| # | Decisão | Valor |
|---|---------|-------|
| T1 | Modelo | Opção A — tabela `conversation_workflow_rules` em `custom/` |
| T2 | Executor | `Custom::ConversationWorkflow::ActionService` (wrapper, não `ActionService` cru) |
| T3 | Multi-regra | **Todas** as regras matching executam (não first-match), salvo dedup |
| T4 | Legacy job | Skip `ResolutionJob` quando `workflow_rules_migrated_at` presente |
| T5 | Condições | Fase 2 — `assignee_id`, `team_id`, `labels`, `priority` |
| T6 | Status `agent_no_reply` | MVP: `open`; Fase 2.1: incluir `pending` pós-handoff bot |

### Produto e runtime

| Tópico | Decisão |
|--------|---------|
| Scheduler | Cron 5 min (todos os triggers); per-message em incoming (`agent_no_reply`, `first_response_overdue`) e outgoing (`customer_no_reply`) |
| Business hours | Opt-in por regra; **só cron** (delay Sidekiq não expressa horário útil) |
| Dedup waiting | `(rule_id, conversation_id, waiting_since_epoch)` — `agent_no_reply`, `first_response_overdue` |
| Dedup activity | `(rule_id, conversation_id, last_activity_epoch)` — inatividade, pending, unassigned, customer_no_reply |
| Tiered SLA | **Múltiplas regras** (ex.: 15 min / 2h / 24h), uma por tier |
| Feature flags | `auto_resolve_conversations` → inatividade + `customer_no_reply`; **`conversation_agent_no_reply_rules`** → waiting / unassigned / pending |
| `send_message` | Default **não** zera `waiting_since`; opt-in `counts_as_agent_reply` por ação |
| `send_message_to_contact` | Workflow-only: inbox + contato + template; SidePanel UX (chips, preview, templates, favoritos, confirm); skips em `conversation_workflow_rule_skips`; sem HSM WhatsApp |
| Activity audit | `Current.executed_by = ConversationWorkflowRule` + i18n |
| i18n | en + pt_BR |
| Required attrs | Fase 4 — `Custom::Conversations::ResolveService` + `skip_required_attributes` para sistema |
| SLA Enterprise | Escopo distinto — SLA = contrato; workflow = automação operacional |
| Automação UI (Opção D) | Fase 4 — 6 eventos sintéticos (um por trigger) |

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [current-state.md](./current-state.md) | Baseline + código implementado |
| [business-rules.md](./business-rules.md) | Regras normativas completas |
| [implementation-plan.md](./implementation-plan.md) | Fases 0–4, arquivos, migração, testes |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Opções A–D |
| [improvements-backlog.md](./improvements-backlog.md) | Log da reavaliação (incorporado nos docs acima) |

---

*Última atualização: ago/2026 — UX pack SidePanel + activity/skips*
