# Conversation Workflow Rules — Backlog de melhorias

> **Status: incorporado.** Itens P0–P2 foram mergeados em [business-rules.md](./business-rules.md) e [implementation-plan.md](./implementation-plan.md). Este arquivo permanece como log da reavaliação.

---

## Mapa de incorporação

| Item | Prioridade | Onde foi incorporado |
|------|------------|----------------------|
| Wrapper `ConversationWorkflow::ActionService` | P0 | business-rules §3.1 · implementation-plan § Backend |
| Guard duplo job legacy | P0 | business-rules §5 · implementation-plan § FORK + migration |
| Condições Fase 2 | P0 | business-rules §2.2 · implementation-plan Fase 2 |
| Semântica `waiting_since` | P0 | business-rules §1.3 · Fase 2.1 |
| Índices compostos | P0 | implementation-plan § Data model |
| Tiered SLA = N regras | P1 | business-rules §2.3 · README decisões |
| Feature flag `conversation_agent_no_reply_rules` | P1 | business-rules §8 · implementation-plan |
| Link UI Não atendidas | P1 | implementation-plan Fase 2.5 |
| Activity message + executed_by | P1 | business-rules §6 · implementation-plan 1.3 |
| `counts_as_agent_reply` | P1 | business-rules §3.2 · implementation-plan Fase 2.6 |
| Job per-message | P2 | implementation-plan Fase 3.2 |
| Business hours | P2 | business-rules §7 · implementation-plan Fase 3.1 |
| ResolveService + required attrs | P2 | business-rules §7 · implementation-plan Fase 4.1 |
| Fronteira SLA Enterprise | P2 | business-rules §7 · implementation-plan Fase 4.4 |
| Opção D Automação | P2 | implementation-plan Fase 4.3 · decision-tree |
| UX refactor + menu split | — | jun/2026 — `conversationRules/` components, sidebar independente, `tm()` tiered SLA fix |
| ScheduleOnMessageScheduler | — | jun/2026 — delay desde `waiting_since`, dedup Redis, specs |
| Gatilhos estendidos + UX | — | jun/2026 — 4 novos triggers, cards, presets, preview, abas lista |
| Índices pending/unassigned + docs runtime | — | jul/2026 — `index_conv_workflow_pending_stale`, `index_conv_workflow_unassigned`; docs 6 eventos Automação / per-message vs cron |

---

## Resumo executivo (reavaliação original)

| Veredito | Detalhe |
|----------|---------|
| Direção geral | ✅ Sólida |
| Maior gap corrigido no plano | Wrapper + guard legacy |
| Quick win | Condições assignee null na Fase 2 |
| Tiered SLA | Múltiplas regras, não engine de tiers |

---

*Última atualização: jul/2026 — índices extended + docs runtime*
