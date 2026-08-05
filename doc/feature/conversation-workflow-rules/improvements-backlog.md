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
| Review fixes ago/2026 (P0–P2) | — | FK delete cascade, `preview_count?`, SQL qualify, BH prefilter×3 + order, matcher FR, ActionService re-raise, legacy guard, reorder tab gate, allowlist FE, migrate refresh, trigger warning, BH preload, pt_BR sidebar |
| `send_message_to_contact` | — | ago/2026 — business-rules §3.2–3.3 · current-state ActionService + WorkflowContactMessageInput |
| UX pack SidePanel + activity/skips | — | ago/2026 — SidePanel form, chips/templates/favoritos, confirm save, `conversation_workflow_rule_skips`, `GET activity`, badge skips |

---

## Fora de escopo (ainda aberto)

| Item | Nota |
|------|------|
| Preview count até 10k rows | Custo/benefício alto; não atacado na rodada ago/2026 |
| Índices DB novos / pending statuses | Documentado; não nesta entrega |
| Reorder transaction + reject unknown IDs | P3 auditoria |
| HSM WhatsApp / templates oficiais | Fora do `send_message_to_contact` (texto livre) |
| Auditoria com filtros/paginação | Só últimas 10 executions/skips |

---

## Resumo executivo (reavaliação original)

| Veredito | Detalhe |
|----------|---------|
| Direção geral | ✅ Sólida |
| Maior gap corrigido no plano | Wrapper + guard legacy |
| Quick win | Condições assignee null na Fase 2 — ✅ `is_present` / `is_not_present` em assignee/team |
| Tiered SLA | Múltiplas regras, não engine de tiers |

---

*Última atualização: ago/2026 — UX pack SidePanel + activity/skips*
