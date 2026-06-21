# Tarefas — Provider Evolution Go (planejamento)

**Fase atual:** documentação consolidada — spike runtime antes de código.

| ID | Tarefa | Status | Doc |
|----|--------|--------|-----|
| P0 | Reavaliação + melhorias documentação | ✅ feito | [gaps-and-improvements.md](./gaps-and-improvements.md) |
| P0b | ADR §22 global_api_key | ✅ fechado | [decisions.md §22](./decisions.md) |
| P0c | ADR §23 reconnect/webhook | ✅ fechado | [decisions.md §23](./decisions.md) |
| P0d | Runbook licença, wizard sequence, Node vs Go | ✅ feito | vários |
| P0e | `sync-documentation-links.sh` | ✅ criado | [documentation-links.md](./documentation-links.md) |
| P1 | Spike REST + fixtures | ❌ pendente | `spec/fixtures/evolution_go/` |
| P3 | Swagger: advanced-settings, Group paths | ⚠️ marcado no doc | spike only |
| I0 | Fase 0 infra | ❌ bloqueado por P1 | [implementation-plan.md](./implementation-plan.md) |
| I1 | Fase 1 MVP texto | ❌ bloqueado | idem |

---

## P1 — Spike (pré-implementação)

**Objetivo:** [validation-checklist.md](./validation-checklist.md) contra Evolution Go Docker.

**Entregas:**
- `spec/fixtures/evolution_go/*.json` (5 arquivos)
- `evolution-target-version.txt` com tag Docker
- Preencher tabelas em `spec/fixtures/evolution_go/README.md`
- Fechar G2/G3 em [gaps-and-improvements.md](./gaps-and-improvements.md)

**Env:** `evoapicloud/evolution-go:latest`, licença ativada, PostgreSQL

---

## P3 — Swagger audit (durante spike)

```bash
# Diff docs oficiais
./doc/feature/whatsapp-provider/evolution-go/sync-documentation-links.sh

# Inspecionar runtime
open "${BASE_URL}/swagger/index.html"
```

Confirmar: `advanced-settings`, paths Group/Chat.

---

## Dependências

```
P0 (doc) ──► P1 (spike) ──► I0 (Fase 0) ──► I1 (Fase 1)
```

Coordenação Node: [coordination-with-evolution-api.md](./coordination-with-evolution-api.md)
