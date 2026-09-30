# Conversation Workflow Rules — Árvore de Decisão

Comparação de abordagens arquiteturais antes/durante implementação.

**Atualizado set/2026**

---

## Pergunta central

> Onde modelar regras temporais (inatividade + agente não respondeu) e como executar ações?

```mermaid
flowchart TD
  Q[Regra temporal + ações]
  A[Opção A: Nova tabela + custom/]
  B[Opção B: Estender AutomationRule]
  C[Opção C: Estender accounts.settings]
  D[Opção D: Híbrido A + eventos Automação]

  Q --> A
  Q --> B
  Q --> C
  Q --> D

  A --> R[✅ Recomendado MVP]
  B --> M[⚠️ Possível Fase 3]
  C --> X[❌ Insuficiente]
  D --> R2[✅ Fase 3]
```

---

## Opção A — `conversation_workflow_rules` em `custom/` (RECOMENDADA)

**Ideia:** entidade dedicada, scheduler próprio, UI em **Regras de conversa**, ações via wrapper sobre `ActionService`.

| Prós | Contras |
|------|---------|
| Separação clara: temporal vs event-driven | Nova tabela + CRUD |
| Múltiplas regras, inbox, dedup nativos | Mais uma superfície para manter |
| Fork-friendly (`custom/` isolado) | Período de transição com legacy job |
| UI coesa no produto (“Regras de conversa”) | |

**Veredito:** ✅ implementada nas Fases 1–5.

---

## Opção B — Estender `AutomationRule` com `duration_minutes`

**Ideia:** adicionar campos temporais à tabela existente; scheduler avalia subset de rules.

| Prós | Contras |
|------|---------|
| Reusa CRUD, validação, UI de Automação | Mistura gatilhos síncronos e cron no mesmo modelo |
| Zero duplicação de action whitelist | UX confusa (“evento” vs “tempo”) |
| | Migration arriscada em tabela core upstream |
| | Fork: editar OSS/Enterprise automation |

**Veredito:** ⚠️ só considerar se quiser **uma única tela** de regras; custo alto para fork.

---

## Opção C — Continuar em `accounts.settings` (JSON)

**Ideia:** array de regras em `settings` como `conversation_workflow_rules: []`.

| Prós | Contras |
|------|---------|
| Zero migration de tabela | Sem dedup executions estruturado |
| Menor diff inicial | JSON grande, difícil CRUD/auditoria |
| | Não escala para múltiplas regras + histórico |
| | Validação fraca vs tabela |

**Veredito:** ❌ insuficiente para multi-regra + dedup.

---

## Opção D — Híbrido (A + eventos Automação Fase 4)

**Ideia:** scheduler dispara eventos `conversation_agent_no_reply` / `conversation_inactivity_threshold`; admin configura **ações** na UI Automação.

| Prós | Contras |
|------|---------|
| Uma engine de ações (Automação) | Duas telas para operação completa |
| Condições ricas sem duplicar UI | Mais moving parts no dispatcher |
| Admins power-users já conhecem Automação | |

**Veredito:** ✅ implementada na Fase 4 para ações complexas, sem substituir a entidade temporal dedicada.

---

## Decisões derivadas (incorporadas — ver README)

| # | Decisão | Valor |
|---|---------|-------|
| T1 | Modelo | **Opção A** — `conversation_workflow_rules` em `custom/` |
| T2 | Executor | `ConversationWorkflow::ActionService` |
| T3 | Multi-regra | Todas matching executam, salvo dedup |
| T4 | Legacy | `workflow_rules_migrated_at` → skip ResolutionJob |
| T5 | Condições | **Fase 2** — assignee, team, labels, priority |
| T6 | Status pending | MVP `open`; Fase 2.1 inclui `pending` |

## Validação pós-implementação (set/2026)

O hardening confirmou a Opção A e não alterou a fronteira arquitetural:

| Achado | Resposta dentro da Opção A |
|--------|----------------------------|
| Candidatos já deduplicados bloqueavam o batch | Keyset pagination no executor dedicado |
| Business hours podiam truncar após dias fechados | Calculator dedicado percorre até o threshold |
| Filtro upstream exige contrato de `AutomationRule` | Adapter local expõe conta e normaliza condições |
| Migração podia deixar regra sem marcador | Serviço dedicado usa lock e transação |
| Form podia disparar persistências concorrentes | Estado `isSaving` no SidePanel |

---

*Última atualização: set/2026 — Opção A reafirmada após hardening de execução*
