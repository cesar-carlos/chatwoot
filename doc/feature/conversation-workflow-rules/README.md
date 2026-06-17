# Conversation Workflow Rules — Documentação

Evolução de **Fluxos de Conversa**: regras configuráveis de resolução automática e escalonamento quando o agente não responde, com filtro por caixa de entrada, condições e ações no estilo Automação.

**Estado:** documentado (melhorias incorporadas) · implementação pendente

| Área | Status |
|------|--------|
| Auto-resolve por inatividade (`last_activity_at`) | ✅ Existe (settings globais) → migrar para regras |
| Atributos obrigatórios na resolução | ✅ Existe (Enterprise, frontend-only) — integração Fase 4 |
| Filtro por inbox + condições | 📋 Planejado Fase 2 |
| Múltiplas ações | 📋 Planejado Fase 1–2 |
| Gatilho “agente não respondeu” (`waiting_since`) | 📋 Planejado Fase 1–2 |
| Eventos sintéticos na Automação | 📋 Planejado Fase 4 (opcional) |

---

## Por onde começar

| Perfil | Documento |
|--------|-----------|
| **Implementar** | [implementation-plan.md](./implementation-plan.md) |
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
4. **Múltiplas ações** via `ConversationWorkflow::ActionService` (wrapper sobre `ActionService`).
5. **Escalonamento em níveis** = múltiplas regras com durações distintas.
6. Migração segura de `auto_resolve_*` legacy com guard anti-duplo job.
7. Fork: `custom/` + `# FORK:` mínimo upstream.

---

## Decisões fechadas

### Arquitetura (Fase 0)

| # | Decisão | Valor |
|---|---------|-------|
| T1 | Modelo | Opção A — tabela `conversation_workflow_rules` em `custom/` |
| T2 | Executor | `ConversationWorkflow::ActionService` (wrapper, não `ActionService` cru) |
| T3 | Multi-regra | **Todas** as regras matching executam (não first-match), salvo dedup |
| T4 | Legacy job | Skip `ResolutionJob` quando `workflow_rules_migrated_at` presente |
| T5 | Condições | Fase 2 — `assignee_id`, `team_id`, `labels`, `priority` |
| T6 | Status `agent_no_reply` | MVP: `open`; Fase 2.1: incluir `pending` pós-handoff bot |

### Produto e runtime

| Tópico | Decisão |
|--------|---------|
| Scheduler | Cron 5 min; Fase 4 opcional: job per-message |
| Dedup `agent_no_reply` | `(rule_id, conversation_id, waiting_since_epoch)` |
| Dedup inatividade | Conversa sai do scope após resolve; ou chave por `last_activity_at_epoch` |
| Tiered SLA | **Múltiplas regras** (ex.: 15 min / 2h / 24h), uma por tier |
| Feature flags | `auto_resolve_conversations` → inatividade; **`conversation_agent_no_reply_rules`** → agente não respondeu |
| `send_message` | Default **não** zera `waiting_since`; opt-in `counts_as_agent_reply` por ação |
| Activity audit | `Current.executed_by = ConversationWorkflowRule` + i18n |
| i18n | en + pt_BR |
| Required attrs | Fase 4 — `Conversations::ResolveService` + `skip_required_attributes` para sistema |
| SLA Enterprise | Escopo distinto — SLA = contrato; workflow = automação operacional |
| Automação UI (Opção D) | Fase 4 — eventos sintéticos após MVP estável |

### Decisões ainda em aberto

| # | Pergunta | Default recomendado |
|---|----------|---------------------|
| D4 | Filtro extra `first_reply_created_at IS NULL` em `agent_no_reply`? | Opcional por regra (Fase 2.1) |
| D1 | Expor eventos na UI Automação? | Sim, Fase 4 |

---

## Índice

| Documento | Conteúdo |
|-----------|----------|
| [current-state.md](./current-state.md) | Baseline do código |
| [business-rules.md](./business-rules.md) | Regras normativas completas |
| [implementation-plan.md](./implementation-plan.md) | Fases 0–4, arquivos, migração, testes |
| [implementation-decision-tree.md](./implementation-decision-tree.md) | Opções A–D |
| [improvements-backlog.md](./improvements-backlog.md) | Log da reavaliação (incorporado nos docs acima) |

---

*Última atualização: jun/2026 — melhorias P0–P2 incorporadas*
