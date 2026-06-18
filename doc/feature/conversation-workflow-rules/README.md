# Conversation Workflow Rules — Documentação

Evolução de **Fluxos de Conversa**: regras configuráveis de resolução automática e escalonamento quando o agente não responde, com filtro por caixa de entrada, condições e ações no estilo Automação.

**Estado:** implementado (Fases 1–4)

| Área | Status |
|------|--------|
| Auto-resolve por inatividade (`last_activity_at`) | ✅ Regras `conversation_inactivity` + migração legacy |
| Atributos obrigatórios na resolução | ✅ `Custom::Conversations::ResolveService` (Fase 4) |
| Filtro por inbox + condições | ✅ Fase 2 |
| Múltiplas ações | ✅ `Custom::ConversationWorkflow::ActionService` |
| Gatilho “agente não respondeu” (`waiting_since`) | ✅ `agent_no_reply` + flag `conversation_agent_no_reply_rules` |
| Eventos sintéticos na Automação | ✅ Fase 4 |
| Business hours | ✅ `BusinessHoursElapsedCalculator` (opt-in por regra) |
| Job per-message | ✅ `ScheduleOnMessageJob` em incoming |

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
2. Dois gatilhos temporais:
   - **Inatividade geral** (`last_activity_at`)
   - **Agente não respondeu** (`waiting_since`)
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
| Scheduler | Cron 5 min; job per-message em incoming (Fase 3) |
| Dedup `agent_no_reply` | `(rule_id, conversation_id, waiting_since_epoch)` |
| Dedup inatividade | Chave por `last_activity_at_epoch` |
| Tiered SLA | **Múltiplas regras** (ex.: 15 min / 2h / 24h), uma por tier |
| Feature flags | `auto_resolve_conversations` → inatividade; **`conversation_agent_no_reply_rules`** → agente não respondeu |
| `send_message` | Default **não** zera `waiting_since`; opt-in `counts_as_agent_reply` por ação |
| Activity audit | `Current.executed_by = ConversationWorkflowRule` + i18n |
| i18n | en + pt_BR |
| Required attrs | Fase 4 — `Custom::Conversations::ResolveService` + `skip_required_attributes` para sistema |
| SLA Enterprise | Escopo distinto — SLA = contrato; workflow = automação operacional |
| Automação UI (Opção D) | Fase 4 — eventos sintéticos `conversation_inactivity_threshold`, `conversation_agent_no_reply` |

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

*Última atualização: jun/2026 — implementação Fases 1–4 concluída*
